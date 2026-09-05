// OpenCarPlay — xem OCPPrefsCommon.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPPrefsCommon.h"

#import <notify.h>

NSString *const OCPPrefsDomain = @"com.opencarplay";
NSString *const OCPPrefsChangedNotification = @"com.opencarplay.prefs-changed";
NSString *const OCPPrefsAllowedApplicationsKey = @"AllowedApplications";

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

void OCPPrefsReset(void) {
    CFStringRef domain = (__bridge CFStringRef)OCPPrefsDomain;
    NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(
        domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    for (NSString *key in keys) {
        CFPreferencesSetValue((__bridge CFStringRef)key, NULL, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    CFPreferencesAppSynchronize(domain);
    [[NSFileManager defaultManager] removeItemAtPath:OCPPrefsPath() error:NULL];
    notify_post(OCPPrefsChangedNotification.UTF8String);
}
