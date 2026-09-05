// OpenCarPlay — xem OCPApplicationListController.h.
//
// Danh sách ứng dụng lấy từ LSApplicationWorkspace lúc chạy. Không có bảng cứng nào
// trong code: máy nào có app nào thì hiện app đó.
//
// Ứng dụng hệ thống bị loại khỏi danh sách, khớp với chặn cứng trong
// Core/ocp_util.c — nếu chọn được ở đây mà tweak vẫn từ chối thì giao diện đang nói dối.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPApplicationListController.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

@interface OCPApplicationListController ()
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *applications;
@property (nonatomic, strong) NSMutableSet<NSString *> *selected;
@end

@implementation OCPApplicationListController

#pragma mark - Nạp danh sách

/// Gọi selector không tham số, trả object. Mọi thứ ở đây đều là API riêng của Apple
/// nên phải kiểm tra sự tồn tại trước khi gọi.
static id OCPSend(id target, NSString *selectorName) {
    if (target == nil) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (selector == NULL || ![target respondsToSelector:selector]) return nil;
    id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return send(target, selector);
}

- (void)loadApplications {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *result = [NSMutableArray array];

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = OCPSend(workspaceClass, @"defaultWorkspace");
    NSArray *proxies = OCPSend(workspace, @"allApplications");

    for (id proxy in proxies) {
        if (![proxy isKindOfClass:[NSObject class]]) continue;

        NSString *type = OCPSend(proxy, @"applicationType");
        // Chỉ ứng dụng người dùng cài. "System" và "Internal" là process của Apple —
        // đưa chúng lên CarPlay không có ý nghĩa và bị registry chặn cứng.
        if (![type isKindOfClass:[NSString class]] || ![type isEqualToString:@"User"]) continue;

        NSString *identifier = OCPSend(proxy, @"applicationIdentifier");
        if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) continue;

        NSString *name = OCPSend(proxy, @"localizedName");
        if (![name isKindOfClass:[NSString class]] || name.length == 0) name = identifier;

        [result addObject:@{ @"id": identifier, @"name": name }];
    }

    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    self.applications = result;
}

- (void)loadSelection {
    id stored = OCPPrefsRead()[OCPPrefsAllowedApplicationsKey];
    NSMutableSet<NSString *> *selected = [NSMutableSet set];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)stored) {
            if ([entry isKindOfClass:[NSString class]]) [selected addObject:entry];
        }
    }
    self.selected = selected;
}

#pragma mark - Specifiers

- (NSString *)navigationTitle {
    return @"Ứng dụng";
}

- (NSMutableArray *)specifiers {
    if (_specifiers == nil) {
        [self loadApplications];
        [self loadSelection];

        NSMutableArray *specifiers = [NSMutableArray array];

        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        [group setProperty:@"Chọn ứng dụng được phép hiện trên màn hình xe. Danh sách "
                           @"chỉ gồm ứng dụng bạn tự cài; ứng dụng hệ thống bị chặn cứng "
                           @"và không xuất hiện ở đây.\n\nThay đổi có hiệu lực ngay, "
                           @"không cần respring."
                    forKey:@"footerText"];
        [specifiers addObject:group];

        if (self.applications.count == 0) {
            PSSpecifier *empty = [PSSpecifier preferenceSpecifierNamed:@"Không tìm thấy ứng dụng nào"
                                                                target:nil
                                                                   set:NULL
                                                                   get:NULL
                                                                detail:Nil
                                                                  cell:PSStaticTextCell
                                                                  edit:Nil];
            [specifiers addObject:empty];
        }

        for (NSDictionary<NSString *, NSString *> *application in self.applications) {
            PSSpecifier *specifier =
                [PSSpecifier preferenceSpecifierNamed:application[@"name"]
                                               target:self
                                                  set:@selector(setSelected:specifier:)
                                                  get:@selector(isSelected:)
                                               detail:Nil
                                                 cell:PSSwitchCell
                                                 edit:Nil];
            [specifier setIdentifier:application[@"id"]];
            [specifier setProperty:application[@"id"] forKey:@"bundleIdentifier"];
            // Icon do Settings nạp lười — không tự đọc file icon của ứng dụng.
            [specifier setProperty:@YES forKey:@"useLazyIcons"];
            [specifier setProperty:application[@"id"] forKey:@"appIDForLazyIcon"];
            [specifiers addObject:specifier];
        }

        _specifiers = specifiers;
    }
    return _specifiers;
}

#pragma mark - Đọc / ghi

- (id)isSelected:(PSSpecifier *)specifier {
    NSString *identifier = [specifier propertyForKey:@"bundleIdentifier"];
    return @(identifier.length > 0 && [self.selected containsObject:identifier]);
}

- (void)setSelected:(id)value specifier:(PSSpecifier *)specifier {
    NSString *identifier = [specifier propertyForKey:@"bundleIdentifier"];
    if (identifier.length == 0) return;

    if ([value boolValue]) {
        [self.selected addObject:identifier];
    } else {
        [self.selected removeObject:identifier];
    }

    // Giữ thứ tự ổn định để file cấu hình không đổi vô cớ giữa các lần ghi.
    NSArray<NSString *> *sorted =
        [self.selected.allObjects sortedArrayUsingSelector:@selector(compare:)];
    OCPPrefsWrite(OCPPrefsAllowedApplicationsKey, sorted);
}

@end
