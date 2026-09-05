// OpenCarPlay — liên lạc giữa các process.
//
// Q10 trong RESEARCH.md §7.4 ("kênh IPC nào còn hoạt động giữa CarPlay.app và
// SpringBoard trên iOS 18.6?") chưa có lời giải, nên lớp này không cam kết một
// kênh cụ thể: nó chọn backend lúc chạy và ghi lại backend đã chọn.
//
// Backend mặc định là Darwin notification — cơ chế ở tầng kernel, không phụ thuộc
// sandbox của distnoted, và luôn có mặt. Payload (nếu cần) đi qua file trong thư mục
// dùng chung vì Darwin notification không mang dữ liệu.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_TRANSPORT_H
#define OCP_TRANSPORT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCPTransportBackend) {
    OCPTransportBackendDarwinNotify = 0,
    OCPTransportBackendUnavailable,
};

/// Tên message. Dùng hằng số, không viết chuỗi rải rác.
FOUNDATION_EXPORT NSString *const OCPMessagePreferencesChanged;
FOUNDATION_EXPORT NSString *const OCPMessageLaunchApplication;
FOUNDATION_EXPORT NSString *const OCPMessageDismissApplication;

@interface OCPTransport : NSObject

+ (instancetype)sharedTransport;

@property (nonatomic, readonly) OCPTransportBackend activeBackend;
@property (nonatomic, readonly, copy) NSString *activeBackendName;

/// Gửi message tới mọi process đang lắng nghe. `payload` phải là plist đơn giản
/// (string/number/bool/array/dictionary) và nên nhỏ — nó đi qua file trung gian.
- (void)postMessage:(NSString *)name payload:(nullable NSDictionary *)payload;

/// Đăng ký nhận message. Handler chạy trên main queue.
- (void)observeMessage:(NSString *)name handler:(void (^)(NSDictionary *payload))handler;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_TRANSPORT_H */
