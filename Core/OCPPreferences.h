// OpenCarPlay — đọc/ghi preferences.
//
// Mọi giá trị mặc định đều là "tắt" (nguyên tắc 1 trong ARCHITECTURE.md): tweak chưa
// được cấu hình thì hệ thống phải hoạt động y như khi chưa cài.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_PREFERENCES_H
#define OCP_PREFERENCES_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Phát trong process khi preferences vừa được nạp lại.
FOUNDATION_EXPORT NSString *const OCPPreferencesDidChangeNotification;

/// Tiền tố khoá của một ứng dụng được phép: `App-com.vi.du` = YES.
/// Bảng cài đặt ghi từng công tắc riêng vì nó không có mã để dựng một mảng.
FOUNDATION_EXPORT NSString *const OCPAllowedApplicationKeyPrefix;

@interface OCPPreferences : NSObject

+ (instancetype)sharedPreferences;

/// Công tắc chính. Mặc định NO.
@property (nonatomic, readonly) BOOL enabled;

/// Ứng dụng được phép dùng với CarPlay (chuỗi thô, chưa lọc hợp lệ —
/// dùng OCPAppRegistry để có danh sách đã kiểm tra).
@property (nonatomic, readonly, copy) NSArray<NSString *> *allowedApplications;

@property (nonatomic, readonly) BOOL autoLaunch;
@property (nonatomic, readonly) BOOL hideStatusBar;
@property (nonatomic, readonly) BOOL fullScreen;
@property (nonatomic, readonly) BOOL forceLandscape;
@property (nonatomic, readonly) BOOL debugLogging;

/// Công cụ nghiên cứu — xem README.
@property (nonatomic, readonly) BOOL runtimeSurvey;
@property (nonatomic, readonly) BOOL signalDiscovery;

/// Cổng riêng cho phần đưa ứng dụng lên dashboard. Tách khỏi `enabled` vì đây là
/// phần đầu tiên thực sự thay đổi hành vi CarPlay và chưa được kiểm chứng trên
/// thiết bị thật — người dùng phải bật tường minh.
@property (nonatomic, readonly) BOOL experimentalDiscovery;

/// Cổng cho phần gắn giao diện ứng dụng lên màn hình xe. Tách riêng khỏi
/// experimentalDiscovery vì phần này chạm vào bộ máy scene của SpringBoard —
/// sai ở đó nghĩa là SpringBoard chết lặp, không phải chỉ mất tính năng.
@property (nonatomic, readonly) BOOL experimentalSceneHosting;

/// Đã có cấu hình lưu lại chưa (phân biệt "chưa cấu hình bao giờ" với "cấu hình tắt").
@property (nonatomic, readonly) BOOL hasStoredConfiguration;

/// Nạp lại từ đĩa và phát OCPPreferencesDidChangeNotification.
- (void)reload;

/// Ghi một giá trị và thông báo cho các process khác. Trả NO nếu ghi thất bại.
- (BOOL)setValue:(nullable id)value forPreferenceKey:(NSString *)key;

/// Toàn bộ giá trị hiện tại, dùng cho log/diagnose.
- (NSDictionary<NSString *, id> *)snapshot;

/// Mô tả một dòng cho log.
- (NSString *)summary;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_PREFERENCES_H */
