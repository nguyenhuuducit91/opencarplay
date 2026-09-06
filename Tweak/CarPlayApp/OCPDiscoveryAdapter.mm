// OpenCarPlay — xem OCPDiscoveryAdapter.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPDiscoveryAdapter.h"

#import "OCPAppRegistry.h"
#import "OCPLog.h"
#import "OCPPreferences.h"
#import "OCPProbe.h"
#import "OCPCrashGuard.h"

NSString *const OCPApplicationTag = @"OpenCarPlay";

@implementation OCPDiscoveryAdapter

#pragma mark - Điều kiện

+ (BOOL)isEnabled {
    OCPPreferences *preferences = [OCPPreferences sharedPreferences];
    if (!preferences.enabled) return NO;

    // Cổng riêng cho phần thử nghiệm: người dùng phải bật tường minh, vì đây là
    // phần đầu tiên thực sự thay đổi hành vi của CarPlay.
    if (!preferences.experimentalDiscovery) return NO;

    // Nếu lần trước dashboard chết trong lúc dựng danh sách, không thử lại.
    static BOOL guardChecked = NO;
    static BOOL guardPassed = NO;
    if (!guardChecked) {
        guardChecked = YES;
        guardPassed = [OCPCrashGuard beginRiskyOperation:@"carplay-discovery"
                                     disablingPreference:@"ExperimentalDiscovery"];
    }
    if (!guardPassed) return NO;

    if ([[OCPAppRegistry sharedRegistry] allowedApplications].count == 0) {
        OCPLogC(OCPLogApplication, @"discovery bật nhưng danh sách ứng dụng rỗng");
        return NO;
    }
    return YES;
}

+ (NSArray<NSNumber *> *)availableStrategies {
    NSMutableArray<NSNumber *> *strategies = [NSMutableArray array];

    // Chiến lược Declaration cần: class tuyên bố + khả năng thêm proxy vào library.
    BOOL hasDeclaration = ([OCPProbe classNamed:@"CRCarPlayAppDeclaration"] != Nil);
    BOOL canAddProxy = [OCPProbe class:@"FBSApplicationLibrary"
                            respondsTo:@"addApplicationProxy:withOverrideURL:"];
    BOOL hasProxyClass = ([OCPProbe classNamed:@"LSApplicationProxy"] != Nil);
    if (hasDeclaration && canAddProxy && hasProxyClass) {
        [strategies addObject:@(OCPDiscoveryStrategyDeclaration)];
    } else {
        OCPLogC(OCPLogApplication,
                @"chiến lược Declaration không khả dụng — declaration=%d addProxy=%d proxy=%d",
                hasDeclaration, canAddProxy, hasProxyClass);
    }

    // Chiến lược Policy chưa triển khai: cần biết method của CRCarPlayAppPolicyEvaluator,
    // mà điều đó phải đến từ OCPRuntimeSurvey trên thiết bị thật (RESEARCH.md Q1).
    if ([OCPProbe classNamed:@"CRCarPlayAppPolicyEvaluator"] != Nil) {
        OCPLogC(OCPLogApplication,
                @"CRCarPlayAppPolicyEvaluator TỒN TẠI trên hệ thống này — "
                @"bật RuntimeSurvey để lấy danh sách method, đó là đầu vào cho chiến lược Policy");
    }

    return strategies;
}

+ (NSString *)nameForStrategy:(OCPDiscoveryStrategy)strategy {
    switch (strategy) {
        case OCPDiscoveryStrategyDeclaration: return @"Declaration";
        case OCPDiscoveryStrategyPolicy:      return @"Policy";
    }
    return @"Unknown";
}

#pragma mark - Chiến lược Declaration

/// Tạo tuyên bố CarPlay cho một ứng dụng.
///
/// supportsTemplates PHẢI là NO: nếu bật, hệ thống sẽ cố tìm template do ứng dụng
/// cung cấp, không thấy, rồi process host template sẽ spawn và chết liên tục.
/// Đây là bài học rút ra từ phân tích carplay-cast (RESEARCH.md §2.5).
///
/// supportsMaps cũng PHẢI là NO trên iOS 18.
///
/// carplay-cast đặt YES vì trên iOS 14 đó là cách để một app không-template được mở
/// toàn màn hình. Trên iOS 18.6 nó gây hậu quả khác hẳn: mọi app ta thêm đều tự khai
/// là app bản đồ, dashboard cố đặt chúng vào khe bản đồ và host scene bản đồ của
/// chúng. Không app nào có scene CarPlay thật, nên dashboard dựng hỏng và MÀN HÌNH XE
/// ĐEN HOÀN TOÀN — không crash, nên không có crash report, và người dùng chỉ thấy một
/// màn hình đen không thoát ra được.
///
/// Đo trên xe thật: bật ExperimentalDiscovery với supportsMaps=YES -> đen ngay.
+ (nullable id)declarationForBundleIdentifier:(NSString *)bundleIdentifier
                                   bundleURL:(nullable NSURL *)bundleURL {
    id declaration = [OCPProbe instantiateClassNamed:@"CRCarPlayAppDeclaration"];
    if (declaration == nil) return nil;

    BOOL ok = YES;
    ok &= [OCPProbe setValue:@NO forKey:@"supportsTemplates" onObject:declaration];
    ok &= [OCPProbe setValue:@NO forKey:@"supportsMaps" onObject:declaration];
    ok &= [OCPProbe setValue:bundleIdentifier forKey:@"bundleIdentifier" onObject:declaration];
    if (bundleURL != nil) {
        // Không tính vào `ok`: một số bản iOS dùng kiểu khác cho trường này.
        [OCPProbe setValue:bundleURL forKey:@"bundlePath" onObject:declaration];
    }

    if (!ok) {
        OCPLogC(OCPLogApplication, @"không điền được tuyên bố cho %@", bundleIdentifier);
        return nil;
    }
    return declaration;
}

/// Đánh dấu thông tin ứng dụng là do OpenCarPlay đưa lên.
+ (void)tagApplicationInfo:(id)applicationInfo {
    id existing = [OCPProbe valueForKey:@"tags" onObject:applicationInfo];
    NSMutableArray *tags = [NSMutableArray arrayWithObject:OCPApplicationTag];
    if ([existing isKindOfClass:[NSArray class]]) {
        [tags addObjectsFromArray:(NSArray *)existing];
    }
    [OCPProbe setValue:[tags copy] forKey:@"tags" onObject:applicationInfo];
}

+ (BOOL)isOpenCarPlayApplication:(nullable id)applicationInfo {
    if (applicationInfo == nil) return NO;
    id tags = [OCPProbe valueForKey:@"tags" onObject:applicationInfo];
    return [tags isKindOfClass:[NSArray class]] &&
           [(NSArray *)tags containsObject:OCPApplicationTag];
}

+ (BOOL)addApplication:(NSString *)bundleIdentifier toLibrary:(id)library {
    // 1. Ứng dụng có thật trên máy không.
    id proxy = [OCPProbe invoke:[OCPProbe classNamed:@"LSApplicationProxy"]
                       selector:@"applicationProxyForIdentifier:"
                     withObject:bundleIdentifier];
    if (proxy == nil) {
        OCPLogC(OCPLogApplication, @"%@: không có proxy ứng dụng", bundleIdentifier);
        return NO;
    }

    id appState = [OCPProbe invoke:proxy selector:@"appState"];
    if (appState != nil && ![OCPProbe invokeBool:appState selector:@"isValid" fallback:YES]) {
        OCPLogC(OCPLogApplication, @"%@: ứng dụng không ở trạng thái hợp lệ", bundleIdentifier);
        return NO;
    }

    // 2. Đưa vào library của dashboard. Library gốc chỉ chứa app có entitlement CarPlay,
    //    nên ứng dụng thường phải được thêm vào một cách tường minh.
    id existing = [OCPProbe invoke:library
                          selector:@"applicationInfoForBundleIdentifier:"
                        withObject:bundleIdentifier];
    if (existing == nil) {
        NSMethodSignature *signature =
            [library methodSignatureForSelector:
                NSSelectorFromString(@"addApplicationProxy:withOverrideURL:")];
        if (signature == nil) {
            OCPLogC(OCPLogApplication, @"%@: library không nhận thêm proxy", bundleIdentifier);
            return NO;
        }
        @try {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.selector = NSSelectorFromString(@"addApplicationProxy:withOverrideURL:");
            invocation.target = library;
            id overrideURL = nil;
            [invocation setArgument:&proxy atIndex:2];
            [invocation setArgument:&overrideURL atIndex:3];
            [invocation invoke];
        } @catch (NSException *exception) {
            OCPLogError_(@"%@: thêm proxy thất bại — %@", bundleIdentifier, exception.reason);
            return NO;
        }

        existing = [OCPProbe invoke:library
                           selector:@"applicationInfoForBundleIdentifier:"
                         withObject:bundleIdentifier];
    }

    if (existing == nil) {
        OCPLogC(OCPLogApplication, @"%@: vẫn không có trong library sau khi thêm", bundleIdentifier);
        return NO;
    }

    // 3. Ứng dụng đã hỗ trợ CarPlay sẵn thì để nguyên — không đụng vào hành vi gốc.
    if ([OCPProbe valueForKey:@"carPlayDeclaration" onObject:existing] != nil) {
        OCPLogC(OCPLogApplication, @"%@: đã hỗ trợ CarPlay sẵn, bỏ qua", bundleIdentifier);
        return NO;
    }

    // 4. Gắn tuyên bố giả.
    NSURL *bundleURL = [OCPProbe invoke:existing selector:@"bundleURL"];
    id declaration = [self declarationForBundleIdentifier:bundleIdentifier bundleURL:bundleURL];
    if (declaration == nil) return NO;

    if (![OCPProbe setValue:declaration forKey:@"carPlayDeclaration" onObject:existing]) {
        OCPLogC(OCPLogApplication,
                @"%@: KHÔNG gắn được tuyên bố — đây là dấu hiệu iOS 18 đã đổi cơ chế, "
                @"xem RESEARCH.md Q3", bundleIdentifier);
        return NO;
    }

    [self tagApplicationInfo:existing];
    OCPLogC(OCPLogApplication, @"%@: đã đưa lên dashboard", bundleIdentifier);
    return YES;
}

#pragma mark - Điểm vào

+ (NSUInteger)augmentApplicationLibrary:(nullable id)applicationLibrary {
    if (applicationLibrary == nil) return 0;
    if (![self isEnabled]) return 0;

    NSArray<NSNumber *> *strategies = [self availableStrategies];
    if (strategies.count == 0) {
        OCPLogError_(@"không có chiến lược discovery nào khả dụng trên iOS này — "
                     @"CarPlay giữ nguyên hành vi gốc");
        return 0;
    }

    NSUInteger added = 0;
    @try {
        for (NSString *bundleIdentifier in [[OCPAppRegistry sharedRegistry] allowedApplications]) {
            if ([self addApplication:bundleIdentifier toLibrary:applicationLibrary]) added++;
        }
    } @catch (NSException *exception) {
        OCPLogError_(@"augment library thất bại: %@ — %@", exception.name, exception.reason);
    }

    // KHÔNG xoá dấu rủi ro ở đây.
    //
    // Bản trước xoá ngay tại chỗ này, tức coi "dựng xong danh sách" là "an toàn". Sai:
    // dashboard hỏng SAU bước này, khi nó dựng giao diện từ danh sách vừa bị sửa. Màn
    // hình xe đen không phải là crash, nên không có gì để bộ đếm crash bắt, và vì dấu
    // đã bị xoá nên lần cắm sau tweak lại làm hỏng y hệt — hỏng mãi mãi, không tự khỏi.
    //
    // Dấu chỉ được xoá khi dashboard THỰC SỰ hiện lên; xem hook viewDidAppear: trong
    // Hooks.xm. Còn sót lại ở lần cắm sau nghĩa là lần trước dashboard không hiện được,
    // và discovery tự tắt.

    OCPLogError_(@"discovery: %lu/%lu ứng dụng đã đưa lên dashboard (chiến lược %@)",
                 (unsigned long)added,
                 (unsigned long)[[OCPAppRegistry sharedRegistry] allowedApplications].count,
                 [self nameForStrategy:(OCPDiscoveryStrategy)strategies.firstObject.integerValue]);
    return added;
}

@end
