// OpenCarPlay — xem OCPRootListController.h.
//
// Bundle này từng làm Settings crash, nhưng nguyên nhân là slice arm64e do toolchain
// Linux sinh ra không tương thích pointer authentication — không phải cách viết lớp.
// Sau khi bỏ arm64e, viết lớp theo cách thông thường là an toàn.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPRootListController.h"

#import <UIKit/UIKit.h>
#import <notify.h>

static NSString *const kPreferencesDomain = @"com.opencarplay";
static NSString *const kPreferencesChangedNotification = @"com.opencarplay.prefs-changed";

@implementation OCPRootListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

/// Đường dẫn preferences, có tiền tố rootless nếu máy dùng /var/jb.
+ (NSString *)preferencesPath {
    NSString *root = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/lib"]
        ? @"/var/jb" : @"";
    return [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/%@.plist",
            root, kPreferencesDomain];
}

+ (void)notifyTweak {
    notify_post(kPreferencesChangedNotification.UTF8String);
}

#pragma mark - Hành động

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Đặt lại cài đặt?"
                         message:@"Mọi tuỳ chọn trở về mặc định và danh sách ứng dụng bị xoá. "
                                 @"Không thể hoàn tác."
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đặt lại"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [self performReset];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performReset {
    NSString *path = [[self class] preferencesPath];
    NSError *error = nil;

    if ([[NSFileManager defaultManager] fileExistsAtPath:path] &&
        ![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
        [self showMessage:@"Không xoá được"
                     body:error.localizedDescription ?: @"Lỗi không xác định"];
        return;
    }

    [[self class] notifyTweak];
    [self reloadSpecifiers];
    [self showMessage:@"Đã đặt lại" body:@"Mọi tuỳ chọn trở về mặc định."];
}

- (void)showMessage:(NSString *)title body:(NSString *)body {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:body
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respring {
    // Không tự gọi sbreload: bảng cài đặt không nên giả định công cụ nào có mặt.
    // Hướng dẫn rõ ràng vẫn tốt hơn một nút im lặng không làm gì.
    [self showMessage:@"Khởi động lại giao diện"
                 body:@"Dùng nút Respring trong Sileo, hoặc chạy sbreload qua SSH.\n\n"
                      @"Thay đổi các tuỳ chọn ở trên có hiệu lực ngay, không cần respring."];
}

@end
