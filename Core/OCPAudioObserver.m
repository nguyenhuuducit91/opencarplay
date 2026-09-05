// OpenCarPlay — xem OCPAudioObserver.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPAudioObserver.h"

#import "OCPLog.h"
#import "OCPProbe.h"

/// Tra cứu qua runtime thay vì link AVFoundation: tránh thêm phụ thuộc vào dylib
/// và tránh làm chậm khởi động những process không cần tới nó.
static NSString *const kAudioSessionClass = @"AVAudioSession";
static NSString *const kRouteChangeNotification = @"AVAudioSessionRouteChangeNotification";

/// portType của cổng ra tương ứng hệ thống âm thanh xe.
static NSString *const kCarAudioPortType = @"CarAudio";

@interface OCPAudioObserver ()
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong, nullable) id routeChangeObserver;
@property (nonatomic, copy, nullable) NSString *lastRouteDescription;
@end

@implementation OCPAudioObserver

+ (instancetype)sharedObserver {
    static OCPAudioObserver *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Đọc tuyến âm thanh

- (nullable id)audioSession {
    return [OCPProbe invokeClass:kAudioSessionClass selector:@"sharedInstance"];
}

/// Danh sách cổng ra hiện tại, mỗi phần tử dạng "portType (portName)".
- (NSArray<NSString *> *)currentOutputDescriptions {
    id session = [self audioSession];
    if (session == nil) return @[];

    id route = [OCPProbe invoke:session selector:@"currentRoute"];
    id outputs = [OCPProbe invoke:route selector:@"outputs"];
    if (![outputs isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<NSString *> *descriptions = [NSMutableArray array];
    for (id port in (NSArray *)outputs) {
        NSString *type = [OCPProbe invoke:port selector:@"portType"];
        NSString *name = [OCPProbe invoke:port selector:@"portName"];
        if (![type isKindOfClass:[NSString class]]) type = @"?";
        if (![name isKindOfClass:[NSString class]]) name = @"?";
        [descriptions addObject:[NSString stringWithFormat:@"%@ (%@)", type, name]];
    }
    return descriptions;
}

- (NSString *)currentRouteDescription {
    if ([OCPProbe classNamed:kAudioSessionClass] == Nil) return @"(không có AVAudioSession)";

    NSArray<NSString *> *outputs = [self currentOutputDescriptions];
    if (outputs.count == 0) return @"(không đọc được)";
    return [outputs componentsJoinedByString:@", "];
}

- (BOOL)routedToVehicle {
    for (NSString *description in [self currentOutputDescriptions]) {
        if ([description containsString:kCarAudioPortType]) return YES;
    }
    return NO;
}

- (void)logCurrentRouteWithContext:(NSString *)context {
    NSString *description = [self currentRouteDescription];
    OCPLogC(OCPLogAudio, @"%@: %@%@", context, description,
            [self routedToVehicle] ? @"  ← đang đi qua hệ thống âm thanh của xe" : @"");
}

#pragma mark - Vòng đời

- (void)start {
    if (_running) return;

    if ([OCPProbe classNamed:kAudioSessionClass] == Nil) {
        OCPLogC(OCPLogAudio, @"AVAudioSession không có trong process này — bỏ qua quan sát");
        return;
    }
    _running = YES;

    __weak typeof(self) weakSelf = self;
    self.routeChangeObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:kRouteChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
        [weakSelf handleRouteChange:note];
    }];

    [self logCurrentRouteWithContext:@"tuyến âm thanh lúc khởi động"];
    OCPLogC(OCPLogAudio, @"quan sát tuyến âm thanh — CHỈ ĐỌC, không thay đổi cấu hình nào");
}

- (void)handleRouteChange:(NSNotification *)notification {
    NSString *description = [self currentRouteDescription];
    if ([description isEqualToString:self.lastRouteDescription]) return;
    self.lastRouteDescription = description;

    // Lý do thay đổi do hệ thống cung cấp; chỉ ghi lại, không diễn giải.
    id reason = notification.userInfo[@"AVAudioSessionRouteChangeReasonKey"];
    OCPLogC(OCPLogAudio, @"tuyến âm thanh đổi (reason %@): %@", reason ?: @"?", description);
}

- (void)stop {
    if (!_running) return;
    _running = NO;

    if (self.routeChangeObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.routeChangeObserver];
        self.routeChangeObserver = nil;
    }
}

@end
