// OpenCarPlay — entry point.
//
// GIAI ĐOẠN KHỞI TẠO
//
// Quá trình khởi tạo chia thành các GIAI ĐOẠN đánh số, và MẶC ĐỊNH LÀ 0 — nạp dylib,
// ghi một dòng log, không chạm gì khác. Người dùng nâng dần giai đoạn khi đã sẵn sàng.
//
// VÌ SAO MẶC ĐỊNH LÀ 0
//
// Vì chưa ai chứng minh được giai đoạn 1–5 chạy an toàn trên iOS 18.6. Cơ chế giai đoạn
// sinh ra chính vì khởi tạo đầy đủ từng làm treo SpringBoard hai lần, và nguyên nhân
// CHƯA BAO GIỜ được tìm ra — nó mới chỉ được né. Bản 0.31.0 đổi mặc định thành "chạy
// hết" với lý do "công cụ gỡ lỗi không nên là hành vi mặc định". Lý lẽ đó đúng về
// nguyên tắc và sai về thực tế: nó làm sống lại đúng cái treo cũ và người dùng mất máy.
//
// Giai đoạn đọc theo thứ tự ưu tiên, tất cả bằng open/read thuần — không Objective-C,
// không cfprefsd, không thứ gì có thể chặn trên đường khởi động:
//
//   1. /var/mobile/Media/OpenCarPlay/STAGE            — ghi được qua cáp USB (cứu hộ)
//   2. /var/mobile/Library/Preferences/com.opencarplay.stage — bảng cài đặt ghi
//   3. không có file nào -> giai đoạn 0
//
// Điều khiển từ máy tính khi không vào được giao diện:
//     echo 0 > /tmp/STAGE && afcclient put /tmp/STAGE /OpenCarPlay/STAGE
//     afcclient put /tmp/x /OpenCarPlay/DISABLED     # tắt hẳn
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import <Foundation/Foundation.h>

#import <UIKit/UIKit.h>

#import <fcntl.h>
#import <notify.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
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

/// Bảng cài đặt ghi giai đoạn vào đây. Văn bản thuần, một số nguyên — cố ý, để
/// constructor đọc được mà không cần parse plist và không cần hỏi cfprefsd.
static const char *const kStagePreferencePath =
    "/var/mobile/Library/Preferences/com.opencarplay.stage";

/// Dấu "đang khởi tạo". Tạo trước khi khởi tạo, xoá khi phiên chạy đã ổn định
/// (OCPCrashGuard markSessionHealthy). Còn sót lại ở lần nạp sau nghĩa là lần trước
/// không bao giờ tới đích — gần như chắc chắn là treo.
///
/// Đây là lưới an toàn mà bộ đếm crash không thay được: treo thì SpringBoard không
/// chết, không có crash report, không có lần nạp thứ hai để mà đếm.
static const char *const kBootstrapMarkerPath =
    "/var/mobile/Library/Preferences/com.opencarplay.bootstrapping";

/// Đọc một số nguyên từ file văn bản thuần. -1 nếu file không có hoặc không chứa số.
/// open/read thuần: hàm này chạy trong constructor.
static int OCPReadIntegerFile(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;

    char buffer[16] = {0};
    ssize_t bytes = read(fd, buffer, sizeof(buffer) - 1);
    close(fd);
    if (bytes <= 0) return -1;

    // atoi() trả 0 cho mọi chuỗi không phải số. Với một giá trị mà 0 nghĩa là "tắt",
    // nhầm lẫn đó âm thầm vô hiệu hoá tweak, nên phải phân biệt tường minh.
    for (ssize_t i = 0; i < bytes; i++) {
        if (buffer[i] >= '0' && buffer[i] <= '9') return atoi(buffer);
    }
    return -1;
}

static int OCPClampStage(int stage) {
    if (stage < OCPStartupStageLoadOnly) return OCPStartupStageLoadOnly;
    if (stage > OCPStartupStageHooks) return OCPStartupStageHooks;
    return stage;
}

/// Giai đoạn yêu cầu, chưa xét tới lưới an toàn.
static int OCPRequestedStartupStage(void) {
    int stage = OCPReadIntegerFile("/var/mobile/Media/OpenCarPlay/STAGE");
    if (stage >= 0) return OCPClampStage(stage);

    stage = OCPReadIntegerFile(kStagePreferencePath);
    if (stage >= 0) return OCPClampStage(stage);

    return OCPStartupStageLoadOnly;
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

/// Ghi dấu "constructor đã chạy", bằng open/write thuần C.
///
/// Ghi ra NHIỀU vị trí, vì mỗi vị trí có một điểm mù:
///
///   /var/mobile/Media/...   đọc được qua cáp USB mà không cần SSH — nhưng đây là vùng
///                           AFC, và sandbox của SpringBoard có thể từ chối ghi vào đó.
///                           Bản 0.30-0.39 chỉ ghi vào đây, nên "không có dấu" vừa có
///                           thể nghĩa là dylib không nạp, vừa có thể là nạp rồi mà
///                           không ghi được — hai kết luận trái ngược, không phân biệt
///                           nổi. Đó là lý do phải sửa chỗ này.
///   Library/Preferences/... SpringBoard chạy dưới quyền mobile và thư mục này thuộc
///                           mobile; đọc bằng Filza hoặc SSH.
///   /var/tmp/...            đường lùi cuối, gần như luôn ghi được.
///
/// syslog() trong constructor mới là bằng chứng đáng tin nhất vì nó không cần quyền ghi
/// file nào; mấy file này chỉ để đọc lại sau, khi không bắt kịp lúc log chạy qua.
static void OCPWriteLoadMarker(const char *processName, int killSwitch, int stage) {
    char line[256];
    int length = snprintf(line, sizeof(line),
                          "constructor da chay\nprocess=%s\nkillswitch=%d\nstage=%d\ntime=%ld\n",
                          processName, killSwitch, stage, (long)time(NULL));
    if (length <= 0) return;

    mkdir("/var/mobile/Media/OpenCarPlay", 0755);

    static const char *const prefixes[] = {
        "/var/mobile/Media/OpenCarPlay/loaded-",
        "/var/mobile/Library/Preferences/com.opencarplay.loaded-",
        "/var/tmp/com.opencarplay.loaded-",
        NULL,
    };

    for (int i = 0; prefixes[i] != NULL; i++) {
        char path[256];
        if (snprintf(path, sizeof(path), "%s%s.txt", prefixes[i], processName)
                >= (int)sizeof(path)) {
            continue;
        }
        int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) continue;
        ssize_t written = write(fd, line, (size_t)length);
        (void)written;
        close(fd);
    }
}

#pragma mark - Constructor

%ctor {
    // C thuần từ đầu tới cuối: không Objective-C, không cấp phát, không dispatch source.
    // os_log với OS_LOG_DEFAULT không cần tạo đối tượng nên dùng được ở đây.

    const char *processName = getprogname();
    const char *mainImage = _dyld_get_image_name(0);

    // GHI NGAY, TRƯỚC MỌI KIỂM TRA.
    //
    // Bản 0.30-0.45 đặt dòng log này SAU phép so tên process, nên khi tên không khớp thì
    // constructor lặng lẽ trả về. Hậu quả: "không có dòng log nào" bị đọc thành "dylib
    // không được nạp", trong khi nó chỉ có nghĩa là "getprogname() không bằng đúng
    // SpringBoard hoặc CarPlay". Hai kết luận hoàn toàn khác nhau, và suốt nhiều bản tôi
    // đã dùng nhầm cái sau làm bằng chứng cho cái trước.
    //
    // Ghi cả getprogname() lẫn đường dẫn image chính: nếu tên process không như dự đoán,
    // dòng này cho biết ngay tên thật là gì.
    syslog(LOG_ERR, "[OpenCarPlay] ctor: nap vao progname=%s main=%s pid=%d",
           processName ? processName : "(null)",
           mainImage ? mainImage : "(null)",
           (int)getpid());

    if (processName == NULL) return;

    BOOL isSpringBoard = (strcmp(processName, "SpringBoard") == 0);
    BOOL isCarPlayApp  = (strcmp(processName, "CarPlay") == 0);
    if (!isSpringBoard && !isCarPlayApp) return;

    int killSwitch = OCPKillSwitchFileFound();
    int stage = OCPRequestedStartupStage();

    // Lần nạp trước bắt đầu khởi tạo mà không bao giờ báo ổn định. Hạ về chỉ-nạp để
    // máy lên được; người dùng nâng lại trong Cài đặt sau khi đã biết vì sao.
    int previousAttemptStalled = (stage > OCPStartupStageLoadOnly && isSpringBoard &&
                                  access(kBootstrapMarkerPath, F_OK) == 0);
    if (previousAttemptStalled) {
        stage = OCPStartupStageLoadOnly;
    }

    // Dòng log này là bằng chứng quan trọng nhất: nó cho biết constructor có chạy tới
    // đây không, và hai file điều khiển có đọc được từ trong sandbox của process không.
    //
    // Ghi bằng CẢ HAI đường: os_log là kênh chuẩn của hệ thống, còn syslog() luôn xuất
    // hiện trong idevicesyslog qua cáp USB. Bản trước chỉ dùng os_log và không thấy gì
    // trong log, mà điều đó không phân biệt được "dylib không nạp" với "log bị lọc".
    os_log(OS_LOG_DEFAULT,
           "[OpenCarPlay] ctor: process=%{public}s killswitch=%d stage=%d stalled=%d",
           processName, killSwitch, stage, previousAttemptStalled);
    syslog(LOG_ERR, "[OpenCarPlay] ctor: process=%s killswitch=%d stage=%d stalled=%d",
           processName, killSwitch, stage, previousAttemptStalled);

    // Ghi dấu ra file trong vùng AFC. Log hệ thống chỉ xuất hiện đúng lúc process khởi
    // động và trôi mất nếu không bắt kịp; file thì đọc được qua cáp bất cứ lúc nào.
    // Đây là bằng chứng dứt khoát cho câu hỏi "dylib có được nạp không".
    OCPWriteLoadMarker(processName, killSwitch, stage);

    if (killSwitch != 0) return;
    if (stage <= OCPStartupStageLoadOnly) return;

    // Đặt dấu TRƯỚC khi khởi tạo. Nếu phần dưới treo, lần nạp sau thấy dấu này và
    // hạ về chỉ-nạp — máy lên được mà không cần cáp USB.
    if (isSpringBoard) {
        int marker = open(kBootstrapMarkerPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (marker >= 0) {
            char line[64];
            int length = snprintf(line, sizeof(line), "stage=%d time=%ld\n",
                                  stage, (long)time(NULL));
            if (length > 0) { ssize_t w = write(marker, line, (size_t)length); (void)w; }
            close(marker);
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        OCPBootstrap(isSpringBoard, isCarPlayApp, stage);
        // Về được tới đây nghĩa là khởi tạo không treo, ở BẤT KỲ giai đoạn nào.
        // Bản trước chỉ đánh dấu ở giai đoạn 4, nên giai đoạn 1-3 không bao giờ xoá
        // được dấu và mọi lần khởi động kế tiếp đều bị lưới an toàn hạ về 0.
        if (isSpringBoard) [OCPCrashGuard markSessionHealthy];
    });
}
