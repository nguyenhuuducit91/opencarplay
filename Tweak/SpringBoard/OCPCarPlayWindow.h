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
- (BOOL)presentContentView:(UIView *)contentView;

/// Gỡ nội dung và ẩn cửa sổ. An toàn khi gọi nhiều lần.
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_CARPLAY_WINDOW_H */
