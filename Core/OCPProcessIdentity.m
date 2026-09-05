// OpenCarPlay — xem OCPProcessIdentity.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPProcessIdentity.h"
#import "OCPDefines.h"

@implementation OCPProcessIdentity

+ (NSArray<NSString *> *)knownCarPlayProcessIdentifiers {
    // Từ RESEARCH.md §3.1. Sự tồn tại của từng process CHƯA được xác minh trên
    // iOS 18.6.2 — scripts/inspect_carplay.sh đối chiếu danh sách này với thực tế.
    return @[
        @"com.apple.CarPlayApp",
        @"com.apple.CarPlayTemplateUIHost",
        @"com.apple.CarPlaySettings",
        @"com.apple.MusicUIService",
        @"com.apple.InCallService",
    ];
}

+ (NSString *)bundleIdentifier {
    return [[NSBundle mainBundle] bundleIdentifier] ?: @"(none)";
}

+ (NSString *)executableName {
    return [[NSProcessInfo processInfo] processName] ?: @"(unknown)";
}

+ (pid_t)processIdentifier {
    return [[NSProcessInfo processInfo] processIdentifier];
}

+ (OCPProcessRole)currentRole {
    static OCPProcessRole role = OCPProcessRoleUnknown;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *bundleID = [self bundleIdentifier];

        if ([bundleID isEqualToString:OCPBundleIDSpringBoard]) {
            role = OCPProcessRoleSpringBoard;
        } else if ([bundleID isEqualToString:OCPBundleIDCarPlayApp]) {
            role = OCPProcessRoleCarPlayDashboard;
        } else if ([[self knownCarPlayProcessIdentifiers] containsObject:bundleID]) {
            role = OCPProcessRoleCarPlayAuxiliary;
        } else if ([bundleID hasPrefix:@"com.apple."]) {
            role = OCPProcessRoleUnknown;
        } else {
            role = OCPProcessRoleUserApplication;
        }
    });
    return role;
}

+ (NSString *)nameForRole:(OCPProcessRole)role {
    switch (role) {
        case OCPProcessRoleSpringBoard:       return @"SpringBoard";
        case OCPProcessRoleCarPlayDashboard:  return @"CarPlayDashboard";
        case OCPProcessRoleCarPlayAuxiliary:  return @"CarPlayAuxiliary";
        case OCPProcessRoleUserApplication:   return @"UserApplication";
        case OCPProcessRoleUnknown:           break;
    }
    return @"Unknown";
}

+ (BOOL)isCarPlayRelatedProcess {
    OCPProcessRole role = [self currentRole];
    return role == OCPProcessRoleCarPlayDashboard || role == OCPProcessRoleCarPlayAuxiliary;
}

+ (NSString *)summary {
    return [NSString stringWithFormat:@"%@ (%@, pid %d) vai trò=%@",
            [self executableName], [self bundleIdentifier], [self processIdentifier],
            [self nameForRole:[self currentRole]]];
}

@end
