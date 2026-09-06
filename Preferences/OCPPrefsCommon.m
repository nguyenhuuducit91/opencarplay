// OpenCarPlay — xem OCPPrefsCommon.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPPrefsCommon.h"

#import <notify.h>

NSString *const OCPPrefsDomain = @"com.opencarplay";
NSString *const OCPPrefsChangedNotification = @"com.opencarplay.prefs-changed";
NSString *const OCPPrefsAllowedApplicationsKey = @"AllowedApplications";
NSString *const OCPPrefsStartupStageKey = @"StartupStage";

static NSString *OCPPrefsStagePath(void) {
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.stage",
            OCPPrefsDomain];
}

static NSString *OCPPrefsBootstrapMarkerPath(void) {
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.bootstrapping",
            OCPPrefsDomain];
}

NSString *OCPPrefsPath(void) {
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist",
            OCPPrefsDomain];
}

NSBundle *OCPPrefsBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bundle = [NSBundle bundleForClass:NSClassFromString(@"OCPRootListController")];
        if (bundle == nil || [bundle.bundlePath rangeOfString:@"OpenCarPlayPrefs"].location
                == NSNotFound) {
            for (NSString *path in @[ @"/var/jb/Library/PreferenceBundles/OpenCarPlayPrefs.bundle",
                                      @"/Library/PreferenceBundles/OpenCarPlayPrefs.bundle" ]) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    bundle = [NSBundle bundleWithPath:path];
                    break;
                }
            }
        }
    });
    return bundle;
}

/// Đọc bằng CFPreferences trước — đó là nơi Settings vừa ghi và có thể chưa kịp
/// xuống đĩa. File chỉ là đường lùi khi domain chưa từng được cfprefsd biết tới.
NSDictionary<NSString *, id> *OCPPrefsRead(void) {
    CFStringRef domain = (__bridge CFStringRef)OCPPrefsDomain;
    CFPreferencesAppSynchronize(domain);

    NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(
        domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    if (keys.count > 0) {
        NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple(
            (__bridge CFArrayRef)keys, domain,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        if (values.count > 0) return values;
    }

    NSDictionary *fromFile = [NSDictionary dictionaryWithContentsOfFile:OCPPrefsPath()];
    return [fromFile isKindOfClass:[NSDictionary class]] ? fromFile : @{};
}

void OCPPrefsWrite(NSString *key, id value) {
    if (key.length == 0) return;

    CFStringRef domain = (__bridge CFStringRef)OCPPrefsDomain;
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                          domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    // Đẩy xuống đĩa NGAY. Tweak đọc file trực tiếp (nó không dùng chung cfprefsd với
    // Settings), nên nếu không synchronize thì thông báo dưới đây tới trước dữ liệu.
    CFPreferencesAppSynchronize(domain);

    notify_post(OCPPrefsChangedNotification.UTF8String);
}

NSInteger OCPPrefsReadStartupStage(void) {
    NSString *contents = [NSString stringWithContentsOfFile:OCPPrefsStagePath()
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
    if (contents.length == 0) return 0;

    NSScanner *scanner = [NSScanner scannerWithString:contents];
    NSInteger stage = 0;
    if (![scanner scanInteger:&stage]) return 0;
    if (stage < 0) return 0;
    if (stage > 5) return 5;
    return stage;
}

BOOL OCPPrefsWriteStartupStage(NSInteger stage) {
    if (stage < 0) stage = 0;
    if (stage > 5) stage = 5;

    NSString *contents = [NSString stringWithFormat:@"%ld\n", (long)stage];
    NSError *error = nil;
    BOOL ok = [contents writeToFile:OCPPrefsStagePath()
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error];
    if (!ok) {
        NSLog(@"[OpenCarPlay] không ghi được giai đoạn khởi tạo: %@", error);
        return NO;
    }

    // Người dùng vừa chọn tường minh, nên bỏ dấu "lần trước treo". Không bỏ thì lần nạp
    // sau vẫn tự hạ về 0 và lựa chọn vừa rồi không có tác dụng gì.
    [[NSFileManager defaultManager] removeItemAtPath:OCPPrefsBootstrapMarkerPath() error:NULL];

    notify_post(OCPPrefsChangedNotification.UTF8String);
    return YES;
}

BOOL OCPPrefsBootstrapStalled(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:OCPPrefsBootstrapMarkerPath()];
}

void OCPPrefsReset(void) {
    CFStringRef domain = (__bridge CFStringRef)OCPPrefsDomain;
    NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(
        domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    for (NSString *key in keys) {
        CFPreferencesSetValue((__bridge CFStringRef)key, NULL, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    CFPreferencesAppSynchronize(domain);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:OCPPrefsPath() error:NULL];
    [fileManager removeItemAtPath:OCPPrefsStagePath() error:NULL];
    [fileManager removeItemAtPath:OCPPrefsBootstrapMarkerPath() error:NULL];
    notify_post(OCPPrefsChangedNotification.UTF8String);
}
