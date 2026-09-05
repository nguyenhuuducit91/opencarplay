// OpenCarPlay — entry point.
//
// Phase 4: thêm phát hiện kết nối CarPlay. Vẫn chưa cài đặt hook nào —
// nguyên tắc 1 (ARCHITECTURE.md): mặc định không làm gì.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import <Foundation/Foundation.h>

#import "OCPDefines.h"
#import "OCPLog.h"
#import "OCPCompatibility.h"
#import "OCPProbe.h"
#import "OCPCarPlayDetector.h"

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

            if (isCarPlayApp) {
                // Process này chỉ tồn tại khi CarPlay đang kết nối, nên chính việc dylib
                // được nạp vào đây đã là một tín hiệu kết nối. Phase 5 sẽ khai thác điều đó.
                OCPLogError_(@"nạp trong CarPlay.app — CarPlay đang kết nối");
                return;
            }

            // SpringBoard: theo dõi kết nối CarPlay. Detector chỉ quan sát và ghi log,
            // chưa thay đổi hành vi hệ thống.
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    [[OCPCarPlayDetector sharedDetector] start];
                } @catch (NSException *exception) {
                    OCPLogError_(@"không khởi động được detector: %@", exception.reason);
                }
            });

            OCPLogC(OCPLogCore, @"phase 4: theo dõi kết nối CarPlay (chưa hook gì)");
        } @catch (NSException *exception) {
            OCPLogError_(@"ctor thất bại: %@ — %@", exception.name, exception.reason);
        }
    }
}
