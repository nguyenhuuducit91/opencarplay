// OpenCarPlay — entry point.
//
// Phase 11: dashboard, khởi chạy, giao diện trên màn hình xe, quan sát âm thanh.
//
// Chuỗi điều kiện trước khi bất cứ thứ gì được kích hoạt — nguyên tắc 1 trong
// ARCHITECTURE.md là mặc định không làm gì:
//   kill switch tắt -> không trong vòng lặp crash -> iOS trong phạm vi ->
//   đúng process -> Enabled = YES -> cổng thử nghiệm tương ứng bật ->
//   probe xác nhận đủ class/selector.
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
#import "OCPPreferences.h"
#import "OCPAppRegistry.h"
#import "OCPLaunchCoordinator.h"
#import "OCPCrashGuard.h"
#import "OCPAudioObserver.h"
#import "OCPTransport.h"

/// Định nghĩa trong Tweak/CarPlayApp/Hooks.xm.
extern void OCPInstallCarPlayHooks(void);

%ctor {
    @autoreleasepool {
        @try {
            OCPProcessRole role = [OCPProcessIdentity currentRole];

            // 1. Lưới an toàn: file kill switch chặn mọi thứ.
            if (OCPKillSwitchEngaged()) {
                OCPLogError_(@"kill switch đang bật (%@) — không nạp gì trong %@",
                             OCPKillSwitchPath(), [OCPCompatibility currentProcessBundleIdentifier]);
                return;
            }

            [OCPLog reloadConfiguration];

            // 2. Lưới an toàn chống bootloop. Từ Phase 9 tweak chạm vào bộ máy scene
            //     của SpringBoard, nên phải có đường tự tắt khi phát hiện chết lặp.
            if (role == OCPProcessRoleSpringBoard && ![OCPCrashGuard recordLoadAndCheckHealth]) {
                OCPLogError_(@"OpenCarPlay tự vô hiệu hoá do phát hiện vòng lặp crash");
                return;
            }

            // 3. Báo cáo môi trường. Luôn ghi ở mức Error để thấy được cả khi
            //    DebugLogging tắt — đây là dấu hiệu duy nhất cho biết tweak đã nạp.
            OCPLogError_(@"loaded — %@", [OCPCompatibility environmentSummary]);

            // 4. Chặn sớm nếu hệ điều hành ngoài phạm vi đã nghiên cứu.
            NSString *unsupported = [OCPCompatibility unsupportedReason];
            if (unsupported != nil) {
                OCPLogError_(@"vô hiệu hoá: %@", unsupported);
                return;
            }

            // 5. Chỉ hoạt động trong hai process đã dự tính. Filter plist đã lọc rồi,
            //    nhưng kiểm tra lại để không phụ thuộc vào cấu hình bên ngoài.
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

            // 6. Nạp cấu hình và danh sách ứng dụng. Hai lớp này chỉ đọc — chưa có gì
            //    được kích hoạt dựa trên chúng cho tới Phase 7.
            OCPPreferences *preferences = [OCPPreferences sharedPreferences];
            OCPAppRegistry *registry = [OCPAppRegistry sharedRegistry];
            OCPLogError_(@"cấu hình: %@ | %@ | ipc=%@",
                         [preferences summary], [registry summary],
                         [[OCPTransport sharedTransport] activeBackendName]);

            if (!preferences.enabled) {
                OCPLogError_(@"Enabled = NO — hệ thống hoạt động y như khi chưa cài tweak");
            }

            // 7. Khảo sát runtime (chỉ khi bật RuntimeSurvey) — công cụ nghiên cứu trả lời
            //    Q1-Q6 trong RESEARCH.md bằng dữ liệu từ chính iOS 18.6.2.
            [OCPRuntimeSurvey runIfEnabled];

            if (isCarPlayApp) {
                // Process này chỉ tồn tại khi CarPlay đang kết nối, nên chính việc dylib
                // được nạp vào đây đã là một tín hiệu kết nối đáng tin — đáng tin hơn cả
                // việc dò notification trong SpringBoard.
                OCPLogError_(@"nạp trong CarPlay dashboard — CarPlay đang kết nối");
                return;
            }

            // SpringBoard: theo dõi kết nối CarPlay và lắng nghe yêu cầu khởi chạy.
            // Không hook gì trong SpringBoard — chỉ dùng đường khởi chạy chuẩn của hệ thống.
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    [[OCPCarPlayDetector sharedDetector] start];
                    [[OCPLaunchCoordinator sharedCoordinator] start];
                    [[OCPAudioObserver sharedObserver] start];
                    [OCPCrashGuard markSessionHealthy];
                } @catch (NSException *exception) {
                    OCPLogError_(@"không khởi động được detector/coordinator: %@", exception.reason);
                }
            });

            OCPLogC(OCPLogCore, @"phase 11: detector + coordinator + scene bridge + audio observer sẵn sàng");
        } @catch (NSException *exception) {
            OCPLogError_(@"ctor thất bại: %@ — %@", exception.name, exception.reason);
        }
    }
}
