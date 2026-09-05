// OpenCarPlay — phát hiện môi trường: iOS, kiến trúc, jailbreak.
//
// Nếu isSupportedOS trả về NO, tweak không được hook bất cứ thứ gì (ARCHITECTURE §1, §4.2).
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_COMPATIBILITY_H
#define OCP_COMPATIBILITY_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCPCompatibility : NSObject

/// "18.6.2"
+ (NSString *)systemVersion;

+ (BOOL)isIOS18;
+ (BOOL)isIOS18_6;

/// Nằm trong phạm vi đã được nghiên cứu: [18.0, 19.0).
+ (BOOL)isSupportedOS;

/// Lý do không hỗ trợ, để ghi log. nil nếu được hỗ trợ.
+ (nullable NSString *)unsupportedReason;

/// "arm64e", "arm64", hoặc "unknown".
+ (NSString *)architecture;

/// Đang chạy trên jailbreak rootless?
+ (BOOL)isRootlessEnvironment;

/// "/var/jb" hoặc "" (rootful/không xác định).
+ (NSString *)jailbreakRootPath;

/// "ellekit" | "substrate" | "libhooker" | "substitute" | "unknown"
+ (NSString *)hookingRuntimeName;

/// Bundle identifier của process hiện tại.
+ (NSString *)currentProcessBundleIdentifier;

/// Tóm tắt một dòng, dùng cho log khởi động và diagnose.
+ (NSString *)environmentSummary;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_COMPATIBILITY_H */
