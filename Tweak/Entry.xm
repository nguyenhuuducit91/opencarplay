// OpenCarPlay — entry point.
//
// GIAI ĐOẠN KHỞI TẠO
//
// Quá trình khởi tạo chia thành các GIAI ĐOẠN đánh số. Mặc định chạy hết — đó là hành
// vi đúng của một tweak đã cài. File STAGE chỉ dùng để HẠ giai đoạn khi cần chẩn đoán,
// và máy tính ghi được nó qua cáp USB mà không cần vào giao diện iPhone.
//
// Nhờ vậy nguyên nhân treo máy xác định được bằng thực nghiệm: hạ dần giai đoạn cho tới
// khi máy khởi động lại được thì giai đoạn kế tiếp chính là chỗ hỏng.
//
// Điều khiển từ máy tính:
//     echo 0 > /tmp/STAGE && afcclient put /tmp/STAGE /OpenCarPlay/STAGE  # chỉ nạp dylib
//     afcclient rm /OpenCarPlay/STAGE                                     # trở lại đầy đủ
//     afcclient put /tmp/x /OpenCarPlay/DISABLED                          # tắt hẳn
//
// LỊCH SỬ: bản 0.22–0.30 lấy giai đoạn 0 làm MẶC ĐỊNH. Hậu quả là tweak cài xong không
// làm gì cả trừ khi người dùng đẩy file STAGE qua cáp — một công cụ gỡ lỗi bị để lại
// làm hành vi mặc định.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import <Foundation/Foundation.h>

#import <UIKit/UIKit.h>

#import <fcntl.h>
#import <notify.h>
#import <objc/message.h>
#import <os/log.h>
#import <sys/syslog.h>
#import <sys/stat.h>
#import <time.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#import "OCPAppRegistry.h"
#import "OCPAudioObserver.h"
#import "OCPCarPlayDetector.h"
#import "OCPCompatibility.h"
#import "OCPCrashGuard.h"
#import "OCPDefines.h"
#import "OCPLaunchCoordinator.h"
#import "OCPLog.h"
#import "OCPPreferences.h"
#import "OCPProbe.h"
#import "OCPProcessIdentity.h"
#import "OCPRuntimeSurvey.h"
#import "OCPSelfTest.h"
#import "OCPTransport.h"

/// Định nghĩa trong Tweak/CarPlayApp/Hooks.xm.
extern void OCPInstallCarPlayHooks(void);

#pragma mark - Giai đoạn khởi tạo

typedef NS_ENUM(int, OCPStartupStage) {
    /// Chỉ nạp dylib và ghi một dòng log. Không chạm gì khác.
    OCPStartupStageLoadOnly       = 0,
    /// + phát hiện môi trường và probe runtime (chỉ đọc).
    OCPStartupStageEnvironment    = 1,
    /// + đọc cấu hình và danh sách ứng dụng.
    OCPStartupStagePreferences    = 2,
    /// + theo dõi kết nối CarPlay.
    OCPStartupStageDetector       = 3,
    /// + điều phối khởi chạy và quan sát âm thanh.
    OCPStartupStageCoordinator    = 4,
    /// + hook trong process CarPlay dashboard.
    OCPStartupStageHooks          = 5,
};

/// Giai đoạn khi không có file điều khiển: chạy hết.
#define OCP_DEFAULT_STARTUP_STAGE OCPStartupStageHooks

/// Đọc giai đoạn từ file điều khiển. Dùng open/read thuần, không Objective-C, vì hàm
/// này được gọi từ constructor.
static int OCPReadStartupStage(void) {
    int fd = open("/var/mobile/Media/OpenCarPlay/STAGE", O_RDONLY);
    if (fd < 0) return OCP_DEFAULT_STARTUP_STAGE;

    char buffer[8] = {0};
    ssize_t bytes = read(fd, buffer, sizeof(buffer) - 1);
    close(fd);
    // File rỗng là lỗi tay người dùng, không phải yêu cầu tắt tweak.
    if (bytes <= 0) return OCP_DEFAULT_STARTUP_STAGE;

    // File chỉ chứa khoảng trắng cũng vậy: atoi() trả 0 cho mọi chuỗi không phải số,
    // và với mặc định cũ điều đó âm thầm vô hiệu hoá tweak.
    int hasDigit = 0;
    for (size_t i = 0; i < sizeof(buffer) && buffer[i] != '\0'; i++) {
        if (buffer[i] >= '0' && buffer[i] <= '9') { hasDigit = 1; break; }
    }
    if (!hasDigit) return OCP_DEFAULT_STARTUP_STAGE;

    int stage = atoi(buffer);
    if (stage < OCPStartupStageLoadOnly) return OCPStartupStageLoadOnly;
    if (stage > OCPStartupStageHooks) return OCPStartupStageHooks;
    return stage;
}

/// Kiểm tra cả hai vị trí kill switch. Vị trí trong /var/mobile/Media ghi được qua USB.
static int OCPKillSwitchFileFound(void) {
    static const char *const paths[] = {
        "/var/jb/var/mobile/Library/Preferences/com.opencarplay.disabled",
        "/var/mobile/Library/Preferences/com.opencarplay.disabled",
        "/var/mobile/Media/OpenCarPlay/DISABLED",
        NULL,
    };
    for (int i = 0; paths[i] != NULL; i++) {
        if (access(paths[i], F_OK) == 0) return i + 1;   // trả về vị trí tìm thấy
    }
    return 0;
}

#pragma mark - Respring theo yêu cầu của bảng cài đặt

/// Settings không được phép giết SpringBoard, nên nút Respring trong bảng cài đặt chỉ
/// gửi một Darwin notification. Phần nhận nằm ở đây.
static void OCPRegisterRespringListener(void) {
    static int token = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        uint32_t status = notify_register_dispatch("com.opencarplay.respring", &token,
                                                   dispatch_get_main_queue(), ^(int t) {
            OCPLogError_(@"nhận yêu cầu respring từ bảng cài đặt");

            // Đường của SpringBoard: dọn dẹp rồi khởi động lại đúng cách.
            UIApplication *application = [UIApplication sharedApplication];
            SEL relaunch = NSSelectorFromString(@"_relaunchSpringBoardNow");
            if ([application respondsToSelector:relaunch]) {
                ((void (*)(id, SEL))objc_msgSend)(application, relaunch);
                return;
            }
            // Không có thì để launchd dựng lại. Thô hơn nhưng vẫn là respring.
            exit(0);
        });
        if (status != NOTIFY_STATUS_OK) {
            OCPLogError_(@"không đăng ký được kênh respring (status %u)", status);
        }
    });
}

#pragma mark - Khởi tạo thật

static void OCPBootstrap(BOOL isSpringBoard, BOOL isCarPlayApp, int stage) {
    @autoreleasepool {
        @try {
            [OCPLog reloadConfiguration];

            if (isSpringBoard && ![OCPCrashGuard recordLoadAndCheckHealth]) {
                OCPLogError_(@"tự vô hiệu hoá do phát hiện vòng lặp crash");
                return;
            }

            // Giai đoạn 1 — chỉ đọc, không đăng ký gì.
            OCPLogError_(@"giai đoạn %d | %@", stage, [OCPCompatibility environmentSummary]);

            NSString *unsupported = [OCPCompatibility unsupportedReason];
            if (unsupported != nil) {
                OCPLogError_(@"vô hiệu hoá: %@", unsupported);
                return;
            }
            [OCPProbe logFullReportAtCategory:OCPLogError];
            if (stage < OCPStartupStagePreferences) {
                OCPLogError_(@"dừng ở giai đoạn %d theo cấu hình", stage);
                return;
            }

            // Giai đoạn 2 — đọc cấu hình. OCPPreferences khởi tạo OCPTransport, tức
            // đăng ký dispatch source; đây là thứ từng làm treo khi chạy trong constructor.
            OCPPreferences *preferences = [OCPPreferences sharedPreferences];
            OCPAppRegistry *registry = [OCPAppRegistry sharedRegistry];
            OCPLogError_(@"cấu hình: %@ | %@ | ipc=%@",
                         [preferences summary], [registry summary],
                         [[OCPTransport sharedTransport] activeBackendName]);
            [OCPRuntimeSurvey runIfEnabled];
            if (stage < OCPStartupStageDetector) {
                OCPLogError_(@"dừng ở giai đoạn %d theo cấu hình", stage);
                return;
            }

            // Giai đoạn 3 — theo dõi màn hình. Truy vấn FrontBoard/CoreAnimation.
            if (isSpringBoard) {
                [[OCPCarPlayDetector sharedDetector] start];
            }
            if (stage < OCPStartupStageCoordinator) {
                OCPLogError_(@"dừng ở giai đoạn %d theo cấu hình", stage);
                return;
            }

            // Giai đoạn 4 — điều phối khởi chạy, âm thanh, tự kiểm tra.
            if (isSpringBoard) {
                OCPRegisterRespringListener();
                [[OCPLaunchCoordinator sharedCoordinator] start];
                [[OCPAudioObserver sharedObserver] start];
                [OCPSelfTest runIfEnabled];
                [OCPCrashGuard markSessionHealthy];
            }
            if (stage < OCPStartupStageHooks) {
                OCPLogError_(@"dừng ở giai đoạn %d theo cấu hình", stage);
                return;
            }

            // Giai đoạn 5 — hook. Chỉ có trong process dashboard.
            if (isCarPlayApp) {
                OCPLogError_(@"nạp trong CarPlay dashboard — cài hook");
                OCPInstallCarPlayHooks();
            }

            OCPLogError_(@"khởi tạo xong ở giai đoạn %d", stage);
        } @catch (NSException *exception) {
            OCPLogError_(@"khởi tạo thất bại: %@ — %@", exception.name, exception.reason);
        }
    }
}

/// Ghi dấu "constructor đã chạy" ra /var/mobile/Media/OpenCarPlay/, dùng open/write
/// thuần C để không phụ thuộc bất cứ thứ gì có thể hỏng.
static void OCPWriteLoadMarker(const char *processName, int killSwitch, int stage) {
    mkdir("/var/mobile/Media/OpenCarPlay", 0755);

    char path[256];
    snprintf(path, sizeof(path), "/var/mobile/Media/OpenCarPlay/loaded-%s.txt", processName);

    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;

    char line[256];
    int length = snprintf(line, sizeof(line),
                          "constructor đã chạy\nprocess=%s\nkillswitch=%d\nstage=%d\ntime=%ld\n",
                          processName, killSwitch, stage, (long)time(NULL));
    if (length > 0) {
        ssize_t written = write(fd, line, (size_t)length);
        (void)written;
    }
    close(fd);
}

#pragma mark - Constructor

%ctor {
    // C thuần từ đầu tới cuối: không Objective-C, không cấp phát, không dispatch source.
    // os_log với OS_LOG_DEFAULT không cần tạo đối tượng nên dùng được ở đây.

    const char *processName = getprogname();
    if (processName == NULL) return;

    BOOL isSpringBoard = (strcmp(processName, "SpringBoard") == 0);
    BOOL isCarPlayApp  = (strcmp(processName, "CarPlay") == 0);
    if (!isSpringBoard && !isCarPlayApp) return;

    int killSwitch = OCPKillSwitchFileFound();
    int stage = OCPReadStartupStage();

    // Dòng log này là bằng chứng quan trọng nhất: nó cho biết constructor có chạy tới
    // đây không, và hai file điều khiển có đọc được từ trong sandbox của process không.
    //
    // Ghi bằng CẢ HAI đường: os_log là kênh chuẩn của hệ thống, còn syslog() luôn xuất
    // hiện trong idevicesyslog qua cáp USB. Bản trước chỉ dùng os_log và không thấy gì
    // trong log, mà điều đó không phân biệt được "dylib không nạp" với "log bị lọc".
    os_log(OS_LOG_DEFAULT,
           "[OpenCarPlay] ctor: process=%{public}s killswitch=%d stage=%d",
           processName, killSwitch, stage);
    syslog(LOG_ERR, "[OpenCarPlay] ctor: process=%s killswitch=%d stage=%d",
           processName, killSwitch, stage);

    // Ghi dấu ra file trong vùng AFC. Log hệ thống chỉ xuất hiện đúng lúc process khởi
    // động và trôi mất nếu không bắt kịp; file thì đọc được qua cáp bất cứ lúc nào.
    // Đây là bằng chứng dứt khoát cho câu hỏi "dylib có được nạp không".
    OCPWriteLoadMarker(processName, killSwitch, stage);

    if (killSwitch != 0) return;
    if (stage <= OCPStartupStageLoadOnly) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        OCPBootstrap(isSpringBoard, isCarPlayApp, stage);
    });
}
