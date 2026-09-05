// OpenCarPlay — lớp điều khiển bảng cài đặt, dựng hoàn toàn lúc chạy.
//
// VÌ SAO KHÔNG DÙNG @interface KẾ THỪA PSListController
//
// Đã thử hai lần và cả hai lần Settings chết với cùng một backtrace:
//
//     libobjc  readClass()          <- EXC_BREAKPOINT
//     libobjc  map_images()
//     dyld     dlopen_from()
//     Foundation -[NSBundle principalClass]
//
// Khi bundle khai báo một lớp kế thừa lớp bên ngoài, con trỏ superclass nằm trong
// metadata (__objc_classlist) và với arm64e nó phải mang định dạng authenticated
// pointer. Toolchain Linux (ld64-609) không sinh đúng định dạng đó. Tắt sinh lệnh PAC
// bằng -fno-ptrauth-* KHÔNG giải quyết được, vì cờ đó chỉ ảnh hưởng mã lệnh chứ không
// ảnh hưởng con trỏ trong metadata.
//
// File này vì thế không khai báo lớp Objective-C nào ở thời điểm biên dịch:
// __objc_classlist rỗng thì readClass() không có gì để đọc. Lớp được dựng lúc chạy
// bằng objc_allocateClassPair, superclass lấy qua NSClassFromString — đường đi không
// qua map_images nên không phụ thuộc định dạng con trỏ do linker sinh.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import <Foundation/Foundation.h>

#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

static NSString *const kControllerClassName = @"OCPRootListController";
static NSString *const kSpecifierPlistName = @"Root";
static NSString *const kPreferencesDomain = @"com.opencarplay";
static NSString *const kPreferencesChangedNotification = @"com.opencarplay.prefs-changed";

static char kSpecifiersKey;

#pragma mark - Tiện ích

/// Bundle chứa Root.plist.
///
/// PSListController tìm plist qua -[PSViewController bundle], mà mặc định là bundle
/// của lớp. Lớp dựng lúc chạy không thuộc image nào nên NSBundle trả về bundle của
/// Settings — đó là lý do bản trước hiện bảng trống. Vì vậy phải chỉ rõ.
static NSBundle *OCPPreferenceBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *path in @[ @"/var/jb/Library/PreferenceBundles/OpenCarPlayPrefs.bundle",
                                  @"/Library/PreferenceBundles/OpenCarPlayPrefs.bundle" ]) {
            if ([fileManager fileExistsAtPath:path]) {
                bundle = [NSBundle bundleWithPath:path];
                break;
            }
        }
    });
    return bundle;
}

static NSString *OCPPreferencesPath(void) {
    NSString *root = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/lib"]
        ? @"/var/jb" : @"";
    return [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/%@.plist",
            root, kPreferencesDomain];
}

/// Gọi selector hai tham số trả về object. Chữ ký khớp chính xác với
/// -[PSListController loadSpecifiersFromPlistName:target:].
static id OCPSend2(id target, SEL selector, id first, id second) {
    if (target == nil || selector == NULL || ![target respondsToSelector:selector]) return nil;
    id (*send)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;
    return send(target, selector, first, second);
}

static id OCPSend0(id target, SEL selector) {
    if (target == nil || selector == NULL || ![target respondsToSelector:selector]) return nil;
    id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return send(target, selector);
}

#pragma mark - Phương thức của lớp dựng lúc chạy

/// -[OCPRootListController bundle]
static id OCPBundleIMP(id self, SEL _cmd) {
    return OCPPreferenceBundle();
}

/// -[OCPRootListController specifiers]
static id OCPSpecifiersIMP(id self, SEL _cmd) {
    id cached = objc_getAssociatedObject(self, &kSpecifiersKey);
    if (cached != nil) return cached;

    id specifiers = OCPSend2(self,
                             NSSelectorFromString(@"loadSpecifiersFromPlistName:target:"),
                             kSpecifierPlistName,
                             self);
    if (specifiers == nil) {
        NSLog(@"[OpenCarPlay] không nạp được %@.plist từ %@",
              kSpecifierPlistName, [OCPPreferenceBundle() bundlePath]);
        return nil;
    }

    objc_setAssociatedObject(self, &kSpecifiersKey, specifiers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return specifiers;
}

/// -[OCPRootListController resetSettings] — nối với PSButtonCell trong Root.plist.
static void OCPResetIMP(id self, SEL _cmd) {
    NSString *path = OCPPreferencesPath();
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    notify_post(kPreferencesChangedNotification.UTF8String);

    // Dựng lại bảng để các công tắc phản ánh giá trị mặc định.
    objc_setAssociatedObject(self, &kSpecifiersKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    OCPSend0(self, NSSelectorFromString(@"reloadSpecifiers"));
}

#pragma mark - Đăng ký

__attribute__((constructor))
static void OCPRegisterPreferenceController(void) {
    @autoreleasepool {
        if (NSClassFromString(kControllerClassName) != Nil) return;

        Class superclass = NSClassFromString(@"PSListController");
        if (superclass == Nil) {
            NSLog(@"[OpenCarPlay] không có PSListController — bỏ qua bảng cài đặt");
            return;
        }

        Class controller = objc_allocateClassPair(superclass,
                                                  kControllerClassName.UTF8String, 0);
        if (controller == Nil) return;

        class_addMethod(controller, NSSelectorFromString(@"specifiers"),
                        (IMP)OCPSpecifiersIMP, "@@:");
        class_addMethod(controller, NSSelectorFromString(@"bundle"),
                        (IMP)OCPBundleIMP, "@@:");
        class_addMethod(controller, NSSelectorFromString(@"resetSettings"),
                        (IMP)OCPResetIMP, "v@:");

        objc_registerClassPair(controller);
    }
}
