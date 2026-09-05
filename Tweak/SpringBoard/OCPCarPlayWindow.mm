// OpenCarPlay — xem OCPCarPlayWindow.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPCarPlayWindow.h"

#import "OCPDisplayConfiguration.h"
#import "OCPLog.h"
#import "OCPProbe.h"

static NSString *const kErrorDomain = @"com.opencarplay.window";

@interface OCPCarPlayWindow ()
@property (nonatomic, strong, nullable) UIWindow *window;
@property (nonatomic, strong, nullable) UIView *contentContainer;
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
