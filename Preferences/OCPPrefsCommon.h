// OpenCarPlay — phần dùng chung của bảng cài đặt.
//
// Bundle này được Settings nạp qua PreferenceLoader. Nó chỉ đọc/ghi file cấu hình và
// dựng giao diện; không hook gì, không nạp dylib của tweak.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_PREFS_COMMON_H
#define OCP_PREFS_COMMON_H

#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

NS_ASSUME_NONNULL_BEGIN

/// Domain của file cấu hình: /var/mobile/Library/Preferences/com.opencarplay.plist
FOUNDATION_EXPORT NSString *const OCPPrefsDomain;

/// Darwin notification báo cho tweak biết cấu hình vừa đổi.
FOUNDATION_EXPORT NSString *const OCPPrefsChangedNotification;

/// Khoá chứa danh sách bundle identifier được phép.
FOUNDATION_EXPORT NSString *const OCPPrefsAllowedApplicationsKey;

/// Đường dẫn file cấu hình. KHÔNG có tiền tố /var/jb: cfprefsd và Settings đều làm
/// việc trên hệ thống file thật, jailbreak rootless không đổi điều đó.
FOUNDATION_EXPORT NSString *OCPPrefsPath(void);

/// Toàn bộ cấu hình hiện tại (rỗng nếu chưa có file).
FOUNDATION_EXPORT NSDictionary<NSString *, id> *OCPPrefsRead(void);

/// Ghi một giá trị rồi đẩy xuống đĩa và báo cho tweak. `value` nil nghĩa là xoá khoá.
FOUNDATION_EXPORT void OCPPrefsWrite(NSString *key, id _Nullable value);

/// Xoá toàn bộ cấu hình.
FOUNDATION_EXPORT void OCPPrefsReset(void);

/// Bundle chứa Root.plist và các plist con.
FOUNDATION_EXPORT NSBundle *OCPPrefsBundle(void);

NS_ASSUME_NONNULL_END

#endif /* OCP_PREFS_COMMON_H */
