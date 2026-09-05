// OpenCarPlay — khởi chạy ứng dụng khi người dùng chọn trên dashboard CarPlay.
//
// Phase 8 cố tình KHÔNG đụng vào bộ máy scene của SpringBoard. Nó chỉ dùng những
// đường khởi chạy chuẩn mà hệ thống vốn cung cấp, mỗi đường được probe trước.
// Việc gắn giao diện ứng dụng lên màn hình xe là bài toán của Phase 9 và cần dữ
// liệu runtime (RESEARCH.md Q5) mà dự án chưa có.
//
// Hệ quả trong bản này: chạm icon trên CarPlay sẽ mở ứng dụng trên MÀN HÌNH IPHONE.
// Đó là bước trung gian có chủ ý, không phải lỗi.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_LAUNCH_COORDINATOR_H
#define OCP_LAUNCH_COORDINATOR_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCPLaunchResult) {
    OCPLaunchResultSucceeded = 0,
    /// Bundle identifier không hợp lệ, bị chặn cứng, hoặc không có trong danh sách.
    OCPLaunchResultRejected,
    /// Ứng dụng không có trên máy.
    OCPLaunchResultNotInstalled,
    /// Không có đường khởi chạy nào khả dụng trên hệ thống này.
    OCPLaunchResultNoStrategy,
    /// Hệ thống từ chối khởi chạy.
    OCPLaunchResultSystemRefused,
};

@interface OCPLaunchCoordinator : NSObject

+ (instancetype)sharedCoordinator;

/// Bắt đầu lắng nghe yêu cầu khởi chạy từ process CarPlay dashboard.
- (void)start;

/// Khởi chạy một ứng dụng. Trả về kết quả để bên gọi ghi log/hiển thị.
- (OCPLaunchResult)launchApplicationWithBundleIdentifier:(nullable NSString *)bundleIdentifier;

/// Bundle identifier của ứng dụng được khởi chạy gần nhất qua OpenCarPlay.
@property (nonatomic, readonly, nullable, copy) NSString *lastLaunchedBundleIdentifier;

/// Tên các đường khởi chạy khả dụng, để ghi log và chẩn đoán.
@property (nonatomic, readonly, copy) NSArray<NSString *> *availableStrategies;

+ (NSString *)nameForResult:(OCPLaunchResult)result;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_LAUNCH_COORDINATOR_H */
