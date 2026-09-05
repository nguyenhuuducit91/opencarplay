// OpenCarPlay — xem OCPCarPlayDetector.h.
//
// Câu hỏi Q8 trong RESEARCH.md §7.4 ("notification nào báo CarPlay connect/disconnect
// trên iOS 18.6?") chưa có lời giải. File này vừa là detector, vừa là công cụ trả lời
// câu hỏi đó: bật khoá SignalDiscovery trong preferences để ghi lại mọi notification
// có tên liên quan tới CarPlay/display mà process nhận được.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPCarPlayDetector.h"

#import <UIKit/UIKit.h>

#import "OCPDefines.h"
#import "OCPDisplayConfiguration.h"
#import "OCPLog.h"
#import "OCPProbe.h"
#import "OCPAudioObserver.h"

NSString *const OCPCarPlayDidConnectNotification = @"com.opencarplay.carplay-connected";
NSString *const OCPCarPlayDidDisconnectNotification = @"com.opencarplay.carplay-disconnected";

/// Tên notification hệ thống đã từng dùng được ở các bản iOS trước. Chúng chỉ là
/// gợi ý — nếu không tồn tại trên 18.6 thì đơn giản là không bao giờ bắn.
static NSString *const kLegacyCarPlayConnectionNotification = @"CarPlayIsConnectedDidChange";

/// Gộp nhiều tín hiệu dồn dập thành một lần đánh giá.
static const NSTimeInterval kEvaluationDebounce = 0.35;

@interface OCPCarPlayDetector ()
@property (nonatomic, assign, getter=isCarPlayConnected) BOOL carPlayConnected;
@property (nonatomic, strong, nullable) OCPDisplayConfiguration *displayConfiguration;
@property (nonatomic, copy) NSArray<NSString *> *activeSignalSources;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL discoveryMode;
@property (nonatomic, strong) NSMutableArray<id> *observers;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenDiscoveryNames;
@end

@implementation OCPCarPlayDetector

+ (instancetype)sharedDetector {
    static OCPCarPlayDetector *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _observers = [NSMutableArray array];
        _seenDiscoveryNames = [NSMutableSet set];
        _activeSignalSources = @[];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Vòng đời

- (void)start {
    if (_running) return;
    _running = YES;

    NSMutableArray<NSString *> *sources = [NSMutableArray array];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    __weak typeof(self) weakSelf = self;

    // Nguồn 1 — API công khai. Deprecated từ iOS 16 nhưng vẫn là tín hiệu đáng tin nhất
    // mà ta không phải đoán tên.
    for (NSNotificationName name in @[ UIScreenDidConnectNotification,
                                       UIScreenDidDisconnectNotification ]) {
        id observer = [center addObserverForName:name
                                          object:nil
                                           queue:[NSOperationQueue mainQueue]
                                      usingBlock:^(NSNotification *note) {
            OCPLogC(OCPLogCarPlay, @"tín hiệu: %@", note.name);
            [weakSelf scheduleEvaluation];
        }];
        [_observers addObject:observer];
    }
    [sources addObject:@"UIScreen"];

    // Nguồn 2 — tên cũ từ thời iOS 14. Không có hại nếu nó không bao giờ bắn.
    id legacyObserver = [center addObserverForName:kLegacyCarPlayConnectionNotification
                                            object:nil
                                             queue:[NSOperationQueue mainQueue]
                                        usingBlock:^(NSNotification *note) {
        OCPLogC(OCPLogCarPlay, @"tín hiệu (legacy): %@", note.name);
        [weakSelf scheduleEvaluation];
    }];
    [_observers addObject:legacyObserver];
    [sources addObject:kLegacyCarPlayConnectionNotification];

    // Nguồn 3 — chế độ khám phá: nghe MỌI notification trong process và ghi lại tên
    // nào liên quan tới CarPlay/display. Đây là cách trả lời Q8 bằng dữ liệu thật.
    [self loadDiscoveryPreference];
    if (_discoveryMode) {
        id discoveryObserver = [center addObserverForName:nil
                                                   object:nil
                                                    queue:nil
                                               usingBlock:^(NSNotification *note) {
            [weakSelf recordDiscoveredNotification:note.name];
        }];
        [_observers addObject:discoveryObserver];
        [sources addObject:@"SignalDiscovery"];
        OCPLogC(OCPLogCarPlay, @"chế độ khám phá tín hiệu ĐANG BẬT — chỉ dùng khi nghiên cứu");
    }

    self.activeSignalSources = sources;
    OCPLogC(OCPLogCarPlay, @"detector khởi động — nguồn: %@",
            [sources componentsJoinedByString:@", "]);

    // Đánh giá trạng thái ban đầu: CarPlay có thể đã cắm sẵn từ trước khi tweak nạp.
    [self scheduleEvaluation];
}

- (void)stop {
    if (!_running) return;
    _running = NO;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (id observer in _observers) {
        [center removeObserver:observer];
    }
    [_observers removeAllObjects];
    self.activeSignalSources = @[];
    OCPLogC(OCPLogCarPlay, @"detector dừng");
}

#pragma mark - Khám phá tín hiệu (công cụ nghiên cứu)

- (void)loadDiscoveryPreference {
    @try {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:OCPPreferencesPath()];
        id value = prefs[@"SignalDiscovery"];
        _discoveryMode = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
    } @catch (NSException *exception) {
        _discoveryMode = NO;
    }
}

- (void)recordDiscoveredNotification:(nullable NSString *)name {
    if (name.length == 0) return;

    // Chỉ quan tâm tên có khả năng liên quan — SpringBoard bắn hàng nghìn notification.
    static NSArray<NSString *> *needles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[ @"carplay", @"car", @"display", @"screen", @"externaldevice", @"vehicle" ];
    });

    NSString *lowercase = name.lowercaseString;
    BOOL interesting = NO;
    for (NSString *needle in needles) {
        if ([lowercase containsString:needle]) { interesting = YES; break; }
    }
    if (!interesting) return;

    @synchronized (_seenDiscoveryNames) {
        if ([_seenDiscoveryNames containsObject:name]) return;   // chỉ ghi lần đầu
        [_seenDiscoveryNames addObject:name];
    }
    OCPLogC(OCPLogCarPlay, @"[discovery] notification: %@", name);
}

#pragma mark - Đánh giá trạng thái

- (void)scheduleEvaluation {
    // Nhiều tín hiệu thường đến liền nhau khi cắm dây; gộp lại thành một lần đánh giá.
    static BOOL pending = NO;
    if (pending) return;
    pending = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kEvaluationDebounce * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        pending = NO;
        [self evaluateNow];
    });
}

- (void)evaluateNow {
    @try {
        OCPDisplayConfiguration *configuration =
            [OCPDisplayConfiguration currentCarPlayConfiguration];
        BOOL connected = (configuration != nil && configuration.isValid);

        if (connected == _carPlayConnected) {
            // Kích thước có thể đổi mà trạng thái không đổi (ví dụ đổi view area).
            if (connected && ![[configuration summary] isEqualToString:
                              [_displayConfiguration summary]]) {
                self.displayConfiguration = configuration;
                OCPLogC(OCPLogCarPlay, @"cấu hình màn hình thay đổi: %@", [configuration summary]);
            }
            return;
        }

        self.carPlayConnected = connected;
        self.displayConfiguration = configuration;

        if (connected) {
            OCPLogError_(@"CarPlay CONNECTED — %@", [configuration summary]);
            [[OCPAudioObserver sharedObserver] logCurrentRouteWithContext:@"khi CarPlay kết nối"];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:OCPCarPlayDidConnectNotification
                              object:self
                            userInfo:@{ @"summary": [configuration summary] }];
        } else {
            OCPLogError_(@"CarPlay DISCONNECTED");
            [[OCPAudioObserver sharedObserver] logCurrentRouteWithContext:@"khi CarPlay ngắt"];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:OCPCarPlayDidDisconnectNotification
                              object:self
                            userInfo:nil];
        }
    } @catch (NSException *exception) {
        OCPLogError_(@"đánh giá trạng thái CarPlay thất bại: %@", exception.reason);
    }
}

@end
