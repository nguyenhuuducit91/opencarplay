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

/// Đường dẫn đầy đủ tới file preferences.
FOUNDATION_EXPORT NSString *OCPPreferencesPath(void);

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
