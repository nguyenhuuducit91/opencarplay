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

    if (OCPPrefsBootstrapStalled()) {
        PSSpecifier *warning =
            [PSSpecifier groupSpecifierWithName:@"Đã tự hạ về giai đoạn 0"];
        [warning setProperty:@"Lần khởi động trước, OpenCarPlay bắt đầu khởi tạo và không "
                             @"bao giờ báo là đã chạy ổn định — gần như chắc chắn là treo. "
                             @"Tweak đã tự hạ về \"chỉ nạp\" để máy lên được.\n\n"
                             @"Chọn lại giai đoạn bên dưới để thử tiếp; nâng từng bậc một "
                             @"và respring sau mỗi bậc thì sẽ biết chính xác bậc nào hỏng."
                      forKey:@"footerText"];
        [specifiers addObject:warning];
    }
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

    // Giai đoạn khởi tạo nằm ngoài plist chung — xem ghi chú ở OCPPrefsCommon.h.
    if ([key isEqualToString:OCPPrefsStartupStageKey]) {
        return @(OCPPrefsReadStartupStage());
    }

    id value = OCPPrefsRead()[key];
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;

    if ([key isEqualToString:OCPPrefsStartupStageKey]) {
        if (!OCPPrefsWriteStartupStage([value integerValue])) {
            [self showAlertWithTitle:@"Không lưu được"
                             message:@"Không ghi được file giai đoạn khởi tạo. Cấu hình "
                                     @"chưa thay đổi.\n\nĐặt tay bằng Filza hoặc SSH:\n"
                                     @"/var/mobile/Library/Preferences/com.opencarplay.stage"];
        }
        [self reloadSpecifiers];
        return;
    }

    OCPPrefsWrite(key, value);

    // Tắt công tắc chính thì các tuỳ chọn phụ thuộc nó cũng phải hiện đúng trạng thái.
    if ([key isEqualToString:@"Enabled"]) [self reloadSpecifiers];
}

#pragma mark - Hành động

// Hộp thoại xác nhận của hai nút dưới đây do Preferences.framework dựng, khai báo bằng
// khoá "confirmation" trong Root.plist. KHÔNG tự dựng UIAlertController với handler:^ —
// đó là block, và bundle này không được phép tạo block nào (xem OCPPrefsCommon.m).

- (void)resetSettings:(PSSpecifier *)specifier {
    OCPPrefsReset();
    [self reloadSpecifiers];
}

- (void)respring:(PSSpecifier *)specifier {
    // Settings không được phép giết SpringBoard; nó chỉ gửi tín hiệu, phần trong
    // SpringBoard tự khởi động lại. Tweak chưa nạp thì không có gì xảy ra — đó cũng
    // chính là câu trả lời trung thực cho người dùng.
    notify_post("com.opencarplay.respring");
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
