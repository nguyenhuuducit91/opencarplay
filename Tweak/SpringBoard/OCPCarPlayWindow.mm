// OpenCarPlay — xem OCPCarPlayWindow.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPCarPlayWindow.h"

#import "OCPDisplayConfiguration.h"
#import "OCPLog.h"
#import "OCPProbe.h"
#import "OCPControlOverlay.h"

static NSString *const kErrorDomain = @"com.opencarplay.window";

@interface OCPCarPlayWindow ()
@property (nonatomic, strong, nullable) UIWindow *window;
@property (nonatomic, strong, nullable) UIView *contentContainer;
@property (nonatomic, strong, nullable) OCPControlOverlay *controlOverlay;
@property (nonatomic, strong, nullable) UITapGestureRecognizer *displayTouchMonitor;
@property (nonatomic, strong, nullable) id gestureDisplayIdentity;
@property (nonatomic, assign) NSUInteger displayTouchCount;
@property (nonatomic, assign) BOOL dismissed;
@end

@implementation OCPCarPlayWindow

+ (NSError *)errorWithStage:(NSString *)stage detail:(NSString *)detail {
    return [NSError errorWithDomain:kErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"%@: %@", stage, detail] }];
}

/// Lấy FBSDisplayConfiguration của màn hình xe.
///
/// OCPDisplayConfiguration có thể đã giữ sẵn đối tượng này (nếu nó lấy được từ
/// FBSDisplayMonitor), hoặc chỉ có CADisplay — khi đó phải dựng cấu hình từ CADisplay.
+ (nullable id)frontBoardConfigurationFrom:(OCPDisplayConfiguration *)configuration
                                     error:(NSError **)error {
    id backing = configuration.backingObject;
    if (backing == nil) {
        if (error) *error = [self errorWithStage:@"DisplayConfiguration"
                                          detail:@"không có đối tượng hệ thống nào cho màn hình xe"];
        return nil;
    }

    Class fbsConfigurationClass = [OCPProbe classNamed:@"FBSDisplayConfiguration"];
    if (fbsConfigurationClass == Nil) {
        if (error) *error = [self errorWithStage:@"DisplayConfiguration"
                                          detail:@"FBSDisplayConfiguration không tồn tại"];
        return nil;
    }

    if ([backing isKindOfClass:fbsConfigurationClass]) return backing;

    // Nguồn CADisplay: dựng cấu hình từ nó.
    Class caDisplayClass = [OCPProbe classNamed:@"CADisplay"];
    if (caDisplayClass != Nil && [backing isKindOfClass:caDisplayClass]) {
        id allocated = [fbsConfigurationClass alloc];
        id built = [OCPProbe invokeTarget:allocated
                                 selector:@"initWithCADisplay:isMainDisplay:"
                                arguments:@[ backing, @NO ]];
        if (built != nil) return built;
        if (error) *error = [self errorWithStage:@"DisplayConfiguration"
                                          detail:@"initWithCADisplay:isMainDisplay: thất bại"];
        return nil;
    }

    if (error) {
        *error = [self errorWithStage:@"DisplayConfiguration"
                               detail:[NSString stringWithFormat:
                                       @"nguồn %@ không dựng được FBSDisplayConfiguration",
                                       configuration.sourceName]];
    }
    return nil;
}

+ (nullable instancetype)windowForDisplayConfiguration:(OCPDisplayConfiguration *)configuration
                                                 error:(NSError **)error {
    if (configuration == nil || !configuration.isValid) {
        if (error) *error = [self errorWithStage:@"Input" detail:@"cấu hình màn hình không hợp lệ"];
        return nil;
    }

    Class windowClass = [OCPProbe classNamed:@"UIRootSceneWindow"];
    if (windowClass == Nil) {
        if (error) *error = [self errorWithStage:@"Window"
                                          detail:@"UIRootSceneWindow không tồn tại — xem RESEARCH.md Q6"];
        return nil;
    }
    if (![OCPProbe class:@"UIRootSceneWindow" respondsTo:@"initWithDisplayConfiguration:"]) {
        if (error) *error = [self errorWithStage:@"Window"
                                          detail:@"-initWithDisplayConfiguration: không tồn tại"];
        return nil;
    }

    id displayConfiguration = [self frontBoardConfigurationFrom:configuration error:error];
    if (displayConfiguration == nil) return nil;

    UIWindow *window = nil;
    @try {
        id allocated = [windowClass alloc];
        window = [OCPProbe invokeTarget:allocated
                               selector:@"initWithDisplayConfiguration:"
                              arguments:@[ displayConfiguration ]];
    } @catch (NSException *exception) {
        if (error) *error = [self errorWithStage:@"Window" detail:exception.reason ?: @"exception"];
        return nil;
    }

    if (![window isKindOfClass:[UIWindow class]]) {
        if (error) *error = [self errorWithStage:@"Window"
                                          detail:@"khởi tạo trả về đối tượng không phải UIWindow"];
        return nil;
    }

    OCPCarPlayWindow *instance = [[self alloc] init];
    instance.window = window;

    @try {
        window.backgroundColor = [UIColor blackColor];
        window.alpha = 0.0;
        UIView *container = [[UIView alloc] initWithFrame:window.bounds];
        container.backgroundColor = [UIColor clearColor];
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                     UIViewAutoresizingFlexibleHeight;
        [window addSubview:container];
        instance.contentContainer = container;
    } @catch (NSException *exception) {
        OCPLogError_(@"dựng nội dung cửa sổ thất bại: %@", exception.reason);
    }

    OCPLogError_(@"đã tạo cửa sổ trên màn hình xe: %@ (%@)",
                 NSStringFromCGRect(window.bounds), [configuration summary]);
    return instance;
}

- (CGRect)bounds {
    return self.window ? self.window.bounds : CGRectZero;
}

- (NSUInteger)overlayTouchCount {
    return self.controlOverlay.touchCount;
}

- (void)installControlOverlayWithDismissHandler:(void (^)(void))dismissHandler {
    if (self.window == nil || self.controlOverlay != nil) return;

    @try {
        CGRect bounds = self.window.bounds;
        CGFloat width = [OCPControlOverlay preferredWidthForBounds:bounds];
        CGRect frame = CGRectMake(0, 0, width, CGRectGetHeight(bounds));

        OCPControlOverlay *overlay = [[OCPControlOverlay alloc] initWithFrame:frame
                                                              dismissHandler:dismissHandler];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        [self.window addSubview:overlay];
        self.controlOverlay = overlay;

        // Nội dung lùi sang phải để không bị thanh điều khiển che.
        CGRect contentFrame = self.contentContainer.frame;
        contentFrame.origin.x = width;
        contentFrame.size.width = CGRectGetWidth(bounds) - width;
        self.contentContainer.frame = contentFrame;
        self.contentContainer.autoresizingMask = UIViewAutoresizingFlexibleHeight;

        OCPLogC(OCPLogRendering, @"đã gắn thanh điều khiển rộng %.0fpt", width);
    } @catch (NSException *exception) {
        OCPLogError_(@"gắn thanh điều khiển thất bại: %@", exception.reason);
    }
}

#pragma mark - Theo dõi chạm ở tầng display

- (void)installDisplayTouchMonitor {
    if (self.window == nil || self.displayTouchMonitor != nil) return;

    id manager = [OCPProbe invokeClass:@"_UISystemGestureManager" selector:@"sharedInstance"];
    if (manager == nil) {
        OCPLogC(OCPLogTouch, @"_UISystemGestureManager không có — bỏ qua lớp theo dõi chạm");
        return;
    }
    if (![OCPProbe class:@"_UISystemGestureManager"
              respondsTo:@"addGestureRecognizer:toDisplayWithIdentity:"]) {
        OCPLogC(OCPLogTouch, @"addGestureRecognizer:toDisplayWithIdentity: không có");
        return;
    }

    id displayConfiguration = [OCPProbe invoke:self.window selector:@"displayConfiguration"];
    id identity = [OCPProbe invoke:displayConfiguration selector:@"identity"];
    if (identity == nil) {
        OCPLogC(OCPLogTouch, @"không lấy được display identity của cửa sổ");
        return;
    }

    UITapGestureRecognizer *monitor =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDisplayTouch:)];
    // Chỉ quan sát: không nuốt sự kiện, không huỷ chạm của ứng dụng bên dưới.
    monitor.cancelsTouchesInView = NO;
    monitor.delaysTouchesBegan = NO;
    monitor.delaysTouchesEnded = NO;

    id result = [OCPProbe invokeTarget:manager
                              selector:@"addGestureRecognizer:toDisplayWithIdentity:"
                             arguments:@[ monitor, identity ]];
    (void)result;

    self.displayTouchMonitor = monitor;
    self.gestureDisplayIdentity = identity;
    OCPLogC(OCPLogTouch, @"đã gắn lớp theo dõi chạm ở tầng display");
}

- (void)handleDisplayTouch:(UITapGestureRecognizer *)recognizer {
    self.displayTouchCount++;
    CGPoint point = [recognizer locationInView:nil];
    OCPLogC(OCPLogTouch, @"display nhận chạm #%lu tại (%.0f, %.0f)",
            (unsigned long)self.displayTouchCount, point.x, point.y);
}

- (void)removeDisplayTouchMonitor {
    if (self.displayTouchMonitor == nil) return;

    id manager = [OCPProbe invokeClass:@"_UISystemGestureManager" selector:@"sharedInstance"];
    if (manager != nil && self.gestureDisplayIdentity != nil) {
        [OCPProbe invokeTarget:manager
                      selector:@"removeGestureRecognizer:fromDisplayWithIdentity:"
                     arguments:@[ self.displayTouchMonitor, self.gestureDisplayIdentity ]];
    }
    self.displayTouchMonitor = nil;
    self.gestureDisplayIdentity = nil;
}

- (BOOL)presentContentView:(UIView *)contentView {
    if (self.window == nil || self.contentContainer == nil || contentView == nil) return NO;

    @try {
        contentView.frame = self.contentContainer.bounds;
        contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                       UIViewAutoresizingFlexibleHeight;
        [self.contentContainer addSubview:contentView];

        self.window.hidden = NO;
        [UIView animateWithDuration:0.35 animations:^{
            self.window.alpha = 1.0;
        }];
        OCPLogC(OCPLogRendering, @"đã gắn nội dung lên màn hình xe");
        return YES;
    } @catch (NSException *exception) {
        OCPLogError_(@"gắn nội dung thất bại: %@", exception.reason);
        return NO;
    }
}

- (void)dismiss {
    if (self.dismissed) return;
    self.dismissed = YES;

    @try {
        for (UIView *subview in [self.contentContainer.subviews copy]) {
            [subview removeFromSuperview];
        }
        if (self.controlOverlay != nil) {
            OCPLogError_(@"tổng kết chạm — thanh điều khiển: %lu, tầng display: %lu",
                         (unsigned long)self.controlOverlay.touchCount,
                         (unsigned long)self.displayTouchCount);
            [self.controlOverlay removeFromSuperview];
            self.controlOverlay = nil;
        }
        [self removeDisplayTouchMonitor];
        self.window.hidden = YES;
        self.window.alpha = 0.0;
        self.contentContainer = nil;
        self.window = nil;
        OCPLogC(OCPLogRendering, @"đã đóng cửa sổ màn hình xe");
    } @catch (NSException *exception) {
        OCPLogError_(@"đóng cửa sổ thất bại: %@", exception.reason);
    }
}

@end
