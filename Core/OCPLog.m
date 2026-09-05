// OpenCarPlay — xem OCPLog.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPLog.h"
#import "OCPDefines.h"

#import <os/log.h>

static BOOL sDebugLoggingEnabled = NO;

@implementation OCPLog

+ (os_log_t)osLog {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.opencarplay.tweak", "tweak");
    });
    return log;
}

+ (BOOL)debugLoggingEnabled {
    return sDebugLoggingEnabled;
}

+ (void)setDebugLoggingEnabled:(BOOL)enabled {
    sDebugLoggingEnabled = enabled;
}

+ (void)reloadConfiguration {
    // Đọc trực tiếp, không qua OCPPreferences: logging phải hoạt động được
    // ngay cả khi lớp preferences chưa sẵn sàng.
    @try {
        id value = OCPPreferencesCopyRaw()[@"DebugLogging"];
        sDebugLoggingEnabled = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
    } @catch (NSException *exception) {
        sDebugLoggingEnabled = NO;
    }
}

+ (NSString *)tagForCategory:(OCPLogCategory)category {
    switch (category) {
        case OCPLogCore:          return @"[OpenCarPlay]";
        case OCPLogCarPlay:       return @"[CarPlay]";
        case OCPLogApplication:   return @"[Application]";
        case OCPLogRendering:     return @"[Rendering]";
        case OCPLogTouch:         return @"[Touch]";
        case OCPLogAudio:         return @"[Audio]";
        case OCPLogCompatibility: return @"[Compatibility]";
        case OCPLogError:         return @"[Error]";
    }
    return @"[OpenCarPlay]";
}

+ (void)log:(OCPLogCategory)category format:(NSString *)format, ... {
    if (category != OCPLogError && !sDebugLoggingEnabled) return;
    if (format == nil) return;

    @try {
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);

        NSString *line = [NSString stringWithFormat:@"[OpenCarPlay]%@ %@",
                          (category == OCPLogCore) ? @"" : [self tagForCategory:category],
                          message];

        if (category == OCPLogError) {
            os_log_error([self osLog], "%{public}@", line);
        } else {
            os_log([self osLog], "%{public}@", line);
        }
    } @catch (NSException *exception) {
        // Ghi log không bao giờ được phép làm chết process gọi nó.
    }
}

@end
