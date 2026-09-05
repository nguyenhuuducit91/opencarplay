// OpenCarPlay — entry point.
//
// Phase 11: dashboard, khởi chạy, giao diện trên màn hình xe, quan sát âm thanh.
//
// VÌ SAO %ctor Ở ĐÂY GẦN NHƯ TRỐNG RỖNG
//
// Constructor của dylib chạy trong dyld, rất sớm — trước khi process kịp dựng xong
// run loop và các hệ thống con của nó. Bản trước làm gần như toàn bộ việc khởi tạo
// ngay trong constructor, trong đó có notify_register_dispatch gắn vào main queue.
// Trong SpringBoard, điều đó làm process ĐƠ hoàn toàn: không crash nên không có crash
// report, không tự khởi động lại nên bộ đếm crash cũng không thấy gì, và máy treo ở
// màn hình khởi động cho tới khi người dùng nhấn nút nguồn.
//
// Nguyên tắc từ đây: constructor chỉ được dùng C thuần và chỉ làm ba việc — nhận diện
// process, kiểm tra kill switch, và xếp phần còn lại vào main queue. Mọi thứ đụng tới
// Objective-C, file, hay dispatch source đều nằm trong OCPBootstrap.
//
// Chuỗi điều kiện trước khi bất cứ thứ gì được kích hoạt — nguyên tắc 1 trong
// ARCHITECTURE.md là mặc định không làm gì:
//   kill switch tắt -> không trong vòng lặp crash -> iOS trong phạm vi ->
//   đúng process -> Enabled = YES -> cổng thử nghiệm tương ứng bật ->
//   probe xác nhận đủ class/selector.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import <Foundation/Foundation.h>

#import <unistd.h>
#import <string.h>
#import <stdlib.h>

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
#import "OCPSelfTest.h"
#import "OCPTransport.h"

/// Định nghĩa trong Tweak/CarPlayApp/Hooks.xm.
extern void OCPInstallCarPlayHooks(void);

/// Toàn bộ khởi tạo thật. Chạy trên main queue sau khi process đã dựng xong run loop.
static void OCPBootstrap(BOOL isSpringBoard, BOOL isCarPlayApp) {
    @autoreleasepool {
        @try {
            [OCPLog reloadConfiguration];

            // Lưới an toàn chống bootloop.
            if (isSpringBoard && ![OCPCrashGuard recordLoadAndCheckHealth]) {
                OCPLogError_(@"OpenCarPlay tự vô hiệu hoá do phát hiện vòng lặp crash");
                return;
            }

            OCPLogError_(@"loaded — %@", [OCPCompatibility environmentSummary]);

            NSString *unsupported = [OCPCompatibility unsupportedReason];
            if (unsupported != nil) {
                OCPLogError_(@"vô hiệu hoá: %@", unsupported);
                return;
            }

            OCPLogError_(@"%@", [OCPProcessIdentity summary]);
            [OCPProbe logFullReportAtCategory:OCPLogError];

            OCPPreferences *preferences = [OCPPreferences sharedPreferences];
            OCPAppRegistry *registry = [OCPAppRegistry sharedRegistry];
            OCPLogError_(@"cấu hình: %@ | %@ | ipc=%@",
                         [preferences summary], [registry summary],
                         [[OCPTransport sharedTransport] activeBackendName]);

            if (!preferences.enabled) {
                OCPLogError_(@"Enabled = NO — hệ thống hoạt động y như khi chưa cài tweak");
            }

            [OCPRuntimeSurvey runIfEnabled];
            if (isSpringBoard) [OCPSelfTest runIfEnabled];

            if (isCarPlayApp) {
                OCPLogError_(@"nạp trong CarPlay dashboard — CarPlay đang kết nối");
                OCPInstallCarPlayHooks();
                return;
            }

            @try {
                [[OCPCarPlayDetector sharedDetector] start];
                [[OCPLaunchCoordinator sharedCoordinator] start];
                [[OCPAudioObserver sharedObserver] start];
                [OCPCrashGuard markSessionHealthy];
            } @catch (NSException *exception) {
                OCPLogError_(@"không khởi động được thành phần SpringBoard: %@", exception.reason);
            }

            OCPLogC(OCPLogCore, @"khởi tạo xong");
        } @catch (NSException *exception) {
            OCPLogError_(@"khởi tạo thất bại: %@ — %@", exception.name, exception.reason);
        }
    }
}

%ctor {
    // C thuần từ đầu tới cuối. Không Objective-C, không cấp phát, không chạm đĩa
    // ngoài access(), không đăng ký dispatch source. Xem ghi chú ở đầu file.

    const char *processName = getprogname();
    if (processName == NULL) return;

    BOOL isSpringBoard = (strcmp(processName, "SpringBoard") == 0);
    BOOL isCarPlayApp  = (strcmp(processName, "CarPlay") == 0);
    if (!isSpringBoard && !isCarPlayApp) return;

    // Kill switch. Kiểm tra cả hai vị trí bằng access() thay vì NSFileManager.
    // Vị trí thứ hai nằm trong vùng AFC nên tạo được qua cáp USB khi máy đang treo.
    if (access("/var/jb/var/mobile/Library/Preferences/com.opencarplay.disabled", F_OK) == 0 ||
        access("/var/mobile/Library/Preferences/com.opencarplay.disabled", F_OK) == 0 ||
        access("/var/mobile/Media/OpenCarPlay/DISABLED", F_OK) == 0) {
        return;
    }

    // Phần còn lại chờ tới khi process sẵn sàng. dispatch_async chỉ xếp hàng, không
    // chờ, nên an toàn ngay cả ở thời điểm sớm này.
    dispatch_async(dispatch_get_main_queue(), ^{
        OCPBootstrap(isSpringBoard, isCarPlayApp);
    });
}
