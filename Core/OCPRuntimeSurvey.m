// OpenCarPlay — xem OCPRuntimeSurvey.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPRuntimeSurvey.h"

#import "OCPCompatibility.h"
#import "OCPDefines.h"
#import "OCPLog.h"
#import "OCPProbe.h"
#import "OCPProcessIdentity.h"

#import <objc/runtime.h>

@implementation OCPRuntimeSurvey

#pragma mark - Liệt kê runtime

+ (NSArray<NSString *> *)classNamesWithPrefix:(NSString *)prefix {
    if (prefix.length == 0) return @[];

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) return @[];

    for (unsigned int i = 0; i < count; i++) {
        const char *raw = class_getName(classes[i]);
        if (raw == NULL) continue;
        NSString *name = @(raw);
        if ([name hasPrefix:prefix]) [names addObject:name];
    }
    free(classes);

    return [names sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSArray<NSString *> *)selectorsForClassNamed:(NSString *)className {
    Class cls = NSClassFromString(className);
    if (cls == Nil) return @[];

    NSMutableArray<NSString *> *selectors = [NSMutableArray array];

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        [selectors addObject:[@"-" stringByAppendingString:
                              NSStringFromSelector(method_getName(methods[i]))]];
    }
    free(methods);

    count = 0;
    methods = class_copyMethodList(object_getClass(cls), &count);
    for (unsigned int i = 0; i < count; i++) {
        [selectors addObject:[@"+" stringByAppendingString:
                              NSStringFromSelector(method_getName(methods[i]))]];
    }
    free(methods);

    return [selectors sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSArray<NSString *> *)ivarsForClassNamed:(NSString *)className {
    Class cls = NSClassFromString(className);
    if (cls == Nil) return @[];

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *raw = ivar_getName(ivars[i]);
        if (raw != NULL) [names addObject:@(raw)];
    }
    free(ivars);

    return [names sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Nội dung khảo sát theo vai trò process

/// Tiền tố class cần liệt kê, tuỳ theo process.
+ (NSArray<NSString *> *)prefixesForRole:(OCPProcessRole)role {
    switch (role) {
        case OCPProcessRoleCarPlayDashboard:
        case OCPProcessRoleCarPlayAuxiliary:
            return @[ @"CAR", @"CRCarPlay", @"CRS", @"CPS", @"CPUI", @"CP" ];
        case OCPProcessRoleSpringBoard:
            return @[ @"SBApp", @"SBScene", @"SBDevice", @"SBMain", @"SBSuspended",
                      @"FBScene", @"FBSDisplay", @"FBSScene", @"UIRootScene" ];
        default:
            return @[];
    }
}

/// Class cần dump chi tiết selector — những class mà kiến trúc phụ thuộc.
/// Xem RESEARCH.md §2.3 (carplay-cast dùng gì) và §3.4 (iOS 18.6 có gì).
+ (NSArray<NSString *> *)detailedClassesForRole:(OCPProcessRole)role {
    switch (role) {
        case OCPProcessRoleCarPlayDashboard:
        case OCPProcessRoleCarPlayAuxiliary:
            return @[ @"CARApplication", @"CARApplicationInfo", @"CARApplicationLaunchInfo",
                      @"CARDashboard", @"CARIconView", @"CARAppDockViewController",
                      @"_CARDashboardHomeViewController",
                      @"CRCarPlayAppDeclaration", @"CRCarPlayAppPolicy",
                      @"CRCarPlayAppPolicyEvaluator", @"CRCarPlayAppDenylist",
                      @"CRCarPlayCapabilities", @"CARSessionStatus", @"CARScreenInfo",
                      @"FBSApplicationLibrary", @"FBSApplicationLibraryConfiguration" ];
        case OCPProcessRoleSpringBoard:
            return @[ @"SBApplicationController", @"SBSceneManagerCoordinator",
                      @"SBMainDisplaySceneManager", @"SBApplicationSceneHandleRequest",
                      @"SBDeviceApplicationSceneEntity", @"SBAppViewController",
                      @"SBDeviceApplicationSceneHandle", @"SBApplicationSceneView",
                      @"SBDeviceApplicationSceneView", @"SBSuspendedUnderLockManager",
                      @"UIRootSceneWindow", @"FBSDisplayConfiguration", @"FBSDisplayMonitor",
                      @"FBScene", @"FBSceneMonitor", @"_UISystemGestureManager" ];
        default:
            return @[];
    }
}

#pragma mark - Ghi kết quả

/// Thư mục ghi kết quả. Ưu tiên /var/mobile/Media vì lấy được qua USB (AFC)
/// mà không cần SSH — xem README → Troubleshooting.
+ (nullable NSString *)prepareOutputDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *candidates = @[
        @"/var/mobile/Media/OpenCarPlay",
        OCPRootedPath(@"/var/mobile/Library/Logs/OpenCarPlay"),
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"OpenCarPlay"],
    ];

    for (NSString *directory in candidates) {
        NSError *error = nil;
        if ([fm fileExistsAtPath:directory] ||
            [fm createDirectoryAtPath:directory
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&error]) {
            // Kiểm tra ghi được thật, không chỉ tạo được thư mục.
            NSString *probe = [directory stringByAppendingPathComponent:@".write-test"];
            if ([@"ok" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
                [fm removeItemAtPath:probe error:NULL];
                return directory;
            }
        }
    }
    return nil;
}

+ (NSString *)surveyText {
    OCPProcessRole role = [OCPProcessIdentity currentRole];
    NSMutableString *out = [NSMutableString string];

    [out appendString:@"OpenCarPlay runtime survey\n"];
    [out appendString:@"==========================\n"];
    [out appendFormat:@"thời điểm : %@\n", [NSDate date]];
    [out appendFormat:@"process   : %@\n", [OCPProcessIdentity summary]];
    [out appendFormat:@"môi trường: %@\n\n", [OCPCompatibility environmentSummary]];

    [out appendString:@"--- probe theo tính năng ---\n"];
    NSDictionary<NSString *, NSNumber *> *report = [OCPProbe diagnosticsReport];
    for (NSString *feature in [report.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [out appendFormat:@"%-20s %@\n", feature.UTF8String,
                          report[feature].boolValue ? @"OK" : @"KHÔNG KHẢ DỤNG"];
    }
    [out appendString:@"\n"];

    [out appendString:@"--- class theo tiền tố ---\n"];
    for (NSString *prefix in [self prefixesForRole:role]) {
        NSArray<NSString *> *names = [self classNamesWithPrefix:prefix];
        [out appendFormat:@"\n[%@] %lu class\n", prefix, (unsigned long)names.count];
        [out appendFormat:@"%@\n", [names componentsJoinedByString:@", "]];
    }

    [out appendString:@"\n\n--- chi tiết class trọng yếu ---\n"];
    for (NSString *className in [self detailedClassesForRole:role]) {
        Class cls = NSClassFromString(className);
        if (cls == Nil) {
            [out appendFormat:@"\n=== %@ : KHÔNG TỒN TẠI ===\n", className];
            continue;
        }
        Class superclass = class_getSuperclass(cls);
        [out appendFormat:@"\n=== %@ : %@ ===\n", className,
                          superclass ? NSStringFromClass(superclass) : @"(root)"];

        NSArray<NSString *> *ivars = [self ivarsForClassNamed:className];
        [out appendFormat:@"ivars (%lu): %@\n", (unsigned long)ivars.count,
                          [ivars componentsJoinedByString:@", "]];

        NSArray<NSString *> *selectors = [self selectorsForClassNamed:className];
        [out appendFormat:@"methods (%lu):\n", (unsigned long)selectors.count];
        for (NSString *selector in selectors) {
            [out appendFormat:@"  %@\n", selector];
        }
    }

    return out;
}

#pragma mark - Điểm vào

+ (nullable NSString *)runNow {
    @try {
        NSString *directory = [self prepareOutputDirectory];
        if (directory == nil) {
            OCPLogError_(@"không tìm được thư mục ghi survey");
            return nil;
        }

        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyyMMdd-HHmmss";
        NSString *filename = [NSString stringWithFormat:@"survey-%@-%@.txt",
                              [OCPProcessIdentity nameForRole:[OCPProcessIdentity currentRole]],
                              [formatter stringFromDate:[NSDate date]]];
        NSString *path = [directory stringByAppendingPathComponent:filename];

        NSError *error = nil;
        if (![[self surveyText] writeToFile:path
                                 atomically:YES
                                   encoding:NSUTF8StringEncoding
                                      error:&error]) {
            OCPLogError_(@"ghi survey thất bại: %@", error.localizedDescription);
            return nil;
        }

        OCPLogError_(@"survey đã ghi: %@", path);
        return path;
    } @catch (NSException *exception) {
        OCPLogError_(@"survey thất bại: %@ — %@", exception.name, exception.reason);
        return nil;
    }
}

+ (void)runIfEnabled {
    BOOL enabled = NO;
    @try {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:OCPPreferencesPath()];
        id value = prefs[@"RuntimeSurvey"];
        enabled = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
    } @catch (NSException *exception) {
        enabled = NO;
    }

    if (!enabled) return;

    // Chạy trễ và ngoài main thread: khảo sát đọc hàng chục nghìn class, không được
    // làm chậm quá trình khởi động của SpringBoard.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self runNow];
    });
}

@end
