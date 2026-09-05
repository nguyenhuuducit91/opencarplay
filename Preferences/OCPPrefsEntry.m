// OpenCarPlay — lớp điều khiển cho bảng cài đặt, tạo hoàn toàn lúc chạy.
//
// VÌ SAO KHÔNG DÙNG @interface KẾ THỪA PSListController
//
// Bản trước làm đúng như vậy và Settings chết ngay khi nạp bundle: libobjc phải bind
// _OBJC_CLASS_$_PSListController để dựng superclass, việc bind đó đi qua chained fixups
// do ld64-609 của toolchain Linux sinh ra, và trên arm64e/iOS 18.6 nó cho con trỏ
// superclass không xác thực được — EXC_BREAKPOINT ngay trong readClass().
//
// File này vì thế KHÔNG định nghĩa lớp Objective-C nào ở thời điểm biên dịch. Không có
// gì trong __objc_classlist thì readClass() không có gì để đọc. Lớp được dựng lúc chạy
// bằng objc_allocateClassPair với superclass lấy qua NSClassFromString — đúng nguyên
// tắc mà dylib chính đã dùng từ đầu và chưa gây sự cố lần nào.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import <Foundation/Foundation.h>

#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kControllerClassName = @"OCPRootListController";
static NSString *const kSpecifierPlistName = @"Root";

/// Khoá cho specifiers đã nạp, gắn vào từng instance.
static char kSpecifiersKey;

/// Gọi selector hai tham số trả về object.
///
/// Dùng objc_msgSend ép kiểu thay vì NSInvocation, để bundle không cần tham chiếu tới
/// một class ngoài nào cả. Chữ ký ở đây khớp chính xác với
/// -[PSListController loadSpecifiersFromPlistName:target:] nên việc ép kiểu là an toàn;
/// rủi ro trên arm64e chỉ đến khi chữ ký sai.
static id OCPInvoke2(id target, SEL selector, id first, id second) {
    if (target == nil || selector == NULL || ![target respondsToSelector:selector]) return nil;

    id (*send)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;
    return send(target, selector, first, second);
}

/// Cài đặt cho -[OCPRootListController specifiers].
///
/// PSListController của hệ thống không tự tìm plist nào cả — mỗi bảng cài đặt phải tự
/// nói mình đọc file nào. Đó là toàn bộ lý do lớp này tồn tại.
static id OCPSpecifiersIMP(id self, SEL _cmd) {
    id cached = objc_getAssociatedObject(self, &kSpecifiersKey);
    if (cached != nil) return cached;

    id specifiers = OCPInvoke2(self,
                               NSSelectorFromString(@"loadSpecifiersFromPlistName:target:"),
                               kSpecifierPlistName,
                               self);
    if (specifiers != nil) {
        objc_setAssociatedObject(self, &kSpecifiersKey, specifiers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return specifiers;
}

__attribute__((constructor))
static void OCPRegisterPreferenceController(void) {
    @autoreleasepool {
        // Đã tồn tại (bundle bị nạp hai lần) thì thôi.
        if (NSClassFromString(kControllerClassName) != Nil) return;

        Class superclass = NSClassFromString(@"PSListController");
        if (superclass == Nil) {
            NSLog(@"[OpenCarPlay] PSListController không có — không dựng được bảng cài đặt");
            return;
        }

        Class controller = objc_allocateClassPair(superclass,
                                                  kControllerClassName.UTF8String,
                                                  0);
        if (controller == Nil) return;

        class_addMethod(controller,
                        NSSelectorFromString(@"specifiers"),
                        (IMP)OCPSpecifiersIMP,
                        "@@:");
        objc_registerClassPair(controller);
    }
}
