// OpenCarPlay — xem OCPProbe.h.
//
// Bảng yêu cầu bên dưới bắt nguồn từ phân tích trong RESEARCH.md. Những mục đến từ
// carplay-cast (iOS 13.5/14) CHƯA được xác minh trên iOS 18.6 — đó chính là lý do
// tồn tại của file này: probe báo cáo cái gì còn, cái gì mất, thay vì đoán.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPProbe.h"
#import "OCPLog.h"

#import <objc/runtime.h>

@implementation OCPProbe

#pragma mark - Bảng yêu cầu

/// Mỗi tính năng: className -> mảng selector ("+sel" hoặc "-sel"). Mảng rỗng = chỉ cần class.
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)requirementsForFeature:(OCPFeature)feature {
    switch (feature) {
        case OCPFeatureCarPlayDetection:
            return @{
                @"FBSDisplayConfiguration" : @[],
                @"FBSDisplayMonitor"       : @[],
                @"CADisplay"               : @[ @"+displays" ],
            };

        case OCPFeatureAppDiscovery:
            return @{
                @"CRCarPlayAppDeclaration"           : @[],
                @"FBSApplicationLibrary"             : @[ @"-allInstalledApplications",
                                                          @"-applicationInfoForBundleIdentifier:" ],
                @"FBSApplicationLibraryConfiguration": @[],
                @"CARApplication"                    : @[],
            };

        case OCPFeatureSceneHosting:
            return @{
                @"SBApplicationController"        : @[ @"+sharedInstance" ],
                @"SBSceneManagerCoordinator"      : @[],
                @"SBApplicationSceneHandleRequest": @[],
                @"SBDeviceApplicationSceneEntity" : @[],
                @"SBAppViewController"            : @[],
                @"FBSceneMonitor"                 : @[],
            };

        case OCPFeatureExternalWindow:
            return @{
                @"UIRootSceneWindow"      : @[ @"-initWithDisplayConfiguration:" ],
                @"FBSDisplayConfiguration": @[],
                @"_UISystemGestureManager": @[ @"+sharedInstance" ],
            };

        case OCPFeatureLockAssertion:
            return @{
                @"FBScene"                     : @[ @"-mutableSettings" ],
                @"SBSuspendedUnderLockManager" : @[],
            };

        case OCPFeatureTransport:
            return @{
                @"NSDistributedNotificationCenter" : @[],
                @"CPDistributedMessagingCenter"    : @[],
            };

        case OCPFeatureCount:
            break;
    }
    return @{};
}

+ (NSString *)nameForFeature:(OCPFeature)feature {
    switch (feature) {
        case OCPFeatureCarPlayDetection: return @"CarPlayDetection";
        case OCPFeatureAppDiscovery:     return @"AppDiscovery";
        case OCPFeatureSceneHosting:     return @"SceneHosting";
        case OCPFeatureExternalWindow:   return @"ExternalWindow";
        case OCPFeatureLockAssertion:    return @"LockAssertion";
        case OCPFeatureTransport:        return @"Transport";
        case OCPFeatureCount:            break;
    }
    return @"Unknown";
}

#pragma mark - Tra cứu runtime

+ (nullable Class)classNamed:(NSString *)name {
    if (name.length == 0) return Nil;

    static NSMutableSet<NSString *> *reportedMissing;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ reportedMissing = [NSMutableSet set]; });

    Class cls = NSClassFromString(name);
    if (cls == Nil) {
        @synchronized (reportedMissing) {
            if (![reportedMissing containsObject:name]) {
                [reportedMissing addObject:name];
                OCPLogC(OCPLogCompatibility, @"class không tồn tại: %@", name);
            }
        }
    }
    return cls;
}

+ (BOOL)class:(NSString *)className respondsTo:(NSString *)selectorName {
    Class cls = [self classNamed:className];
    if (cls == Nil || selectorName.length == 0) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    return selector != NULL && [cls instancesRespondToSelector:selector];
}

+ (BOOL)metaClass:(NSString *)className respondsTo:(NSString *)selectorName {
    Class cls = [self classNamed:className];
    if (cls == Nil || selectorName.length == 0) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    return selector != NULL && [cls respondsToSelector:selector];
}

+ (BOOL)object:(id)object hasIvar:(NSString *)ivarName {
    if (object == nil || ivarName.length == 0) return NO;
    return class_getInstanceVariable([object class], ivarName.UTF8String) != NULL;
}

#pragma mark - Đánh giá tính năng

/// Một mục yêu cầu có được thoả mãn không. `spec` là "+sel", "-sel" hoặc rỗng.
+ (BOOL)satisfiesClass:(NSString *)className selectorSpec:(NSString *)spec {
    if (spec.length == 0) return [self classNamed:className] != Nil;

    NSString *selectorName = [spec substringFromIndex:1];
    if ([spec hasPrefix:@"+"]) {
        return [self metaClass:className respondsTo:selectorName];
    }
    if ([spec hasPrefix:@"-"]) {
        return [self class:className respondsTo:selectorName];
    }
    // Không có tiền tố: coi là instance method.
    return [self class:className respondsTo:spec];
}

+ (NSArray<NSString *> *)missingRequirementsForFeature:(OCPFeature)feature {
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    NSDictionary<NSString *, NSArray<NSString *> *> *requirements =
        [self requirementsForFeature:feature];

    for (NSString *className in requirements) {
        if ([self classNamed:className] == Nil) {
            [missing addObject:className];
            continue;   // thiếu class thì không cần báo từng selector
        }
        for (NSString *spec in requirements[className]) {
            if (![self satisfiesClass:className selectorSpec:spec]) {
                [missing addObject:[NSString stringWithFormat:@"%@[%@ %@]",
                                    [spec hasPrefix:@"+"] ? @"+" : @"-",
                                    className,
                                    [spec substringFromIndex:1]]];
            }
        }
    }
    return [missing sortedArrayUsingSelector:@selector(compare:)];
}

+ (BOOL)featureAvailable:(OCPFeature)feature {
    if (feature < 0 || feature >= OCPFeatureCount) return NO;

    static NSMutableDictionary<NSNumber *, NSNumber *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

    @synchronized (cache) {
        NSNumber *cached = cache[@(feature)];
        if (cached != nil) return cached.boolValue;

        NSArray<NSString *> *missing = [self missingRequirementsForFeature:feature];
        BOOL available = (missing.count == 0);
        cache[@(feature)] = @(available);

        if (!available) {
            OCPLogC(OCPLogCompatibility, @"tính năng %@ KHÔNG khả dụng — thiếu: %@",
                    [self nameForFeature:feature], [missing componentsJoinedByString:@", "]);
        }
        return available;
    }
}

#pragma mark - Gọi private API an toàn

+ (nullable NSInvocation *)invocationFor:(id)target selector:(SEL)selector {
    if (target == nil || selector == NULL) return nil;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (signature == nil) return nil;

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    invocation.target = target;
    return invocation;
}

/// Kiểu trả về của signature có phải object không (@ hoặc #)?
+ (BOOL)signatureReturnsObject:(NSMethodSignature *)signature {
    const char *type = signature.methodReturnType;
    return type != NULL && (type[0] == '@' || type[0] == '#');
}

+ (nullable id)invoke:(nullable id)target selector:(NSString *)selectorName {
    return [self invoke:target selector:selectorName withObject:nil hasArgument:NO];
}

+ (nullable id)invoke:(nullable id)target
             selector:(NSString *)selectorName
           withObject:(nullable id)argument {
    return [self invoke:target selector:selectorName withObject:argument hasArgument:YES];
}

+ (nullable id)invoke:(nullable id)target
             selector:(NSString *)selectorName
           withObject:(nullable id)argument
          hasArgument:(BOOL)hasArgument {
    if (target == nil || selectorName.length == 0) return nil;

    @try {
        SEL selector = NSSelectorFromString(selectorName);
        if (selector == NULL || ![target respondsToSelector:selector]) {
            OCPLogC(OCPLogCompatibility, @"selector không tồn tại: %@ trên %@",
                    selectorName, NSStringFromClass([target class]));
            return nil;
        }

        NSInvocation *invocation = [self invocationFor:target selector:selector];
        if (invocation == nil) return nil;
        if (![self signatureReturnsObject:invocation.methodSignature]) {
            OCPLogC(OCPLogCompatibility, @"%@ không trả về object — dùng biến thể đúng kiểu",
                    selectorName);
            return nil;
        }
        if (hasArgument) {
            if (invocation.methodSignature.numberOfArguments < 3) return nil;
            [invocation setArgument:&argument atIndex:2];
        }

        [invocation invoke];

        __unsafe_unretained id result = nil;
        [invocation getReturnValue:&result];
        return result;
    } @catch (NSException *exception) {
        OCPLogError_(@"gọi %@ thất bại: %@", selectorName, exception.reason);
        return nil;
    }
}

+ (nullable id)invokeClass:(NSString *)className selector:(NSString *)selectorName {
    Class cls = [self classNamed:className];
    if (cls == Nil) return nil;
    return [self invoke:cls selector:selectorName];
}

+ (BOOL)invokeBool:(nullable id)target
          selector:(NSString *)selectorName
          fallback:(BOOL)fallback {
    if (target == nil || selectorName.length == 0) return fallback;

    @try {
        SEL selector = NSSelectorFromString(selectorName);
        if (selector == NULL || ![target respondsToSelector:selector]) return fallback;

        NSInvocation *invocation = [self invocationFor:target selector:selector];
        if (invocation == nil) return fallback;

        const char *type = invocation.methodSignature.methodReturnType;
        if (type == NULL || (type[0] != 'B' && type[0] != 'c' && type[0] != 'i')) return fallback;

        [invocation invoke];
        // BOOL/char/int đều vừa trong NSInteger; đọc theo kích thước thật để tránh rác.
        NSInteger raw = 0;
        [invocation getReturnValue:&raw];
        return (raw & 0xff) != 0;
    } @catch (NSException *exception) {
        OCPLogError_(@"gọi bool %@ thất bại: %@", selectorName, exception.reason);
        return fallback;
    }
}

+ (nullable id)valueForKey:(NSString *)key onObject:(nullable id)object {
    if (object == nil || key.length == 0) return nil;
    @try {
        NSString *ivarName = [@"_" stringByAppendingString:key];
        if (![self object:object hasIvar:key] && ![self object:object hasIvar:ivarName]) {
            SEL getter = NSSelectorFromString(key);
            if (getter == NULL || ![object respondsToSelector:getter]) return nil;
        }
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        OCPLogC(OCPLogCompatibility, @"KVC %@ thất bại: %@", key, exception.reason);
        return nil;
    }
}

+ (NSDictionary<NSString *, NSNumber *> *)diagnosticsReport {
    NSMutableDictionary<NSString *, NSNumber *> *report = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < OCPFeatureCount; i++) {
        OCPFeature feature = (OCPFeature)i;
        report[[self nameForFeature:feature]] = @([self featureAvailable:feature]);
    }
    return report;
}

+ (void)logFullReport {
    [self logFullReportAtCategory:OCPLogCompatibility];
}

+ (void)logFullReportAtCategory:(OCPLogCategory)category {
    OCPLogC(category, @"===== probe report =====");
    for (NSInteger i = 0; i < OCPFeatureCount; i++) {
        OCPFeature feature = (OCPFeature)i;
        NSArray<NSString *> *missing = [self missingRequirementsForFeature:feature];
        if (missing.count == 0) {
            OCPLogC(category, @"  OK   %@", [self nameForFeature:feature]);
        } else {
            OCPLogC(category, @"  MISS %@ — %@",
                    [self nameForFeature:feature], [missing componentsJoinedByString:@", "]);
        }
    }
    OCPLogC(category, @"========================");
}

@end
