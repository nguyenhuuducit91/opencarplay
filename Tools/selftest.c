// OpenCarPlay — thử nạp dylib và IN RA LÝ DO nếu thất bại.
//
//     opencarplay-selftest [đường dẫn dylib]
//
// VÌ SAO CẦN
//
// Injector của ElleKit gọi dlopen; khi dlopen trả về NULL nó bỏ qua tweak trong im lặng.
// Không lỗi, không log, không dấu hiệu nào. Đã chứng minh được là dylib không bao giờ
// được nạp — constructor ghi log ngay dòng đầu, trước mọi kiểm tra, và không có dòng
// nào xuất hiện — nhưng KHÔNG biết vì sao.
//
// Chương trình này gọi đúng lời gọi đó rồi in dlerror(). Chạy dưới quyền root trong
// postinst, nên nó trả lời được câu hỏi mà từ xa không cách nào trả lời.
//
// Bản thân nó cũng là một phép thử: nếu chương trình này chạy được thì binary arm64e do
// toolchain Linux dựng, ký bằng ldid, ĐƯỢC hệ thống chấp nhận — loại bỏ nghi vấn về
// trust cache và chữ ký.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#include <dlfcn.h>
#include <errno.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *kDefaultPath = "/var/jb/usr/lib/TweakInject/OpenCarPlay.dylib";

int main(int argc, char *argv[]) {
    const char *path = (argc > 1) ? argv[1] : kDefaultPath;

    printf("opencarplay-selftest\n");
    printf("  progname   : %s\n", getprogname() ? getprogname() : "(null)");
    printf("  uid/euid   : %d/%d\n", (int)getuid(), (int)geteuid());
    printf("  đường dẫn  : %s\n", path);

    if (access(path, R_OK) != 0) {
        printf("  KHÔNG ĐỌC ĐƯỢC file (access): %s\n", strerror(errno));
        return 1;
    }

    // RTLD_NOW: bắt lỗi bind ngay, thay vì để lộ ra lúc gọi hàm đầu tiên.
    dlerror();
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        const char *error = dlerror();
        printf("  dlopen THẤT BẠI\n");
        printf("  dlerror    : %s\n", error ? error : "(không có mô tả)");
        return 2;
    }

    printf("  dlopen THÀNH CÔNG\n");

    // Ảnh vừa nạp nằm ở cuối danh sách image của process.
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name != NULL && strstr(name, "OpenCarPlay") != NULL) {
            printf("  đã nạp     : %s\n", name);
        }
    }

    dlclose(handle);
    return 0;
}
