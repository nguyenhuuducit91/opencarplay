// OpenCarPlay — xem OCPAppListController.h.
//
// Danh sách dựng lúc chạy từ ứng dụng thực sự có trên máy — không hard-code bundle
// identifier nào. Nếu không truy vấn được, bảng hướng dẫn sửa file cấu hình thay vì
// hiện danh sách rỗng không giải thích.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPAppListController.h"

#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <notify.h>

static NSString *const kPreferencesDomain = @"com.opencarplay";
static NSString *const kPreferencesChangedNotification = @"com.opencarplay.prefs-changed";
static NSString *const kAllowedApplicationsKey = @"AllowedApplications";

/// Process hệ thống bị ẩn khỏi danh sách. Trùng với danh sách chặn cứng trong
/// Core/ocp_util.c — ở đây chỉ để người dùng không chọn nhầm; việc chặn thật nằm ở tweak.
static NSArray<NSString *> *OCPHiddenIdentifiers(void) {
    return @[ @"com.apple.springboard", @"com.apple.CarPlayApp",
              @"com.apple.CarPlayTemplateUIHost", @"com.apple.CarPlaySettings",
              @"com.apple.InCallService", @"com.apple.MusicUIService",
              @"com.opencarplay.tweak", @"com.opencarplay.prefs" ];
}

/// Gọi selector không tham số trả về object, dùng chữ ký thật từ runtime.
/// Tránh performSelector: vì ARC không suy được quy ước bộ nhớ của selector động.
static id OCPInvoke(id target, SEL selector) {
    if (target == nil || selector == NULL || ![target respondsToSelector:selector]) return nil;

    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (signature == nil) return nil;
    const char *returnType = signature.methodReturnType;
    if (returnType == NULL || returnType[0] != '@') return nil;

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    invocation.target = target;
    [invocation invoke];

    __unsafe_unretained id result = nil;
    [invocation getReturnValue:&result];
    return result;
}

@implementation OCPAppListController

+ (NSString *)preferencesPath {
    NSString *root = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/lib"]
        ? @"/var/jb" : @"";
    return [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/%@.plist",
            root, kPreferencesDomain];
}

#pragma mark - Đọc/ghi danh sách

- (NSMutableArray<NSString *> *)allowedApplications {
    NSDictionary *preferences =
        [NSDictionary dictionaryWithContentsOfFile:[[self class] preferencesPath]];
    id value = preferences[kAllowedApplicationsKey];
    if (![value isKindOfClass:[NSArray class]]) return [NSMutableArray array];

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
        if ([entry isKindOfClass:[NSString class]]) [result addObject:entry];
    }
    return result;
}

- (void)writeAllowedApplications:(NSArray<NSString *> *)applications {
    NSString *path = [[self class] preferencesPath];
    NSMutableDictionary *preferences =
        [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy]
            ?: [NSMutableDictionary dictionary];
    preferences[kAllowedApplicationsKey] = applications;

    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
    [preferences writeToFile:path atomically:YES];
    notify_post(kPreferencesChangedNotification.UTF8String);
}

#pragma mark - Ứng dụng trên máy

/// [{identifier, name}] đã sắp theo tên, hoặc nil nếu không truy vấn được.
- (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApplications {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (workspaceClass == Nil) return nil;

    id workspace = OCPInvoke(workspaceClass, NSSelectorFromString(@"defaultWorkspace"));
    if (workspace == nil) return nil;

    id proxies = OCPInvoke(workspace, NSSelectorFromString(@"allApplications"));
    if (![proxies isKindOfClass:[NSArray class]]) return nil;

    NSArray<NSString *> *hidden = OCPHiddenIdentifiers();
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *applications = [NSMutableArray array];

    for (id proxy in (NSArray *)proxies) {
        @try {
            NSString *identifier = [proxy valueForKey:@"applicationIdentifier"];
            if (![identifier isKindOfClass:[NSString class]]) continue;
            if ([hidden containsObject:identifier]) continue;

            // Chỉ ứng dụng người dùng cài: app hệ thống phần lớn vô nghĩa trên màn hình xe.
            NSString *type = [proxy valueForKey:@"applicationType"];
            if ([type isKindOfClass:[NSString class]] && ![type isEqualToString:@"User"]) continue;

            NSString *name = [proxy valueForKey:@"localizedName"];
            if (![name isKindOfClass:[NSString class]]) name = identifier;

            [applications addObject:@{ @"identifier": identifier, @"name": name }];
        } @catch (NSException *exception) {
            continue;
        }
    }

    [applications sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return applications;
}

#pragma mark - Dựng bảng

- (NSArray *)specifiers {
    if (_specifiers != nil) return _specifiers;

    NSMutableArray *specifiers = [NSMutableArray array];
    NSArray<NSDictionary<NSString *, NSString *> *> *applications = [self installedApplications];

    if (applications == nil) {
        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        [group setProperty:@"Không đọc được danh sách ứng dụng trên máy này. Sửa khoá "
                            @"AllowedApplications trong "
                            @"/var/jb/var/mobile/Library/Preferences/com.opencarplay.plist "
                            @"bằng Filza."
                    forKey:@"footerText"];
        [specifiers addObject:group];
        _specifiers = specifiers;
        return _specifiers;
    }

    PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
    [group setProperty:[NSString stringWithFormat:
                        @"%lu ứng dụng đã cài. Bật ứng dụng nào thì ứng dụng đó xuất hiện "
                        @"trên dashboard CarPlay khi tính năng thử nghiệm được bật.",
                        (unsigned long)applications.count]
                forKey:@"footerText"];
    [specifiers addObject:group];

    for (NSDictionary<NSString *, NSString *> *application in applications) {
        PSSpecifier *specifier =
            [PSSpecifier preferenceSpecifierNamed:application[@"name"]
                                           target:self
                                              set:@selector(setAllowed:forSpecifier:)
                                              get:@selector(allowedForSpecifier:)
                                           detail:Nil
                                             cell:PSSwitchCell
                                             edit:Nil];
        [specifier setProperty:application[@"identifier"] forKey:@"ocpBundleIdentifier"];
        [specifiers addObject:specifier];
    }

    _specifiers = specifiers;
    return _specifiers;
}

- (id)allowedForSpecifier:(PSSpecifier *)specifier {
    NSString *identifier = [specifier propertyForKey:@"ocpBundleIdentifier"];
    return @([[self allowedApplications] containsObject:identifier]);
}

- (void)setAllowed:(id)value forSpecifier:(PSSpecifier *)specifier {
    NSString *identifier = [specifier propertyForKey:@"ocpBundleIdentifier"];
    if (identifier.length == 0) return;

    NSMutableArray<NSString *> *allowed = [self allowedApplications];
    if ([value boolValue]) {
        if (![allowed containsObject:identifier]) [allowed addObject:identifier];
    } else {
        [allowed removeObject:identifier];
    }
    [self writeAllowedApplications:allowed];
}

@end
