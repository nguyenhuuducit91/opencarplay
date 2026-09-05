// OpenCarPlay — xem OCPDefines.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPDefines.h"

NSString *OCPJailbreakRoot(void) {
    static NSString *root = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        // Dopamine và các jailbreak rootless khác dùng /var/jb.
        // Kiểm tra usr/lib thay vì chỉ thư mục gốc để tránh dương tính giả.
        if ([fm fileExistsAtPath:@"/var/jb/usr/lib"]) {
            root = @"/var/jb";
        } else {
            root = @"";
        }
    });
    return root;
}

NSString *OCPRootedPath(NSString *absolutePath) {
    if (absolutePath.length == 0) return OCPJailbreakRoot();
    return [OCPJailbreakRoot() stringByAppendingString:absolutePath];
}

NSString *OCPPreferencesPath(void) {
    return OCPRootedPath([NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist",
                                                    OCPPreferencesDomain]);
}

NSString *OCPKillSwitchPath(void) {
    return OCPRootedPath([NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.disabled",
                                                    OCPPreferencesDomain]);
}

NSString *OCPMediaKillSwitchPath(void) {
    return @"/var/mobile/Media/OpenCarPlay/DISABLED";
}

BOOL OCPKillSwitchEngaged(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:OCPKillSwitchPath()] ||
           [fileManager fileExistsAtPath:OCPMediaKillSwitchPath()];
}
