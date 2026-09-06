// OpenCarPlay — xem OCPPrefsTrace.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#include "OCPPrefsTrace.h"

#include <fcntl.h>
#include <stdio.h>
#include <sys/syslog.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

void OCPPrefsTraceReset(void);

/// Hai vị trí, thử lần lượt. Vị trí đầu đọc được qua cáp USB mà không cần SSH; vị trí
/// thứ hai là nơi Settings chắc chắn ghi được nếu vị trí đầu bị sandbox chặn.
static const char *const kTracePaths[] = {
    "/var/mobile/Media/OpenCarPlay/prefs-trace.txt",
    "/var/mobile/Library/Preferences/com.opencarplay.trace.txt",
    NULL,
};

static void OCPPrefsTraceWrite(const char *line, size_t length, int truncate) {
    mkdir("/var/mobile/Media/OpenCarPlay", 0755);
    for (int i = 0; kTracePaths[i] != NULL; i++) {
        int flags = O_WRONLY | O_CREAT | (truncate ? O_TRUNC : O_APPEND);
        int fd = open(kTracePaths[i], flags, 0644);
        if (fd < 0) continue;
        ssize_t written = write(fd, line, length);
        (void)written;
        close(fd);
    }
}

void OCPPrefsTrace(const char *step, const char *detail) {
    if (step == NULL) return;

    // syslog trước: nếu bước kế tiếp làm chết process, dòng này đã ra ngoài rồi.
    syslog(LOG_ERR, "[OpenCarPlay][prefs] %s%s%s",
           step, detail ? " | " : "", detail ? detail : "");

    char line[512];
    int length = snprintf(line, sizeof(line), "%ld %s%s%s\n",
                          (long)time(NULL), step,
                          detail ? " | " : "", detail ? detail : "");
    if (length > 0) OCPPrefsTraceWrite(line, (size_t)length, 0);
}

/// Mốc sớm nhất có thể đặt được.
///
/// dyld chạy theo thứ tự: map + bind -> map_images của libobjc (đọc metadata lớp,
/// tức readClass) -> constructor. Nên dòng này xuất hiện nghĩa là bind và đăng ký lớp
/// ĐÃ XONG, và nghi vấn "readClass chết khi Settings nạp bundle" bị loại bỏ bằng quan
/// sát chứ không phải bằng lập luận.
__attribute__((constructor))
static void OCPPrefsTraceLoaded(void) {
    // Xoá dấu vết cũ ở ĐÂY, không phải trong -specifiers: bundle chỉ được nạp một lần
    // mỗi phiên Settings, nên đây đúng là điểm bắt đầu của một lần thử.
    OCPPrefsTraceReset();
    OCPPrefsTrace("bundle: dylib đã nạp, lớp đã đăng ký", NULL);
}

void OCPPrefsTraceReset(void) {
    const char header[] = "--- mở bảng cài đặt ---\n";
    OCPPrefsTraceWrite(header, sizeof(header) - 1, 1);
}
