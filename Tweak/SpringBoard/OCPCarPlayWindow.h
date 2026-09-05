// OpenCarPlay — cửa sổ trên màn hình xe.
//
// TRẠNG THÁI: THỬ NGHIỆM, CHƯA KIỂM CHỨNG TRÊN THIẾT BỊ.
// UIRootSceneWindow và FBSDisplayConfiguration đã được xác minh TỒN TẠI trên iOS 18.6
// qua symbol SDK (RESEARCH.md §3.7), nhưng cách khởi tạo cụ thể là suy ra từ
// carplay-cast (iOS 14) và chưa có bằng chứng runtime — xem Q6.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_CARPLAY_WINDOW_H
#define OCP_CARPLAY_WINDOW_H

#import <UIKit/UIKit.h>

@class OCPDisplayConfiguration;

NS_ASSUME_NONNULL_BEGIN

@interface OCPCarPlayWindow : NSObject

/// Tạo cửa sổ trên màn hình xe. Trả nil nếu thiếu bất kỳ điều kiện nào —
/// `error` mang mô tả bước thất bại.
+ (nullable instancetype)windowForDisplayConfiguration:(OCPDisplayConfiguration *)configuration
                                                 error:(NSError **)error;

@property (nonatomic, readonly, nullable) UIWindow *window;
@property (nonatomic, readonly) CGRect bounds;

/// Đặt view nội dung (view của ứng dụng) vào cửa sổ và hiện nó lên.
/// Nội dung được thu hẹp để chừa chỗ cho thanh điều khiển.
- (BOOL)presentContentView:(UIView *)contentView;

/// Gắn thanh điều khiển với nút thoát. Gọi trước presentContentView:.
- (void)installControlOverlayWithDismissHandler:(void (^)(void))dismissHandler;

/// Số lần thanh điều khiển nhận được chạm — dùng để xác minh touch routing.
@property (nonatomic, readonly) NSUInteger overlayTouchCount;

/// Đăng ký một gesture chỉ-quan-sát ở tầng display của màn hình xe.
///
/// Đây là lớp chẩn đoán độc lập với cây view: nếu tầng này thấy chạm mà thanh điều
/// khiển không thấy, vấn đề nằm ở cách gắn view; nếu cả hai đều không thấy, sự kiện
/// chạm chưa từng tới SpringBoard. Gesture không nuốt sự kiện nên không ảnh hưởng
/// tới ứng dụng đang hiển thị.
- (void)installDisplayTouchMonitor;

/// Gỡ nội dung và ẩn cửa sổ. An toàn khi gọi nhiều lần.
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_CARPLAY_WINDOW_H */
