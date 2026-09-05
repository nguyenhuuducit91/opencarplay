// OpenCarPlay — xem OCPCrashGuard.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPCrashGuard.h"

#import "OCPDefines.h"
#import "OCPLog.h"

/// Nạp nhiều hơn ngần này lần trong kCrashWindow giây nghĩa là SpringBoard đang chết lặp.
/// Người dùng respring thủ công vài lần liên tiếp là chuyện bình thường, nên ngưỡng
/// phải đủ cao để không báo động giả, nhưng đủ thấp để cắt vòng lặp trong ~nửa phút.
static const NSUInteger kCrashThreshold = 4;
static const NSTimeInterval kCrashWindow = 45.0;

/// Sau ngần này giây coi như phiên chạy ổn định.
static const NSTimeInterval kHealthyAfter = 60.0;

@implementation OCPCrashGuard

+ (NSString *)historyPath {
    return OCPRootedPath(@"/var/mobile/Library/Preferences/com.opencarplay.loads.plist");
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
