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
#import "OCPCarPlayWindow.h"
#import "OCPDisplayConfiguration.h"
#import "OCPSceneBridge.h"
#import "OCPAudioObserver.h"
#import "OCPCrashGuard.h"

/// SBSLaunchApplicationWithIdentifier(CFStringRef identifier, Boolean suspended) -> int
/// Symbol công khai của SpringBoardServices; 0 nghĩa là thành công.
typedef int (*OCPLaunchFunction)(CFStringRef, Boolean);

@interface OCPLaunchCoordinator ()
@property (nonatomic, copy, nullable) NSString *lastLaunchedBundleIdentifier;
@property (nonatomic, copy) NSArray<NSString *> *availableStrategies;
@property (nonatomic, assign) BOOL running;
/// Chỉ tồn tại khi đang thực sự hiển thị ứng dụng trên màn hình xe.
@property (nonatomic, strong, nullable) OCPSceneBridge *sceneBridge;
@property (nonatomic, strong, nullable) OCPCarPlayWindow *carPlayWindow;
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

    // CarPlay rút dây khi đang hiển thị ứng dụng: phải dọn ngay, nếu không cửa sổ
    // trỏ tới một màn hình không còn tồn tại.
    [[NSNotificationCenter defaultCenter]
        addObserverForName:OCPCarPlayDidDisconnectNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        [weakSelf dismissHostedApplication];
    }];

    [[OCPTransport sharedTransport] observeMessage:OCPMessageDismissApplication
                                           handler:^(NSDictionary *payload) {
        [weakSelf dismissHostedApplication];
    }];

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

        // 2. Nếu được bật và đủ điều kiện, thử gắn ứng dụng lên MÀN HÌNH XE.
        //    Thất bại ở đây không phải lỗi nghiêm trọng — ta lùi về mở trên màn hình
        //    iPhone, tức hành vi của Phase 8.
        if ([self attemptSceneHostingFor:bundleIdentifier]) {
            self.lastLaunchedBundleIdentifier = bundleIdentifier;
            return OCPLaunchResultSucceeded;
        }

        // 3. Thử đường 1.
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

        // 4. Thử đường 2.
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

#pragma mark - Gắn lên màn hình xe (thử nghiệm)

/// Trả YES nếu ứng dụng đã hiện trên màn hình xe.
- (BOOL)attemptSceneHostingFor:(NSString *)bundleIdentifier {
    if (![[OCPPreferences sharedPreferences] experimentalSceneHosting]) return NO;

    // Dựng scene là thao tác rủi ro nhất trong tweak. Nếu lần trước SpringBoard chết
    // ở đây, tắt hẳn tính năng thay vì làm người dùng treo máy lần nữa.
    if (![OCPCrashGuard beginRiskyOperation:@"scene-hosting"
                        disablingPreference:@"ExperimentalSceneHosting"]) {
        return NO;
    }

    if (![OCPSceneBridge isSupported]) {
        OCPLogError_(@"scene hosting bật nhưng thiếu tiền đề: %@ — lùi về mở trên iPhone",
                     [[OCPSceneBridge missingRequirements] componentsJoinedByString:@", "]);
        [OCPCrashGuard endRiskyOperation:@"scene-hosting"];
        return NO;
    }

    OCPDisplayConfiguration *display =
        [[OCPCarPlayDetector sharedDetector] displayConfiguration];
    if (display == nil || !display.isValid) {
        OCPLogError_(@"không có màn hình xe khả dụng — lùi về mở trên iPhone");
        [OCPCrashGuard endRiskyOperation:@"scene-hosting"];
        return NO;
    }

    // Chỉ hiển thị một ứng dụng tại một thời điểm.
    [self dismissHostedApplication];

    NSError *error = nil;
    OCPCarPlayWindow *window = [OCPCarPlayWindow windowForDisplayConfiguration:display
                                                                         error:&error];
    if (window == nil) {
        OCPLogError_(@"không tạo được cửa sổ màn hình xe: %@", error.localizedDescription);
        [OCPCrashGuard endRiskyOperation:@"scene-hosting"];
        return NO;
    }

    // Thanh điều khiển phải có TRƯỚC nội dung: nếu bridge dựng được scene nhưng có
    // sự cố sau đó, người dùng vẫn còn đường thoát khỏi ứng dụng trên màn hình xe.
    __weak typeof(self) weakSelf = self;
    [window installControlOverlayWithDismissHandler:^{
        [weakSelf dismissHostedApplication];
    }];
    [window installDisplayTouchMonitor];

    OCPSceneBridge *bridge = [[OCPSceneBridge alloc] init];
    UIView *applicationView =
        [bridge viewForApplicationWithBundleIdentifier:bundleIdentifier error:&error];
    if (applicationView == nil) {
        OCPLogError_(@"scene bridge thất bại: %@", error.localizedDescription);
        [bridge teardown];
        [window dismiss];
        [OCPCrashGuard endRiskyOperation:@"scene-hosting"];
        return NO;
    }

    if (![window presentContentView:applicationView]) {
        [bridge teardown];
        [window dismiss];
        [OCPCrashGuard endRiskyOperation:@"scene-hosting"];
        return NO;
    }

    // Hiển thị được rồi thì thao tác coi như an toàn.
    [OCPCrashGuard endRiskyOperation:@"scene-hosting"];

    self.sceneBridge = bridge;
    self.carPlayWindow = window;

    // Xác nhận kết luận trong RESEARCH.md §6: ứng dụng không tự đổi tuyến âm thanh,
    // hệ thống đã trỏ sẵn về xe khi CarPlay kết nối. Chỉ ghi lại, không can thiệp.
    [[OCPAudioObserver sharedObserver] logCurrentRouteWithContext:
        @"sau khi gắn ứng dụng lên màn hình xe"];

    OCPLogError_(@"%@ đang hiển thị trên MÀN HÌNH XE — chạm vào thanh điều khiển bên trái "
                 @"để xác minh touch routing và để thoát", bundleIdentifier);
    return YES;
}

/// Đóng ứng dụng đang hiển thị trên màn hình xe (nếu có).
- (void)dismissHostedApplication {
    if (self.sceneBridge == nil && self.carPlayWindow == nil) return;

    [self.sceneBridge teardown];
    [self.carPlayWindow dismiss];
    self.sceneBridge = nil;
    self.carPlayWindow = nil;
    [[OCPAudioObserver sharedObserver] logCurrentRouteWithContext:
        @"sau khi đóng ứng dụng trên màn hình xe"];
    OCPLogC(OCPLogRendering, @"đã đóng ứng dụng trên màn hình xe");
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
