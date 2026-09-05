// OpenCarPlay — xem OCPRootListController.h.
//
// Giao diện chia làm ba phần, theo đúng mức rủi ro tăng dần:
//   1. Trạng thái  — chỉ đọc, cho biết tweak có thực sự nạp được không.
//   2. Cơ bản      — công tắc chính và danh sách ứng dụng.
//   3. Thử nghiệm  — những thứ đổi hành vi CarPlay, mặc định tắt.
//
// Nhóm Trạng thái được dựng lúc chạy vì nội dung của nó phụ thuộc thiết bị; phần còn
// lại nằm trong Root.plist.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPRootListController.h"

#import <UIKit/UIKit.h>
#import <notify.h>

/// Dấu do constructor của tweak ghi ra khi nó nạp được vào một process.
/// Xem OCPWriteLoadMarker() trong Tweak/Entry.xm.
static NSString *OCPLoadMarkerPath(NSString *processName) {
    return [NSString stringWithFormat:@"/var/mobile/Media/OpenCarPlay/loaded-%@.txt",
            processName];
}

@implementation OCPRootListController

#pragma mark - Bundle

// PSListController tìm plist qua -bundle. Chỉ rõ để không phụ thuộc vào việc lớp này
// thuộc image nào.
- (NSBundle *)bundle {
    return OCPPrefsBundle() ?: [NSBundle bundleForClass:[self class]];
}

#pragma mark - Specifiers

- (NSMutableArray *)specifiers {
    if (_specifiers == nil) {
        NSMutableArray *loaded = [self loadSpecifiersFromPlistName:@"Root" target:self];
        if (loaded == nil) loaded = [NSMutableArray array];

        NSMutableArray *combined = [NSMutableArray array];
        [combined addObjectsFromArray:[self statusSpecifiers]];
        [combined addObjectsFromArray:loaded];
        _specifiers = combined;
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Số ứng dụng đã chọn và trạng thái nạp có thể đã đổi khi quay lại từ màn khác.
    [self refreshDynamicRows];
}

- (void)refreshDynamicRows {
    for (NSString *identifier in @[ @"OCPStatusLoad", @"OCPStatusApps" ]) {
        PSSpecifier *specifier = [self specifierForID:identifier];
        if (specifier != nil) [self reloadSpecifier:specifier animated:NO];
    }
    PSSpecifier *appLink = [self specifierForID:@"OCPApplicationsLink"];
    if (appLink != nil) [self reloadSpecifier:appLink animated:NO];
}

#pragma mark - Nhóm trạng thái

- (NSArray<PSSpecifier *> *)statusSpecifiers {
    NSMutableArray<PSSpecifier *> *specifiers = [NSMutableArray array];

    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Trạng thái"];
    [group setProperty:@"Dòng \"Đã nạp\" là bằng chứng tweak thực sự chạy trong "
                       @"SpringBoard. Nếu nó báo chưa, hãy respring; vẫn chưa thì "
                       @"tweak không được nạp và mọi tuỳ chọn bên dưới đều vô nghĩa."
                forKey:@"footerText"];
    [specifiers addObject:group];

    [specifiers addObject:[self valueRowWithIdentifier:@"OCPStatusVersion"
                                                 label:@"Phiên bản"
                                                getter:@selector(versionValue:)]];
    [specifiers addObject:[self valueRowWithIdentifier:@"OCPStatusLoad"
                                                 label:@"Đã nạp vào SpringBoard"
                                                getter:@selector(loadStateValue:)]];
    [specifiers addObject:[self valueRowWithIdentifier:@"OCPStatusApps"
                                                 label:@"Ứng dụng đã chọn"
                                                getter:@selector(applicationCountValue:)]];
    return specifiers;
}

- (PSSpecifier *)valueRowWithIdentifier:(NSString *)identifier
                                  label:(NSString *)label
                                 getter:(SEL)getter {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:label
                                                            target:self
                                                               set:NULL
                                                               get:getter
                                                            detail:Nil
                                                              cell:PSTitleValueCell
                                                              edit:Nil];
    [specifier setIdentifier:identifier];
    [specifier setProperty:@YES forKey:@"enabled"];
    return specifier;
}

- (id)versionValue:(PSSpecifier *)specifier {
    NSString *version = [OCPPrefsBundle() objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return version.length ? version : @"?";
}

- (id)loadStateValue:(PSSpecifier *)specifier {
    NSString *path = OCPLoadMarkerPath(@"SpringBoard");
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path
                                                                                error:NULL];
    NSDate *modified = attributes[NSFileModificationDate];
    if (modified == nil) return @"chưa";

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:modified];
}

- (id)applicationCountValue:(PSSpecifier *)specifier {
    id value = OCPPrefsRead()[OCPPrefsAllowedApplicationsKey];
    NSUInteger count = [value isKindOfClass:[NSArray class]] ? [(NSArray *)value count] : 0;
    return [NSString stringWithFormat:@"%lu", (unsigned long)count];
}

#pragma mark - Đọc / ghi cấu hình

// Không dùng cài đặt mặc định của PSListController: nó chỉ ghi qua CFPreferences và
// không ép xuống đĩa, trong khi tweak đọc thẳng file. OCPPrefsWrite làm cả hai việc.
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return [specifier propertyForKey:@"default"];

    id value = OCPPrefsRead()[key];
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;

    OCPPrefsWrite(key, value);

    // Tắt công tắc chính thì các tuỳ chọn phụ thuộc nó cũng phải hiện đúng trạng thái.
    if ([key isEqualToString:@"Enabled"]) [self reloadSpecifiers];
}

#pragma mark - Hành động

- (void)resetSettings:(PSSpecifier *)specifier {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Đặt lại cài đặt?"
                         message:@"Mọi tuỳ chọn và danh sách ứng dụng sẽ trở về mặc định "
                                 @"(tất cả đều tắt). Không thể hoàn tác."
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đặt lại"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        OCPPrefsReset();
        [self reloadSpecifiers];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respring:(PSSpecifier *)specifier {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Respring?"
                         message:@"SpringBoard sẽ khởi động lại để nạp lại tweak. "
                                 @"Màn hình khoá sẽ hiện ra trong vài giây."
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        // Settings không được phép giết SpringBoard; nó chỉ gửi tín hiệu, phần trong
        // SpringBoard tự khởi động lại. Tweak chưa nạp thì không có gì xảy ra — đó
        // cũng chính là câu trả lời trung thực cho người dùng.
        notify_post("com.opencarplay.respring");
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
