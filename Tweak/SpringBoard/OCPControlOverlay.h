// OpenCarPlay — thanh điều khiển trên màn hình xe.
//
// Vì sao đây là phần bắt buộc chứ không phải trang trí: khi một ứng dụng thường
// chiếm màn hình xe, nó KHÔNG có nút Home của CarPlay. Không có đường thoát thì
// người lái bị kẹt trong ứng dụng đó — vừa là lỗi dùng, vừa là vấn đề an toàn.
//
// Overlay cũng là nơi xác minh chạm: nếu nút ở đây bấm được thì sự kiện chạm từ màn
// hình xe đã tới được cây view của ta (RESEARCH.md §11).
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_CONTROL_OVERLAY_H
#define OCP_CONTROL_OVERLAY_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCPControlOverlay : UIView

/// Chiều rộng thanh điều khiển, tính theo kích thước màn hình xe chứ không cố định,
/// vì màn hình xe rất khác nhau giữa các đời xe.
+ (CGFloat)preferredWidthForBounds:(CGRect)bounds;

/// `dismissHandler` được gọi trên main thread khi người dùng bấm nút thoát.
- (instancetype)initWithFrame:(CGRect)frame
               dismissHandler:(void (^)(void))dismissHandler NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Số lần overlay nhận được sự kiện chạm — bằng chứng cho thấy touch routing hoạt động.
@property (nonatomic, readonly) NSUInteger touchCount;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_CONTROL_OVERLAY_H */
