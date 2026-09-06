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
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist",
                                      OCPPreferencesDomain];
}

NSString *OCPLegacyPreferencesPath(void) {
    return OCPRootedPath([NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist",
                                                    OCPPreferencesDomain]);
}

void OCPMigrateLegacyPreferences(void) {
    NSString *legacy = OCPLegacyPreferencesPath();
    NSString *current = OCPPreferencesPath();
    if ([legacy isEqualToString:current]) return;   // rootful: hai đường dẫn là một

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:legacy]) return;
    if ([fileManager fileExistsAtPath:current]) {
        // Vị trí đúng đã có dữ liệu — nó thắng. Chỉ dọn file cũ đi.
        [fileManager removeItemAtPath:legacy error:NULL];
        return;
    }
    [fileManager moveItemAtPath:legacy toPath:current error:NULL];
}

NSDictionary<NSString *, id> *OCPPreferencesCopyRaw(void) {
    @try {
        // FILE TRƯỚC, CFPreferences sau — thứ tự này quan trọng.
        //
        // CFPreferences nói chuyện với cfprefsd qua XPC. Hàm này được gọi rất sớm trong
        // quá trình SpringBoard khởi động, trên main queue; một lời gọi XPC chặn ở đó là
        // đúng công thức làm treo máy ở màn hình khởi động. Đọc file thì không bao giờ
        // chặn vào một process khác.
        //
        // Đọc file không bị cũ, vì bảng cài đặt gọi CFPreferencesAppSynchronize ngay sau
        // mỗi lần ghi — file trên đĩa luôn là bản mới nhất.
        NSDictionary *fromFile = [NSDictionary dictionaryWithContentsOfFile:OCPPreferencesPath()];
        if ([fromFile isKindOfClass:[NSDictionary class]] && fromFile.count > 0) return fromFile;

        // Chưa có file: domain có thể mới chỉ tồn tại trong cfprefsd.
        CFStringRef domain = (__bridge CFStringRef)OCPPreferencesDomain;
        NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(
            domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        if (keys.count > 0) {
            NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(
                (__bridge CFArrayRef)keys, domain,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
            if ([values isKindOfClass:[NSDictionary class]] && values.count > 0) return values;
        }
    } @catch (NSException *exception) {
        // Đọc cấu hình không bao giờ được phép làm chết process gọi nó.
    }
    return @{};
}

NSString *OCPStartupStagePath(void) {
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.stage",
                                      OCPPreferencesDomain];
}

NSString *OCPBootstrapMarkerPath(void) {
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.bootstrapping",
                                      OCPPreferencesDomain];
}

NSString *OCPKillSwitchPath(void) {
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.disabled",
                                      OCPPreferencesDomain];
}

NSString *OCPMediaKillSwitchPath(void) {
    return @"/var/mobile/Media/OpenCarPlay/DISABLED";
}

BOOL OCPKillSwitchEngaged(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // Cả vị trí cũ lẫn mới: người dùng có thể đã tạo kill switch từ bản trước.
    for (NSString *path in @[ OCPKillSwitchPath(),
                              OCPRootedPath([NSString stringWithFormat:
                                  @"/var/mobile/Library/Preferences/%@.disabled",
                                  OCPPreferencesDomain]),
                              OCPMediaKillSwitchPath() ]) {
        if ([fileManager fileExistsAtPath:path]) return YES;
    }
    return NO;
}
