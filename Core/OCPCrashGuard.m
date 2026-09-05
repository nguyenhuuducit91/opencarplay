// OpenCarPlay — xem OCPCrashGuard.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPCrashGuard.h"

#import "OCPDefines.h"
#import "OCPLog.h"
#import "OCPPreferences.h"

/// Nạp nhiều hơn ngần này lần trong kCrashWindow giây nghĩa là SpringBoard đang chết lặp.
/// Người dùng respring thủ công vài lần liên tiếp là chuyện bình thường, nên ngưỡng
/// phải đủ cao để không báo động giả, nhưng đủ thấp để cắt vòng lặp trong ~nửa phút.
static const NSUInteger kCrashThreshold = 4;
static const NSTimeInterval kCrashWindow = 45.0;

/// Sau ngần này giây coi như phiên chạy ổn định.
static const NSTimeInterval kHealthyAfter = 60.0;

@implementation OCPCrashGuard

+ (NSString *)historyPath {
    return @"/var/mobile/Library/Preferences/com.opencarplay.loads.plist";
}

+ (NSArray<NSNumber *> *)loadHistory {
    @try {
        NSArray *history = [NSArray arrayWithContentsOfFile:[self historyPath]];
        if (![history isKindOfClass:[NSArray class]]) return @[];

        NSTimeInterval cutoff = [[NSDate date] timeIntervalSince1970] - kCrashWindow;
        NSMutableArray<NSNumber *> *recent = [NSMutableArray array];
        for (id entry in history) {
            if ([entry isKindOfClass:[NSNumber class]] &&
                [(NSNumber *)entry doubleValue] >= cutoff) {
                [recent addObject:entry];
            }
        }
        return recent;
    } @catch (NSException *exception) {
        return @[];
    }
}

+ (NSUInteger)recentLoadCount {
    return [self loadHistory].count;
}

+ (BOOL)recordLoadAndCheckHealth {
    @try {
        NSMutableArray<NSNumber *> *history = [[self loadHistory] mutableCopy];
        [history addObject:@([[NSDate date] timeIntervalSince1970])];
        [history writeToFile:[self historyPath] atomically:YES];

        if (history.count < kCrashThreshold) return YES;

        // Vòng lặp crash: tạo kill switch để lần nạp sau không chạy gì nữa.
        OCPLogError_(@"phát hiện vòng lặp crash — %lu lần nạp trong %.0f giây. "
                     @"Tự vô hiệu hoá bằng %@",
                     (unsigned long)history.count, kCrashWindow, OCPKillSwitchPath());

        NSString *reason = [NSString stringWithFormat:
            @"Tự tạo bởi OCPCrashGuard lúc %@ sau %lu lần nạp trong %.0f giây.\n"
            @"Xoá file này để bật lại OpenCarPlay.\n",
            [NSDate date], (unsigned long)history.count, kCrashWindow];
        [reason writeToFile:OCPKillSwitchPath()
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:NULL];

        [[NSFileManager defaultManager] removeItemAtPath:[self historyPath] error:NULL];
        return NO;
    } @catch (NSException *exception) {
        // Không đọc/ghi được lịch sử thì cho chạy tiếp — lưới an toàn không được
        // trở thành nguyên nhân làm hỏng tính năng.
        return YES;
    }
}

#pragma mark - Thao tác rủi ro

+ (NSString *)markerPathForOperation:(NSString *)name {
    NSString *safeName = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [NSString stringWithFormat:
        @"/var/mobile/Library/Preferences/com.opencarplay.running-%@", safeName];
}

+ (BOOL)beginRiskyOperation:(NSString *)name disablingPreference:(nullable NSString *)preferenceKey {
    if (name.length == 0) return NO;

    NSString *markerPath = [self markerPathForOperation:name];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:markerPath]) {
        OCPLogError_(@"'%@' đã chạy dở ở lần nạp trước và không hoàn tất — "
                     @"nhiều khả năng nó làm treo máy. Tự tắt lần này.", name);

        [fileManager removeItemAtPath:markerPath error:NULL];

        if (preferenceKey.length > 0) {
            // Qua OCPPreferences chứ không ghi thẳng file: cfprefsd giữ bản nhớ đệm
            // của domain này và sẽ đè lên mọi thứ ghi vòng qua nó.
            if ([[OCPPreferences sharedPreferences] setValue:@NO forPreferenceKey:preferenceKey]) {
                OCPLogError_(@"đã đặt %@ = NO trong preferences", preferenceKey);
            } else {
                OCPLogError_(@"không tắt được %@ trong preferences", preferenceKey);
            }
        }
        return NO;
    }

    @try {
        NSString *content = [NSString stringWithFormat:@"%@\n", [NSDate date]];
        [content writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    } @catch (NSException *exception) {
        // Không ghi được dấu thì vẫn cho chạy — lưới an toàn không được tự nó
        // trở thành lý do chặn tính năng.
    }
    return YES;
}

+ (void)endRiskyOperation:(NSString *)name {
    if (name.length == 0) return;
    [[NSFileManager defaultManager] removeItemAtPath:[self markerPathForOperation:name]
                                               error:NULL];
}

+ (void)markSessionHealthy {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHealthyAfter * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        @try {
            [[NSFileManager defaultManager] removeItemAtPath:[self historyPath] error:NULL];
            OCPLogC(OCPLogCore, @"phiên chạy ổn định — đã xoá lịch sử nạp");
        } @catch (NSException *exception) {
            // không quan trọng
        }
    });
}

@end
