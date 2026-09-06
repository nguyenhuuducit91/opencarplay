// OpenCarPlay — xem OCPPreferences.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPPreferences.h"

#import "OCPDefines.h"
#import "OCPLog.h"
#import "OCPTransport.h"

NSString *const OCPPreferencesDidChangeNotification = @"OCPPreferencesDidChangeNotification";

@interface OCPPreferences ()
@property (nonatomic, copy) NSDictionary<NSString *, id> *cache;
@property (nonatomic, assign) BOOL hasStoredConfiguration;
@end

@implementation OCPPreferences

+ (instancetype)sharedPreferences {
    static OCPPreferences *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _cache = @{};
        [self reload];

        // Nhận thông báo khi process khác (hoặc bảng cài đặt) đổi preferences.
        __weak typeof(self) weakSelf = self;
        [[OCPTransport sharedTransport] observeMessage:OCPMessagePreferencesChanged
                                               handler:^(NSDictionary *payload) {
            [weakSelf reload];
        }];
    }
    return self;
}

#pragma mark - Đọc

- (void)reload {
    NSDictionary *loaded = nil;
    @try {
        OCPMigrateLegacyPreferences();
        loaded = OCPPreferencesCopyRaw();
        // "Đã cấu hình" nghĩa là có ít nhất một giá trị, dù nó nằm ở cfprefsd hay ở
        // file. Bản trước chỉ nhìn file nên báo "chưa cấu hình" ngay sau khi người
        // dùng bật công tắc trong Settings.
        _hasStoredConfiguration = (loaded.count > 0);
    } @catch (NSException *exception) {
        OCPLogError_(@"đọc preferences thất bại: %@", exception.reason);
        loaded = nil;
    }

    self.cache = loaded ?: @{};
    [OCPLog setDebugLoggingEnabled:self.debugLogging];

    OCPLogC(OCPLogCore, @"preferences nạp lại — %@", [self summary]);
    [[NSNotificationCenter defaultCenter] postNotificationName:OCPPreferencesDidChangeNotification
                                                        object:self];
}

/// Đọc BOOL an toàn: giá trị sai kiểu (chuỗi, mảng, null) đều rơi về mặc định.
- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id value = self.cache[key];
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    if ([value isKindOfClass:[NSString class]]) {
        NSString *lowercase = [(NSString *)value lowercaseString];
        if ([lowercase isEqualToString:@"yes"] || [lowercase isEqualToString:@"true"] ||
            [lowercase isEqualToString:@"1"]) {
            return YES;
        }
        if ([lowercase isEqualToString:@"no"] || [lowercase isEqualToString:@"false"] ||
            [lowercase isEqualToString:@"0"]) {
            return NO;
        }
    }
    return defaultValue;
}

- (BOOL)enabled          { return [self boolForKey:@"Enabled"          defaultValue:NO]; }
- (BOOL)autoLaunch       { return [self boolForKey:@"AutoLaunch"       defaultValue:NO]; }
- (BOOL)hideStatusBar    { return [self boolForKey:@"HideStatusBar"    defaultValue:NO]; }
- (BOOL)fullScreen       { return [self boolForKey:@"FullScreen"       defaultValue:NO]; }
- (BOOL)forceLandscape   { return [self boolForKey:@"ForceLandscape"   defaultValue:YES]; }
- (BOOL)debugLogging     { return [self boolForKey:@"DebugLogging"     defaultValue:NO]; }
- (BOOL)runtimeSurvey    { return [self boolForKey:@"RuntimeSurvey"    defaultValue:NO]; }
- (BOOL)signalDiscovery  { return [self boolForKey:@"SignalDiscovery"  defaultValue:NO]; }
- (BOOL)experimentalDiscovery {
    return [self boolForKey:@"ExperimentalDiscovery" defaultValue:NO];
}
- (BOOL)experimentalSceneHosting {
    return [self boolForKey:@"ExperimentalSceneHosting" defaultValue:NO];
}

/// Chấp nhận cả mảng lẫn chuỗi.
///
/// Mảng là dạng gốc, dùng khi sửa file bằng Filza. Chuỗi ngăn cách bằng dấu phẩy là
/// dạng mà bảng cài đặt ghi ra: bảng không có mã thực thi (xem README), nên ô nhập chỉ
/// lưu được một chuỗi. Chấp nhận cả hai là việc của bên đọc, không phải của người dùng.
- (NSArray<NSString *> *)allowedApplications {
    id value = self.cache[@"AllowedApplications"];

    NSArray *entries = nil;
    if ([value isKindOfClass:[NSArray class]]) {
        entries = (NSArray *)value;
    } else if ([value isKindOfClass:[NSString class]]) {
        NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",;\n\r\t "];
        entries = [(NSString *)value componentsSeparatedByCharactersInSet:separators];
    } else {
        return @[];
    }

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (id entry in entries) {
        if (![entry isKindOfClass:[NSString class]]) continue;
        NSString *trimmed = [(NSString *)entry stringByTrimmingCharactersInSet:whitespace];
        if (trimmed.length > 0 && ![result containsObject:trimmed]) [result addObject:trimmed];
    }
    return result;
}

#pragma mark - Ghi

- (BOOL)setValue:(nullable id)value forPreferenceKey:(NSString *)key {
    if (key.length == 0) return NO;

    @try {
        NSMutableDictionary *updated = [self.cache mutableCopy];
        if (value == nil) {
            [updated removeObjectForKey:key];
        } else {
            updated[key] = value;
        }

        // Ghi qua CFPreferences, cùng đường mà bảng cài đặt dùng. Ghi thẳng vào file
        // thì cfprefsd có thể đè lại bằng bản nhớ đệm của nó và thay đổi biến mất.
        CFStringRef domain = (__bridge CFStringRef)OCPPreferencesDomain;
        CFPreferencesSetValue((__bridge CFStringRef)key,
                              (__bridge CFPropertyListRef)value,
                              domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (!CFPreferencesAppSynchronize(domain)) {
            OCPLogError_(@"ghi preferences thất bại: cfprefsd từ chối domain %@",
                         OCPPreferencesDomain);
            return NO;
        }

        self.cache = updated;
        _hasStoredConfiguration = YES;
        [OCPLog setDebugLoggingEnabled:self.debugLogging];
        [[OCPTransport sharedTransport] postMessage:OCPMessagePreferencesChanged payload:nil];
        return YES;
    } @catch (NSException *exception) {
        OCPLogError_(@"ghi preferences thất bại: %@", exception.reason);
        return NO;
    }
}

#pragma mark - Chẩn đoán

- (NSDictionary<NSString *, id> *)snapshot {
    return @{
        @"Enabled":             @(self.enabled),
        @"AllowedApplications": self.allowedApplications,
        @"AutoLaunch":          @(self.autoLaunch),
        @"HideStatusBar":       @(self.hideStatusBar),
        @"FullScreen":          @(self.fullScreen),
        @"ForceLandscape":      @(self.forceLandscape),
        @"DebugLogging":        @(self.debugLogging),
        @"RuntimeSurvey":       @(self.runtimeSurvey),
        @"SignalDiscovery":     @(self.signalDiscovery),
        @"ExperimentalDiscovery": @(self.experimentalDiscovery),
        @"ExperimentalSceneHosting": @(self.experimentalSceneHosting),
        @"Configured":          @(self.hasStoredConfiguration),
    };
}

- (NSString *)summary {
    if (!self.hasStoredConfiguration) return @"chưa cấu hình bao giờ (mọi tuỳ chọn tắt)";
    return [NSString stringWithFormat:
            @"Enabled=%@ apps=%lu debug=%@ survey=%@ signals=%@ experimental=%@",
            self.enabled ? @"YES" : @"NO",
            (unsigned long)self.allowedApplications.count,
            self.debugLogging ? @"YES" : @"NO",
            self.runtimeSurvey ? @"YES" : @"NO",
            self.signalDiscovery ? @"YES" : @"NO",
            self.experimentalDiscovery ? @"YES" : @"NO"];
}

@end
