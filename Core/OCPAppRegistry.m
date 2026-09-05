// OpenCarPlay — xem OCPAppRegistry.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPAppRegistry.h"

#import "OCPLog.h"
#import "OCPPreferences.h"
#import "ocp_util.h"

@interface OCPAppRegistry ()
@property (nonatomic, copy) NSArray<NSString *> *allowedApplications;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *rejectedEntries;
@property (nonatomic, strong) NSSet<NSString *> *allowedSet;
@end

@implementation OCPAppRegistry

+ (instancetype)sharedRegistry {
    static OCPAppRegistry *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _allowedApplications = @[];
        _allowedSet = [NSSet set];
        _rejectedEntries = @{};
        [self reload];

        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(handlePreferencesChanged:)
                   name:OCPPreferencesDidChangeNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handlePreferencesChanged:(NSNotification *)notification {
    [self reload];
}

#pragma mark - Nạp

- (void)reload {
    NSMutableArray<NSString *> *accepted = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *rejected = [NSMutableDictionary dictionary];

    for (NSString *entry in [[OCPPreferences sharedPreferences] allowedApplications]) {
        // Chuẩn hoá nhẹ: bỏ khoảng trắng thừa mà người dùng hay gõ nhầm.
        NSString *identifier =
            [entry stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        OCPRegistryDecision decision = [self validateIdentifier:identifier];
        if (decision == OCPRegistryDecisionAllowed) {
            if (![accepted containsObject:identifier]) [accepted addObject:identifier];
        } else {
            rejected[entry.length ? entry : @"(rỗng)"] = [[self class] nameForDecision:decision];
        }
    }

    self.allowedApplications = accepted;
    self.allowedSet = [NSSet setWithArray:accepted];
    self.rejectedEntries = rejected;

    OCPLogC(OCPLogApplication, @"registry nạp lại — %@", [self summary]);
    for (NSString *entry in rejected) {
        OCPLogC(OCPLogApplication, @"  loại \"%@\": %@", entry, rejected[entry]);
    }
}

/// Kiểm tra một identifier, KHÔNG xét tới việc nó có trong danh sách hay không.
- (OCPRegistryDecision)validateIdentifier:(nullable NSString *)identifier {
    if (identifier.length == 0) return OCPRegistryDecisionInvalidIdentifier;

    const char *raw = identifier.UTF8String;
    if (raw == NULL || !ocp_bundle_id_is_valid(raw)) {
        return OCPRegistryDecisionInvalidIdentifier;
    }
    if (ocp_bundle_id_is_system_critical(raw)) {
        return OCPRegistryDecisionSystemCritical;
    }
    return OCPRegistryDecisionAllowed;
}

#pragma mark - Tra cứu

- (OCPRegistryDecision)decisionForBundleIdentifier:(nullable NSString *)bundleIdentifier {
    // Thứ tự quan trọng: chặn cứng phải được xét TRƯỚC danh sách cho phép, để một mục
    // cấu hình sai không bao giờ đưa được process hệ thống lên CarPlay.
    OCPRegistryDecision validation = [self validateIdentifier:bundleIdentifier];
    if (validation != OCPRegistryDecisionAllowed) return validation;

    if (![[OCPPreferences sharedPreferences] enabled]) {
        return OCPRegistryDecisionTweakDisabled;
    }
    if (![self.allowedSet containsObject:bundleIdentifier]) {
        return OCPRegistryDecisionNotListed;
    }
    return OCPRegistryDecisionAllowed;
}

- (BOOL)isAllowed:(nullable NSString *)bundleIdentifier {
    return [self decisionForBundleIdentifier:bundleIdentifier] == OCPRegistryDecisionAllowed;
}

+ (NSString *)nameForDecision:(OCPRegistryDecision)decision {
    switch (decision) {
        case OCPRegistryDecisionAllowed:           return @"được phép";
        case OCPRegistryDecisionTweakDisabled:     return @"tweak đang tắt";
        case OCPRegistryDecisionNotListed:         return @"không có trong danh sách";
        case OCPRegistryDecisionInvalidIdentifier: return @"bundle identifier không hợp lệ";
        case OCPRegistryDecisionSystemCritical:    return @"process hệ thống bị chặn cứng";
    }
    return @"không rõ";
}

- (NSString *)summary {
    return [NSString stringWithFormat:@"%lu app được phép, %lu mục bị loại, tweak %@",
            (unsigned long)self.allowedApplications.count,
            (unsigned long)self.rejectedEntries.count,
            [[OCPPreferences sharedPreferences] enabled] ? @"BẬT" : @"tắt"];
}

@end
