// OpenCarPlay — xem OCPCompatibility.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPCompatibility.h"
#import "OCPDefines.h"
#import "ocp_util.h"

#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <mach-o/dyld.h>
#import <mach-o/arch.h>
#import <string.h>

/// Phạm vi iOS mà dự án đã nghiên cứu. Hẹp dần khi có dữ liệu thực địa.
static NSString *const kMinimumSupportedVersion = @"18.0";
static NSString *const kMaximumExclusiveVersion = @"19.0";

@implementation OCPCompatibility

+ (NSString *)systemVersion {
    static NSString *version = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
        version = [NSString stringWithFormat:@"%ld.%ld.%ld",
                   (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion];
    });
    return version;
}

+ (ocp_version_t)parsedSystemVersion {
    return ocp_version_parse([[self systemVersion] UTF8String]);
}

+ (BOOL)isIOS18 {
    return [self parsedSystemVersion].major == 18;
}

+ (BOOL)isIOS18_6 {
    ocp_version_t v = [self parsedSystemVersion];
    return v.valid && v.major == 18 && v.minor == 6;
}

+ (BOOL)isSupportedOS {
    return [self unsupportedReason] == nil;
}

+ (nullable NSString *)unsupportedReason {
    ocp_version_t current = [self parsedSystemVersion];
    if (!current.valid) {
        return @"không đọc được phiên bản hệ điều hành";
    }

    ocp_version_t min = ocp_version_parse([kMinimumSupportedVersion UTF8String]);
    ocp_version_t max = ocp_version_parse([kMaximumExclusiveVersion UTF8String]);
    if (!ocp_version_in_range(current, min, max)) {
        return [NSString stringWithFormat:@"iOS %@ nằm ngoài phạm vi [%@, %@)",
                [self systemVersion], kMinimumSupportedVersion, kMaximumExclusiveVersion];
    }

    if (![self isRootlessEnvironment]) {
        return @"không phát hiện được môi trường jailbreak rootless";
    }

    return nil;
}

+ (NSString *)architecture {
    static NSString *arch = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Kiến trúc của chính process này (không phải của thiết bị) — đây mới là
        // thứ quyết định slice nào của dylib được nạp.
        cpu_type_t type = 0;
        cpu_subtype_t subtype = 0;
        size_t size = sizeof(type);
        if (sysctlbyname("hw.cputype", &type, &size, NULL, 0) != 0) {
            arch = @"unknown";
            return;
        }
        size = sizeof(subtype);
        if (sysctlbyname("hw.cpusubtype", &subtype, &size, NULL, 0) != 0) {
            subtype = 0;
        }

        if (type == CPU_TYPE_ARM64) {
            arch = ((subtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E) ? @"arm64e" : @"arm64";
        } else {
            arch = @"unknown";
        }
    });
    return arch;
}

+ (NSString *)jailbreakRootPath {
    return OCPJailbreakRoot();
}

+ (BOOL)isRootlessEnvironment {
    return OCPJailbreakRoot().length > 0;
}

+ (NSString *)hookingRuntimeName {
    static NSString *name = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Ưu tiên nhận diện qua image đã nạp trong process này — chính xác hơn
        // là đoán từ file có mặt trên đĩa.
        uint32_t count = _dyld_image_count();
        for (uint32_t i = 0; i < count; i++) {
            const char *path = _dyld_get_image_name(i);
            if (path == NULL) continue;
            if (strstr(path, "ellekit"))    { name = @"ellekit";    return; }
            if (strstr(path, "libhooker"))  { name = @"libhooker";  return; }
            if (strstr(path, "substitute")) { name = @"substitute"; return; }
            if (strstr(path, "substrate"))  { name = @"substrate";  return; }
        }
        name = @"unknown";
    });
    return name;
}

+ (NSString *)currentProcessBundleIdentifier {
    return [[NSBundle mainBundle] bundleIdentifier] ?: @"(none)";
}

+ (NSString *)environmentSummary {
    NSString *reason = [self unsupportedReason];
    return [NSString stringWithFormat:@"iOS %@ | %@ | jbroot=%@ | hooking=%@ | process=%@ | %@",
            [self systemVersion],
            [self architecture],
            [self isRootlessEnvironment] ? [self jailbreakRootPath] : @"(rootful/unknown)",
            [self hookingRuntimeName],
            [self currentProcessBundleIdentifier],
            reason ? [@"KHÔNG hỗ trợ: " stringByAppendingString:reason] : @"được hỗ trợ"];
}

@end
