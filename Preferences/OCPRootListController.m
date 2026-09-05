// OpenCarPlay — xem OCPRootListController.h.
//
// Các switch đọc/ghi trực tiếp qua cơ chế `defaults` của PSSpecifier, và mỗi lần đổi
// đều bắn Darwin notification com.opencarplay.prefs-changed — đúng tên mà OCPTransport
// trong tweak đang lắng nghe, nên SpringBoard và CarPlay tự nạp lại mà không cần respring.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPRootListController.h"

#import <UIKit/UIKit.h>
#import <notify.h>
#import <dlfcn.h>

static NSString *const kPreferencesDomain = @"com.opencarplay";
static NSString *const kPreferencesChangedNotification = @"com.opencarplay.prefs-changed";

@implementation OCPRootListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

#pragma mark - Đường dẫn

/// Preferences nằm dưới tiền tố rootless nếu có.
- (NSString *)preferencesPath {
    NSString *root = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/lib"]
        ? @"/var/jb" : @"";
    return [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/%@.plist",
            root, kPreferencesDomain];
}

- (void)notifyTweak {
    notify_post(kPreferencesChangedNotification.UTF8String);
}

#pragma mark - Hành động

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Đặt lại cài đặt?"
                         message:@"Mọi tuỳ chọn trở về mặc định và danh sách ứng dụng được xoá. "
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
    NSError *error = nil;
    NSString *path = [self preferencesPath];

    if ([[NSFileManager defaultManager] fileExistsAtPath:path] &&
        ![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
        UIAlertController *failure = [UIAlertController
            alertControllerWithTitle:@"Không xoá được"
                             message:error.localizedDescription ?: @"Lỗi không xác định"
                      preferredStyle:UIAlertControllerStyleAlert];
        [failure addAction:[UIAlertAction actionWithTitle:@"OK"
                                                    style:UIAlertActionStyleDefault
                                                  handler:nil]];
        [self presentViewController:failure animated:YES completion:nil];
        return;
    }

    [self notifyTweak];

    // Dựng lại bảng để các switch phản ánh giá trị mặc định.
    [self reloadSpecifiers];
}

- (void)respring {
    // sbreload giữ được phiên đăng nhập; nếu không có thì thôi, người dùng tự khởi động lại.
    void *handle = dlopen("/var/jb/usr/lib/libsbreload.dylib", RTLD_LAZY);
    if (handle != NULL) {
        void (*reload)(void) = (void (*)(void))dlsym(handle, "sbreload");
        if (reload != NULL) {
            reload();
            return;
        }
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Khởi động lại giao diện"
                         message:@"Chạy lệnh sau qua SSH hoặc dùng công cụ respring của "
                                 @"trình quản lý gói:\n\nsbreload"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
