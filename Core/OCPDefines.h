// OpenCarPlay — hằng số và tiện ích đường dẫn dùng chung.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_DEFINES_H
#define OCP_DEFINES_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bundle identifier của các process mà OpenCarPlay quan tâm.
static NSString *const OCPBundleIDSpringBoard = @"com.apple.springboard";
static NSString *const OCPBundleIDCarPlayApp  = @"com.apple.CarPlayApp";

/// Domain của preferences (không kèm tiền tố jbroot — dùng OCPPreferencesPath()).
static NSString *const OCPPreferencesDomain = @"com.opencarplay";

/// Tiền tố rootless đã phát hiện. Chuỗi rỗng nghĩa là rootful/không xác định.
FOUNDATION_EXPORT NSString *OCPJailbreakRoot(void);

/// Ghép jbroot vào một đường dẫn tuyệt đối kiểu iOS.
/// OCPRootedPath(@"/var/mobile/...") -> @"/var/jb/var/mobile/..." trên rootless.
FOUNDATION_EXPORT NSString *OCPRootedPath(NSString *absolutePath);

/// Đường dẫn file preferences.
///
/// KHÔNG có tiền tố jbroot. Bảng cài đặt chạy trong Settings và ghi qua CFPreferences,
/// mà cfprefsd làm việc trên hệ thống file thật: /var/mobile/Library/Preferences/.
/// Jailbreak rootless dời /Library, /usr, /Applications — không dời /var/mobile.
///
/// Bản 0.30 và trước đó đọc /var/jb/var/mobile/... nên không bao giờ thấy thứ người
/// dùng vừa bật trong Settings.
FOUNDATION_EXPORT NSString *OCPPreferencesPath(void);

/// Vị trí sai mà các bản trước dùng. Chỉ còn để di trú cấu hình cũ một lần.
FOUNDATION_EXPORT NSString *OCPLegacyPreferencesPath(void);

/// Chuyển file cấu hình từ vị trí cũ sang vị trí đúng nếu cần. An toàn khi gọi nhiều lần.
FOUNDATION_EXPORT void OCPMigrateLegacyPreferences(void);

/// Toàn bộ cấu hình hiện tại, đọc trực tiếp không qua OCPPreferences.
///
/// Hai đường, theo đúng thứ tự này:
///   1. CFPreferences — nơi bảng cài đặt vừa ghi; giá trị mới nhất nằm ở đây kể cả
///      khi cfprefsd chưa kịp đẩy xuống đĩa.
///   2. File plist — đường lùi khi domain chưa từng qua cfprefsd (ví dụ người dùng
///      tạo file bằng Filza).
///
/// Dùng được từ mọi nơi, kể cả những lớp không được phép phụ thuộc OCPPreferences.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *OCPPreferencesCopyRaw(void);

/// Đường dẫn tới kill switch. Nếu file tồn tại, tweak không được nạp bất cứ thứ gì.
FOUNDATION_EXPORT NSString *OCPKillSwitchPath(void);

/// Kill switch thứ hai, đặt trong vùng AFC (/var/mobile/Media) nên tạo được từ máy
/// tính qua cáp USB mà không cần SSH hay vào được giao diện máy. Đây là đường cứu hộ
/// khi máy treo ở màn hình khởi động:
///     afcclient put /dev/null /OpenCarPlay/DISABLED
FOUNDATION_EXPORT NSString *OCPMediaKillSwitchPath(void);

/// Kill switch đang bật?
FOUNDATION_EXPORT BOOL OCPKillSwitchEngaged(void);

NS_ASSUME_NONNULL_END

#endif /* OCP_DEFINES_H */
