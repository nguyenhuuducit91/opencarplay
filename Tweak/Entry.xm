// OpenCarPlay — entry point.
//
// Phase 3: phát hiện môi trường, logging, probe khả năng. Vẫn chưa cài đặt hook nào —
// nguyên tắc 1 (ARCHITECTURE.md): mặc định không làm gì.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import <Foundation/Foundation.h>

#import "OCPDefines.h"
#import "OCPLog.h"
#import "OCPCompatibility.h"
#import "OCPProbe.h"

%ctor {
    @autoreleasepool {
        @try {
            // 1. Lưới an toàn: file kill switch chặn mọi thứ.
            if (OCPKillSwitchEngaged()) {
                OCPLogError_(@"kill switch đang bật (%@) — không nạp gì trong %@",
                             OCPKillSwitchPath(), [OCPCompatibility currentProcessBundleIdentifier]);
                return;
            }

            [OCPLog reloadConfiguration];

            // 2. Báo cáo môi trường. Luôn ghi ở mức Error để thấy được cả khi
            //    DebugLogging tắt — đây là dấu hiệu duy nhất cho biết tweak đã nạp.
            OCPLogError_(@"loaded — %@", [OCPCompatibility environmentSummary]);

            // 3. Chặn sớm nếu hệ điều hành ngoài phạm vi đã nghiên cứu.
            NSString *unsupported = [OCPCompatibility unsupportedReason];
            if (unsupported != nil) {
                OCPLogError_(@"vô hiệu hoá: %@", unsupported);
                return;
            }

            // 4. Chỉ hoạt động trong hai process đã dự tính. Filter plist đã lọc rồi,
            //    nhưng kiểm tra lại để không phụ thuộc vào cấu hình bên ngoài.
            NSString *bundleID = [OCPCompatibility currentProcessBundleIdentifier];
            BOOL isSpringBoard = [bundleID isEqualToString:OCPBundleIDSpringBoard];
            BOOL isCarPlayApp  = [bundleID isEqualToString:OCPBundleIDCarPlayApp];
            if (!isSpringBoard && !isCarPlayApp) {
                OCPLogC(OCPLogCore, @"process %@ không nằm trong phạm vi — bỏ qua", bundleID);
                return;
            }

            // 5. Thu thập bằng chứng runtime. Kết quả này là đầu vào cho Phase 4+
            //    (xem RESEARCH.md §7 — probe bổ sung cho Frida, chạy trong process thật).
            // Giai đoạn phát triển: ghi ở mức Error để báo cáo hiện ra kể cả khi
            // DebugLogging còn tắt (thiết bị chưa có file preferences).
            [OCPProbe logFullReportAtCategory:OCPLogError];

            OCPLogC(OCPLogCore, @"phase 3: chưa cài hook nào (%@)",
                    isSpringBoard ? @"SpringBoard" : @"CarPlayApp");
        } @catch (NSException *exception) {
            OCPLogError_(@"ctor thất bại: %@ — %@", exception.name, exception.reason);
        }
    }
}
