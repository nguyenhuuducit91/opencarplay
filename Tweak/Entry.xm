// OpenCarPlay — entry point.
//
// Phase 5: nhận diện process + khảo sát runtime. Vẫn chưa cài đặt hook nào —
// nguyên tắc 1 (ARCHITECTURE.md): mặc định không làm gì.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import <Foundation/Foundation.h>

#import "OCPDefines.h"
#import "OCPLog.h"
#import "OCPCompatibility.h"
#import "OCPProbe.h"
#import "OCPCarPlayDetector.h"
#import "OCPProcessIdentity.h"
#import "OCPRuntimeSurvey.h"

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
            OCPProcessRole role = [OCPProcessIdentity currentRole];
            BOOL isSpringBoard = (role == OCPProcessRoleSpringBoard);
            BOOL isCarPlayApp  = (role == OCPProcessRoleCarPlayDashboard);
            if (!isSpringBoard && !isCarPlayApp) {
                OCPLogC(OCPLogCore, @"%@ — ngoài phạm vi, bỏ qua", [OCPProcessIdentity summary]);
                return;
            }
            OCPLogError_(@"%@", [OCPProcessIdentity summary]);

            // 5. Thu thập bằng chứng runtime. Kết quả này là đầu vào cho Phase 4+
            //    (xem RESEARCH.md §7 — probe bổ sung cho Frida, chạy trong process thật).
            // Giai đoạn phát triển: ghi ở mức Error để báo cáo hiện ra kể cả khi
            // DebugLogging còn tắt (thiết bị chưa có file preferences).
            [OCPProbe logFullReportAtCategory:OCPLogError];

            // 6. Khảo sát runtime (chỉ khi bật RuntimeSurvey) — công cụ nghiên cứu trả lời
            //    Q1-Q6 trong RESEARCH.md bằng dữ liệu từ chính iOS 18.6.2.
            [OCPRuntimeSurvey runIfEnabled];

            if (isCarPlayApp) {
                // Process này chỉ tồn tại khi CarPlay đang kết nối, nên chính việc dylib
                // được nạp vào đây đã là một tín hiệu kết nối đáng tin — đáng tin hơn cả
                // việc dò notification trong SpringBoard.
                OCPLogError_(@"nạp trong CarPlay dashboard — CarPlay đang kết nối");
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

            OCPLogC(OCPLogCore, @"phase 5: theo dõi kết nối CarPlay + khảo sát runtime (chưa hook gì)");
        } @catch (NSException *exception) {
            OCPLogError_(@"ctor thất bại: %@ — %@", exception.name, exception.reason);
        }
    }
}
