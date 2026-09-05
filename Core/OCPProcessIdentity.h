// OpenCarPlay — nhận diện process đang chạy.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_PROCESS_IDENTITY_H
#define OCP_PROCESS_IDENTITY_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCPProcessRole) {
    OCPProcessRoleUnknown = 0,
    OCPProcessRoleSpringBoard,
    /// com.apple.CarPlayApp — dashboard hiển thị trên màn hình xe.
    OCPProcessRoleCarPlayDashboard,
    /// Các process phụ trợ của CarPlay (template host, settings, now playing...).
    OCPProcessRoleCarPlayAuxiliary,
    /// Ứng dụng người dùng.
    OCPProcessRoleUserApplication,
};

@interface OCPProcessIdentity : NSObject

+ (OCPProcessRole)currentRole;
+ (NSString *)nameForRole:(OCPProcessRole)role;

+ (NSString *)bundleIdentifier;
+ (NSString *)executableName;
+ (pid_t)processIdentifier;

/// Process này có thuộc hệ CarPlay không (dashboard hoặc phụ trợ).
+ (BOOL)isCarPlayRelatedProcess;

/// Bundle identifier của các process liên quan CarPlay đã biết, dùng cho log và
/// cho scripts/inspect_carplay.sh. Đây là danh sách để ĐỐI CHIẾU, không phải để
/// giả định process nào đang chạy.
+ (NSArray<NSString *> *)knownCarPlayProcessIdentifiers;

/// Mô tả một dòng cho log.
+ (NSString *)summary;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_PROCESS_IDENTITY_H */
