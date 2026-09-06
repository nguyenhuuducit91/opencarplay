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

/// Khoá giai đoạn khởi tạo.
FOUNDATION_EXPORT NSString *const OCPPrefsStartupStageKey;

/// Giai đoạn khởi tạo hiện tại (0–5).
///
/// KHÔNG nằm trong file plist chung. Constructor của tweak đọc giá trị này trên đường
/// khởi động SpringBoard, nơi không được phép parse plist hay hỏi cfprefsd, nên nó nằm
/// riêng trong một file văn bản thuần chứa đúng một số nguyên.
FOUNDATION_EXPORT NSInteger OCPPrefsReadStartupStage(void);

/// Ghi giai đoạn. Trả NO nếu không ghi được file (sandbox từ chối) — bên gọi phải nói
/// thật với người dùng thay vì hiện một giá trị chưa hề được lưu.
FOUNDATION_EXPORT BOOL OCPPrefsWriteStartupStage(NSInteger stage);

/// Lần nạp trước có bắt đầu khởi tạo mà không bao giờ báo ổn định không.
/// YES nghĩa là tweak đã tự hạ về giai đoạn 0 để máy lên được.
FOUNDATION_EXPORT BOOL OCPPrefsBootstrapStalled(void);

NS_ASSUME_NONNULL_END

#endif /* OCP_PREFS_COMMON_H */
