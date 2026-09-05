// OpenCarPlay — xem OCPControlOverlay.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPControlOverlay.h"

#import "OCPLog.h"

@interface OCPControlOverlay ()
@property (nonatomic, copy) void (^dismissHandler)(void);
@property (nonatomic, strong) UIButton *dismissButton;
@property (nonatomic, assign) NSUInteger touchCount;
@end

@implementation OCPControlOverlay

+ (CGFloat)preferredWidthForBounds:(CGRect)bounds {
    // Đủ rộng để bấm khi đang lái, nhưng không lấn nội dung. Màn hình xe dao động
    // khoảng 800–1900pt chiều ngang nên tỉ lệ hợp lý hơn con số cố định.
    CGFloat proportional = CGRectGetWidth(bounds) * 0.07;
    return MAX(44.0, MIN(72.0, proportional));
}

- (instancetype)initWithFrame:(CGRect)frame
               dismissHandler:(void (^)(void))dismissHandler {
    if ((self = [super initWithFrame:frame])) {
        _dismissHandler = [dismissHandler copy];
        [self buildContent];
    }
    return self;
}

- (void)buildContent {
    self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];

    // Ưu tiên biểu tượng hệ thống; nếu không có thì dùng chữ, không để nút trống.
    UIImage *icon = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                            weight:UIImageSymbolWeightRegular];
        icon = [UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:configuration];
    }
    if (icon != nil) {
        [button setImage:icon forState:UIControlStateNormal];
    } else {
        [button setTitle:@"Đóng" forState:UIControlStateNormal];
    }

    [button addTarget:self
               action:@selector(handleDismiss)
     forControlEvents:UIControlEventTouchUpInside];

    button.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:button];
    self.dismissButton = button;

    [NSLayoutConstraint activateConstraints:@[
        [button.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16.0],
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:44.0],
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
    ]];
}

- (void)handleDismiss {
    OCPLogC(OCPLogTouch, @"người dùng bấm nút thoát trên màn hình xe");
    if (self.dismissHandler != nil) {
        self.dismissHandler();
    }
}

#pragma mark - Xác minh touch routing

// Đếm sự kiện chạm nhận được. Đây là bằng chứng trực tiếp trả lời câu hỏi
// "sự kiện chạm từ màn hình xe có tới được cây view của SpringBoard không".
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.touchCount++;
    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self];
    OCPLogC(OCPLogTouch, @"chạm #%lu tại (%.0f, %.0f) — touch routing HOẠT ĐỘNG",
            (unsigned long)self.touchCount, point.x, point.y);
    [super touchesBegan:touches withEvent:event];
}

@end
