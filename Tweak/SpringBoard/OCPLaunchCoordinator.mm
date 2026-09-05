// OpenCarPlay — xem OCPLaunchCoordinator.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPLaunchCoordinator.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>

#import "OCPAppRegistry.h"
#import "OCPCarPlayDetector.h"
#import "OCPLog.h"
#import "OCPPreferences.h"
#import "OCPProbe.h"
#import "OCPTransport.h"

/// SBSLaunchApplicationWithIdentifier(CFStringRef identifier, Boolean suspended) -> int
/// Symbol công khai của SpringBoardServices; 0 nghĩa là thành công.
typedef int (*OCPLaunchFunction)(CFStringRef, Boolean);

@interface OCPLaunchCoordinator ()
@property (nonatomic, copy, nullable) NSString *lastLaunchedBundleIdentifier;
@property (nonatomic, copy) NSArray<NSString *> *availableStrategies;
@property (nonatomic, assign) BOOL running;
@end

@implementation OCPLaunchCoordinator

+ (instancetype)sharedCoordinator {
    static OCPLaunchCoordinator *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _availableStrategies = @[];
    }
    return self;
}

#pragma mark - Các đường khởi chạy

/// Đường 1: hàm C của SpringBoardServices. Đơn giản nhất và ít phụ thuộc runtime nhất.
- (nullable OCPLaunchFunction)springBoardServicesLaunch {
    static OCPLaunchFunction function = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        function = (OCPLaunchFunction)dlsym(RTLD_DEFAULT, "SBSLaunchApplicationWithIdentifier");
        if (function == NULL) {
            OCPLogC(OCPLogCompatibility, @"không tìm thấy SBSLaunchApplicationWithIdentifier");
        }
    });
    return function;
}

/// Đường 2: FBSSystemService — API mà hệ thống dùng để mở ứng dụng.
- (nullable id)systemService {
    return [OCPProbe invokeClass:@"FBSSystemService" selector:@"sharedService"];
}

- (NSArray<NSString *> *)computeAvailableStrategies {
    NSMutableArray<NSString *> *strategies = [NSMutableArray array];
    if ([self springBoardServicesLaunch] != NULL) {
        [strategies addObject:@"SBSLaunchApplicationWithIdentifier"];
    }
    if ([self systemService] != nil) {
        [strategies addObject:@"FBSSystemService"];
    }
    return strategies;
}

#pragma mark - Vòng đời

- (void)start {
    if (_running) return;
    _running = YES;

    self.availableStrategies = [self computeAvailableStrategies];
    OCPLogError_(@"launch coordinator: %@",
                 self.availableStrategies.count
                     ? [self.availableStrategies componentsJoinedByString:@", "]
                     : @"KHÔNG có đường khởi chạy nào khả dụng");

    __weak typeof(self) weakSelf = self;
    [[OCPTransport sharedTransport] observeMessage:OCPMessageLaunchApplication
                                           handler:^(NSDictionary *payload) {
        NSString *bundleIdentifier = payload[@"bundleIdentifier"];
        if (![bundleIdentifier isKindOfClass:[NSString class]]) {
            OCPLogError_(@"yêu cầu khởi chạy thiếu bundleIdentifier");
            return;
        }
        OCPLaunchResult result =
            [weakSelf launchApplicationWithBundleIdentifier:bundleIdentifier];
        OCPLogError_(@"khởi chạy %@: %@", bundleIdentifier,
                     [OCPLaunchCoordinator nameForResult:result]);
    }];
}

#pragma mark - Khởi chạy

/// Ứng dụng có thật trên máy không. Trả YES nếu không kiểm tra được (để hệ thống
/// tự từ chối) — thà báo lỗi từ hệ thống còn hơn tự chặn nhầm.
- (BOOL)applicationIsInstalled:(NSString *)bundleIdentifier {
    id proxy = [OCPProbe invoke:[OCPProbe classNamed:@"LSApplicationProxy"]
                       selector:@"applicationProxyForIdentifier:"
                     withObject:bundleIdentifier];
    if (proxy == nil) return YES;

    id appState = [OCPProbe invoke:proxy selector:@"appState"];
    if (appState == nil) return YES;
    return [OCPProbe invokeBool:appState selector:@"isValid" fallback:YES];
}

- (OCPLaunchResult)launchApplicationWithBundleIdentifier:(nullable NSString *)bundleIdentifier {
    @try {
        // 1. Registry là cổng duy nhất. Danh sách chặn cứng được xét trong đó, nên
        //    một yêu cầu giả mạo qua IPC cũng không mở được process hệ thống.
        OCPRegistryDecision decision =
            [[OCPAppRegistry sharedRegistry] decisionForBundleIdentifier:bundleIdentifier];
        if (decision != OCPRegistryDecisionAllowed) {
            OCPLogError_(@"từ chối khởi chạy %@: %@", bundleIdentifier,
                         [OCPAppRegistry nameForDecision:decision]);
            return OCPLaunchResultRejected;
        }

        if (![self applicationIsInstalled:bundleIdentifier]) {
            return OCPLaunchResultNotInstalled;
        }

        if (self.availableStrategies.count == 0) {
            self.availableStrategies = [self computeAvailableStrategies];
        }
        if (self.availableStrategies.count == 0) {
            return OCPLaunchResultNoStrategy;
        }

        // 2. Thử đường 1.
        OCPLaunchFunction launch = [self springBoardServicesLaunch];
        if (launch != NULL) {
            int status = launch((__bridge CFStringRef)bundleIdentifier, false);
            if (status == 0) {
                self.lastLaunchedBundleIdentifier = bundleIdentifier;
                [self logPostLaunchState:bundleIdentifier via:@"SBSLaunchApplicationWithIdentifier"];
                return OCPLaunchResultSucceeded;
            }
            OCPLogC(OCPLogApplication, @"SBSLaunch... trả về %d, thử đường khác", status);
        }

        // 3. Thử đường 2.
        id service = [self systemService];
        if (service != nil) {
            id result = [OCPProbe invoke:service
                                selector:@"openApplication:"
                              withObject:bundleIdentifier];
            (void)result;
            self.lastLaunchedBundleIdentifier = bundleIdentifier;
            [self logPostLaunchState:bundleIdentifier via:@"FBSSystemService"];
            return OCPLaunchResultSucceeded;
        }

        return OCPLaunchResultSystemRefused;
    } @catch (NSException *exception) {
        OCPLogError_(@"khởi chạy %@ ném exception: %@ — %@",
                     bundleIdentifier, exception.name, exception.reason);
        return OCPLaunchResultSystemRefused;
    }
}

/// Ghi lại trạng thái sau khi khởi chạy. Đây là dữ liệu để viết Phase 9: nó cho biết
/// ứng dụng thực sự đi tới đâu và màn hình xe đang ở trạng thái nào.
- (void)logPostLaunchState:(NSString *)bundleIdentifier via:(NSString *)strategy {
    OCPLogError_(@"đã yêu cầu khởi chạy %@ qua %@", bundleIdentifier, strategy);

    BOOL carPlayConnected = [[OCPCarPlayDetector sharedDetector] isCarPlayConnected];
    OCPLogC(OCPLogApplication, @"CarPlay %@; ứng dụng sẽ hiện trên MÀN HÌNH IPHONE "
                               @"— gắn lên màn hình xe là việc của Phase 9",
            carPlayConnected ? @"đang kết nối" : @"không kết nối");
}

+ (NSString *)nameForResult:(OCPLaunchResult)result {
    switch (result) {
        case OCPLaunchResultSucceeded:      return @"thành công";
        case OCPLaunchResultRejected:       return @"bị từ chối bởi registry";
        case OCPLaunchResultNotInstalled:   return @"ứng dụng không có trên máy";
        case OCPLaunchResultNoStrategy:     return @"không có đường khởi chạy khả dụng";
        case OCPLaunchResultSystemRefused:  return @"hệ thống từ chối";
    }
    return @"không rõ";
}

@end
