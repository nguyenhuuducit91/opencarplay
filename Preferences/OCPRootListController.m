// OpenCarPlay — xem OCPRootListController.h.
//
// Giao diện chia làm ba phần theo mức rủi ro tăng dần: trạng thái (chỉ đọc), cơ bản,
// rồi thử nghiệm. Nhóm trạng thái dựng lúc chạy vì nội dung phụ thuộc thiết bị; phần
// còn lại nằm trong Root.plist.
//
// HAI RÀNG BUỘC CỦA FILE NÀY
//
// 1. KHÔNG BLOCK. Toolchain không ký con trỏ block, hệ thống thì xác thực chúng khi
//    gọi. Xem mục "Giới hạn của toolchain Linux" trong README.
//
// 2. KHÔNG ĐỌC/GHI THẲNG IVAR CỦA LỚP CHA. Bản 0.33.0 gán `_specifiers = ...`, khiến
//    binary phụ thuộc symbol _OBJC_IVAR_$_PSListController._specifiers — tức phụ thuộc
//    bố cục nội bộ của Preferences.framework, thứ Apple đổi lúc nào cũng được. Dùng
//    -setSpecifiers: và một mảng của riêng ta.
//
// Mỗi bước trên đường nạp đều ghi dấu qua OCPPrefsTrace: bảng này đã làm Settings chết
// ba lần, và mỗi lần chẩn đoán bằng suy luận đều sai.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPRootListController.h"
#import "OCPPrefsTrace.h"

#import <UIKit/UIKit.h>
#import <notify.h>

/// Dấu do constructor của tweak ghi ra khi nó nạp được vào một process.
static NSString *const kLoadMarkerPath =
    @"/var/mobile/Media/OpenCarPlay/loaded-SpringBoard.txt";

@interface OCPRootListController ()
/// Bản của riêng ta. Xem ràng buộc 2 ở đầu file.
@property (nonatomic, strong) NSMutableArray *ocpSpecifiers;
@end

@implementation OCPRootListController

#pragma mark - Bundle

// PSListController tìm plist qua -bundle. Chỉ rõ để không phụ thuộc việc lớp này thuộc
// image nào.
- (NSBundle *)bundle {
    NSBundle *bundle = OCPPrefsBundle();
    if (bundle == nil) {
        OCPPrefsTrace("bundle: OCPPrefsBundle() trả nil — lùi về bundleForClass:", NULL);
        bundle = [NSBundle bundleForClass:[self class]];
    }
    return bundle;
}

#pragma mark - Specifiers

- (NSMutableArray *)specifiers {
    if (self.ocpSpecifiers != nil) return self.ocpSpecifiers;

    OCPPrefsTrace("specifiers: bắt đầu", NULL);

    NSMutableArray *combined = [NSMutableArray array];

    // Nhóm trạng thái là phần dựng lúc chạy, tức phần dễ hỏng nhất. Dựng nó TRƯỚC và
    // riêng, để nếu nó hỏng thì phần chính vẫn hiện ra.
    @try {
        OCPPrefsTrace("specifiers: dựng nhóm trạng thái", NULL);
        [combined addObjectsFromArray:[self statusSpecifiers]];
        OCPPrefsTrace("specifiers: nhóm trạng thái xong", NULL);
    } @catch (NSException *exception) {
        OCPPrefsTrace("specifiers: nhóm trạng thái NÉM EXCEPTION",
                      exception.reason.UTF8String);
        [combined removeAllObjects];
        [combined addObjectsFromArray:
            [self errorSpecifiersWithTitle:@"Không dựng được nhóm trạng thái"
                                    detail:exception.reason]];
    }

    @try {
        OCPPrefsTrace("specifiers: nạp Root.plist", [[self bundle].bundlePath UTF8String]);
        NSMutableArray *loaded = [self loadSpecifiersFromPlistName:@"Root" target:self];
        OCPPrefsTrace("specifiers: Root.plist xong",
                      [[NSString stringWithFormat:@"%lu mục",
                        (unsigned long)loaded.count] UTF8String]);
        if (loaded.count > 0) {
            [combined addObjectsFromArray:loaded];
        } else {
            [combined addObjectsFromArray:
                [self errorSpecifiersWithTitle:@"Root.plist trống"
                                        detail:[[self bundle] bundlePath]]];
        }
    } @catch (NSException *exception) {
        OCPPrefsTrace("specifiers: Root.plist NÉM EXCEPTION", exception.reason.UTF8String);
        [combined addObjectsFromArray:
            [self errorSpecifiersWithTitle:@"Không nạp được Root.plist"
                                    detail:exception.reason]];
    }

    self.ocpSpecifiers = combined;

    // Cho lớp cha biết, nhưng qua setter chứ không chạm vào ivar của nó.
    if ([self respondsToSelector:@selector(setSpecifiers:)]) {
        @try {
            [self setSpecifiers:combined];
        } @catch (NSException *exception) {
            OCPPrefsTrace("specifiers: setSpecifiers: ném exception",
                          exception.reason.UTF8String);
        }
    }

    OCPPrefsTrace("specifiers: hoàn tất",
                  [[NSString stringWithFormat:@"%lu mục",
                    (unsigned long)combined.count] UTF8String]);
    return combined;
}

/// Hiện lỗi thành một nhóm trong chính bảng cài đặt. Thà bảng hiện ra kèm lời giải
/// thích còn hơn Settings biến mất không để lại gì.
- (NSArray *)errorSpecifiersWithTitle:(NSString *)title detail:(NSString *)detail {
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:title];
    [group setProperty:(detail.length ? detail : @"(không có chi tiết)")
                forKey:@"footerText"];
    return @[ group ];
}

#pragma mark - Nhóm trạng thái

- (NSArray *)statusSpecifiers {
    NSMutableArray *specifiers = [NSMutableArray array];

    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Trạng thái"];
    [group setProperty:@"Dòng \"Đã nạp\" là bằng chứng tweak thực sự chạy trong "
                       @"SpringBoard. Nếu nó báo chưa, hãy respring; vẫn chưa thì tweak "
                       @"không được nạp và mọi tuỳ chọn bên dưới đều vô nghĩa."
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
        PSSpecifier *warning = [PSSpecifier groupSpecifierWithName:@"Đã tự hạ về giai đoạn 0"];
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
    // setProperty:forKey:@"id" chứ không phải -setIdentifier:. Cùng chỗ lưu (PSIDKey),
    // nhưng chỉ dùng một method mà mọi bản iOS đều có.
    [specifier setProperty:identifier forKey:@"id"];
    return specifier;
}

- (id)versionValue:(PSSpecifier *)specifier {
    NSString *version = [OCPPrefsBundle() objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return version.length ? version : @"?";
}

- (id)loadStateValue:(PSSpecifier *)specifier {
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:kLoadMarkerPath error:NULL];
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
        [self rebuildSpecifiers];
        return;
    }

    OCPPrefsWrite(key, value);

    // Tắt công tắc chính thì các tuỳ chọn phụ thuộc nó cũng phải hiện đúng trạng thái.
    if ([key isEqualToString:@"Enabled"]) [self rebuildSpecifiers];
}

#pragma mark - Hành động

// Hộp thoại xác nhận của hai nút dưới đây do Preferences.framework dựng, khai báo bằng
// khoá "confirmation" trong Root.plist — không tự dựng UIAlertController với handler:^,
// vì đó là block.

- (void)resetSettings:(PSSpecifier *)specifier {
    OCPPrefsReset();
    [self rebuildSpecifiers];
}

- (void)respring:(PSSpecifier *)specifier {
    // Settings không được phép giết SpringBoard; nó chỉ gửi tín hiệu, phần trong
    // SpringBoard tự khởi động lại. Tweak chưa nạp thì không có gì xảy ra — đó cũng
    // chính là câu trả lời trung thực cho người dùng.
    notify_post("com.opencarplay.respring");
}

- (void)rebuildSpecifiers {
    self.ocpSpecifiers = nil;
    @try {
        [self reloadSpecifiers];
    } @catch (NSException *exception) {
        OCPPrefsTrace("reloadSpecifiers ném exception", exception.reason.UTF8String);
    }
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
