// OpenCarPlay — xem OCPPreferences.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPPreferences.h"

#import "OCPDefines.h"
#import "OCPLog.h"
#import "OCPTransport.h"

NSString *const OCPPreferencesDidChangeNotification = @"OCPPreferencesDidChangeNotification";

@interface OCPPreferences ()
@property (nonatomic, copy) NSDictionary<NSString *, id> *cache;
@property (nonatomic, assign) BOOL fileExists;
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
        NSString *path = OCPPreferencesPath();
        _fileExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
        if (_fileExists) {
            loaded = [NSDictionary dictionaryWithContentsOfFile:path];
            if (![loaded isKindOfClass:[NSDictionary class]]) {
                OCPLogError_(@"preferences không phải dictionary — bỏ qua nội dung");
                loaded = nil;
            }
        }
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

- (NSArray<NSString *> *)allowedApplications {
    id value = self.cache[@"AllowedApplications"];
    if (![value isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
        if ([entry isKindOfClass:[NSString class]]) [result addObject:entry];
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

        NSString *path = OCPPreferencesPath();
        NSString *directory = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:NULL];

        if (![updated writeToFile:path atomically:YES]) {
            OCPLogError_(@"ghi preferences thất bại: %@", path);
            return NO;
        }

        self.cache = updated;
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
        @"FileExists":          @(self.fileExists),
    };
}

- (NSString *)summary {
    if (!self.fileExists) return @"chưa có file cấu hình (mọi tuỳ chọn tắt)";
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
