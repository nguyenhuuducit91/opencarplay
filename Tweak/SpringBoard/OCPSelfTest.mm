// OpenCarPlay — xem OCPSelfTest.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPSelfTest.h"

#import <UIKit/UIKit.h>
#import <mach/mach.h>

#import "OCPAppRegistry.h"
#import "OCPCarPlayDetector.h"
#import "OCPCarPlayWindow.h"
#import "OCPCompatibility.h"
#import "OCPDefines.h"
#import "OCPDisplayConfiguration.h"
#import "OCPLog.h"
#import "OCPPreferences.h"
#import "OCPProbe.h"
#import "OCPSceneBridge.h"
#import "OCPTransport.h"
#import "OCPCrashGuard.h"

/// Số vòng cho các bài lặp. Đủ nhiều để rò rỉ lộ ra, đủ ít để không giữ máy quá lâu.
static const NSUInteger kIterations = 8;

@implementation OCPSelfTest {
    NSMutableString *_report;
    NSUInteger _passed;
    NSUInteger _failed;
    NSUInteger _skipped;
}

#pragma mark - Ghi báo cáo

- (instancetype)init {
    if ((self = [super init])) {
        _report = [NSMutableString string];
    }
    return self;
}

- (void)line:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [_report appendFormat:@"%@\n", message];
}

- (void)pass:(NSString *)name detail:(NSString *)detail {
    _passed++;
    [self line:@"  PASS  %-38@ %@", name, detail ?: @""];
}

- (void)fail:(NSString *)name detail:(NSString *)detail {
    _failed++;
    [self line:@"  FAIL  %-38@ %@", name, detail ?: @""];
}

- (void)skip:(NSString *)name reason:(NSString *)reason {
    _skipped++;
    [self line:@"  SKIP  %-38@ %@", name, reason ?: @""];
}

/// Bộ nhớ thường trú của process, dùng để phát hiện rò rỉ qua các vòng lặp.
- (double)residentMemoryMB {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) {
        return -1.0;
    }
    return (double)info.phys_footprint / (1024.0 * 1024.0);
}

#pragma mark - Tầng 1: luôn an toàn

- (void)runFoundationChecks {
    [self line:@"\n--- tầng 1: nền tảng (không đụng CarPlay) ---"];

    if ([OCPCompatibility isSupportedOS]) {
        [self pass:@"phiên bản iOS" detail:[OCPCompatibility systemVersion]];
    } else {
        [self fail:@"phiên bản iOS" detail:[OCPCompatibility unsupportedReason]];
    }

    NSString *architecture = [OCPCompatibility architecture];
    if ([architecture isEqualToString:@"arm64e"] || [architecture isEqualToString:@"arm64"]) {
        [self pass:@"kiến trúc" detail:architecture];
    } else {
        [self fail:@"kiến trúc" detail:architecture];
    }

    NSDictionary<NSString *, NSNumber *> *probe = [OCPProbe diagnosticsReport];
    for (NSString *feature in [probe.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (probe[feature].boolValue) {
            [self pass:[@"probe " stringByAppendingString:feature] detail:nil];
        } else {
            [self fail:[@"probe " stringByAppendingString:feature]
                detail:[[OCPProbe missingRequirementsForFeature:
                          (OCPFeature)[[probe.allKeys sortedArrayUsingSelector:@selector(compare:)]
                                       indexOfObject:feature]]
                        componentsJoinedByString:@", "]];
        }
    }

    // Ghi/đọc preferences: xác nhận đường ghi hoạt động và không làm hỏng cấu hình.
    OCPPreferences *preferences = [OCPPreferences sharedPreferences];
    NSString *probeKey = @"__selftest_probe";
    if ([preferences setValue:@YES forPreferenceKey:probeKey]) {
        [preferences reload];
        BOOL wroteAndRead = [[preferences snapshot] count] > 0;
        [preferences setValue:nil forPreferenceKey:probeKey];
        wroteAndRead ? [self pass:@"ghi/đọc preferences" detail:OCPPreferencesPath()]
                     : [self fail:@"ghi/đọc preferences" detail:@"đọc lại không thấy"];
    } else {
        [self fail:@"ghi/đọc preferences" detail:@"không ghi được"];
    }

    // IPC: gửi cho chính mình và chờ nhận.
    __block BOOL received = NO;
    [[OCPTransport sharedTransport] observeMessage:@"selftest-ping"
                                           handler:^(NSDictionary *payload) { received = YES; }];
    [[OCPTransport sharedTransport] postMessage:@"selftest-ping" payload:@{ @"n": @1 }];
    // Darwin notification đi qua kernel rồi quay lại main queue; chờ ngắn là đủ.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    received ? [self pass:@"IPC gửi/nhận"
                   detail:[[OCPTransport sharedTransport] activeBackendName]]
             : [self fail:@"IPC gửi/nhận" detail:@"không nhận được trong 1 giây"];

    [self pass:@"registry" detail:[[OCPAppRegistry sharedRegistry] summary]];
}

#pragma mark - Tầng 2: cần CarPlay đang kết nối

- (void)runDisplayChecks {
    [self line:@"\n--- tầng 2: màn hình xe (cần CarPlay đang cắm) ---"];

    OCPCarPlayDetector *detector = [OCPCarPlayDetector sharedDetector];
    if (![detector isCarPlayConnected]) {
        [self skip:@"phát hiện màn hình xe" reason:@"CarPlay không kết nối"];
        [self skip:@"tạo/huỷ cửa sổ lặp lại" reason:@"CarPlay không kết nối"];
        return;
    }

    OCPDisplayConfiguration *display = [detector displayConfiguration];
    [self pass:@"phát hiện màn hình xe" detail:[display summary]];

    // Tạo rồi huỷ cửa sổ nhiều lần. Đây là nơi rò rỉ dễ xuất hiện nhất, vì mỗi vòng
    // đều cấp phát một UIWindow gắn vào display của hệ thống.
    double before = [self residentMemoryMB];
    NSTimeInterval firstDuration = 0;
    NSTimeInterval lastDuration = 0;
    NSUInteger created = 0;

    for (NSUInteger i = 0; i < kIterations; i++) {
        NSDate *start = [NSDate date];
        NSError *error = nil;
        OCPCarPlayWindow *window = [OCPCarPlayWindow windowForDisplayConfiguration:display
                                                                             error:&error];
        if (window == nil) {
            [self fail:@"tạo/huỷ cửa sổ lặp lại"
                detail:[NSString stringWithFormat:@"vòng %lu: %@",
                        (unsigned long)i, error.localizedDescription]];
            return;
        }
        [window dismiss];
        created++;

        NSTimeInterval duration = -[start timeIntervalSinceNow];
        if (i == 0) firstDuration = duration;
        lastDuration = duration;
    }

    double after = [self residentMemoryMB];
    double growth = (before > 0 && after > 0) ? (after - before) : 0.0;

    // Ngưỡng: mỗi vòng rò rỉ dưới 0.5MB coi như chấp nhận được; trên đó là dấu hiệu
    // cửa sổ không được giải phóng.
    if (growth > 0.5 * (double)kIterations) {
        [self fail:@"tạo/huỷ cửa sổ lặp lại"
            detail:[NSString stringWithFormat:@"%lu vòng, bộ nhớ tăng %.1fMB — nghi rò rỉ",
                    (unsigned long)created, growth]];
    } else {
        [self pass:@"tạo/huỷ cửa sổ lặp lại"
            detail:[NSString stringWithFormat:@"%lu vòng, bộ nhớ %+.1fMB, vòng đầu %.0fms cuối %.0fms",
                    (unsigned long)created, growth,
                    firstDuration * 1000.0, lastDuration * 1000.0]];
    }
}

#pragma mark - Tầng 3: cần bật scene hosting

- (void)runSceneBridgeChecks {
    [self line:@"\n--- tầng 3: scene bridge (cần ExperimentalSceneHosting) ---"];

    if (![[OCPPreferences sharedPreferences] experimentalSceneHosting]) {
        [self skip:@"tiền đề scene bridge" reason:@"ExperimentalSceneHosting tắt"];
        return;
    }

    NSArray<NSString *> *missing = [OCPSceneBridge missingRequirements];
    if (missing.count > 0) {
        // Đây KHÔNG phải lỗi của tweak — đó là câu trả lời cho Q5 trong RESEARCH.md.
        [self fail:@"tiền đề scene bridge"
            detail:[NSString stringWithFormat:@"thiếu %@", [missing componentsJoinedByString:@", "]]];
        return;
    }
    [self pass:@"tiền đề scene bridge" detail:@"đủ toàn bộ class và selector"];

    NSString *bundleIdentifier =
        [[[OCPAppRegistry sharedRegistry] allowedApplications] firstObject];
    if (bundleIdentifier == nil) {
        [self skip:@"dựng/dọn scene lặp lại" reason:@"danh sách ứng dụng rỗng"];
        return;
    }

    double before = [self residentMemoryMB];
    for (NSUInteger i = 0; i < kIterations / 2; i++) {
        OCPSceneBridge *bridge = [[OCPSceneBridge alloc] init];
        NSError *error = nil;
        UIView *view = [bridge viewForApplicationWithBundleIdentifier:bundleIdentifier
                                                                error:&error];
        if (view == nil) {
            [self fail:@"dựng/dọn scene lặp lại"
                detail:[NSString stringWithFormat:@"vòng %lu: %@",
                        (unsigned long)i, error.localizedDescription]];
            [bridge teardown];
            return;
        }
        [bridge teardown];
    }
    double after = [self residentMemoryMB];

    [self pass:@"dựng/dọn scene lặp lại"
        detail:[NSString stringWithFormat:@"%lu vòng cho %@, bộ nhớ %+.1fMB",
                (unsigned long)(kIterations / 2), bundleIdentifier,
                (before > 0 && after > 0) ? (after - before) : 0.0]];
}

#pragma mark - Điểm vào

- (NSString *)buildReport {
    [self line:@"OpenCarPlay self-test"];
    [self line:@"====================="];
    [self line:@"thời điểm : %@", [NSDate date]];
    [self line:@"môi trường: %@", [OCPCompatibility environmentSummary]];
    [self line:@"bộ nhớ    : %.1f MB", [self residentMemoryMB]];

    [self runFoundationChecks];
    [self runDisplayChecks];
    [self runSceneBridgeChecks];

    [self line:@"\n====================="];
    [self line:@"%lu pass, %lu fail, %lu skip",
        (unsigned long)_passed, (unsigned long)_failed, (unsigned long)_skipped];
    [self line:@"bộ nhớ sau khi chạy: %.1f MB", [self residentMemoryMB]];
    return [_report copy];
}

+ (nullable NSString *)runNow {
    @try {
        OCPSelfTest *test = [[OCPSelfTest alloc] init];
        NSString *report = [test buildReport];

        NSString *directory = @"/var/mobile/Media/OpenCarPlay";
        if (![[NSFileManager defaultManager] fileExistsAtPath:directory]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:NULL];
        }

        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyyMMdd-HHmmss";
        NSString *path = [directory stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"selftest-%@.txt",
                           [formatter stringFromDate:[NSDate date]]]];

        if (![report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
            OCPLogError_(@"không ghi được báo cáo self-test");
            return nil;
        }

        OCPLogError_(@"self-test xong — %@", path);
        return path;
    } @catch (NSException *exception) {
        OCPLogError_(@"self-test ném exception: %@ — %@", exception.name, exception.reason);
        return nil;
    }
}

+ (void)runIfEnabled {
    NSDictionary *preferences =
        [NSDictionary dictionaryWithContentsOfFile:OCPPreferencesPath()];
    id value = preferences[@"SelfTest"];
    BOOL enabled = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
    if (!enabled) return;
    if (![OCPCrashGuard beginRiskyOperation:@"self-test" disablingPreference:@"SelfTest"]) return;

    // Chạy trên main thread vì có đụng UIKit, nhưng lùi lại để hệ thống khởi động xong.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self runNow];
        [OCPCrashGuard endRiskyOperation:@"self-test"];
    });
}

@end
