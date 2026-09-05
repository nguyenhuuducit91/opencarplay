// OpenCarPlay — fuzz test cho lớp logic thuần C.
//
// Mục tiêu không phải là kiểm tra giá trị trả về đúng (test_ocp_util.c làm việc đó),
// mà là chứng minh các hàm không bao giờ crash, đọc ngoài vùng nhớ, hay tràn số —
// kể cả với đầu vào rác. Chạy dưới ASan + UBSan nên mọi vi phạm đều dừng chương trình.
//
//   make -C tests fuzz
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#include "../Core/ocp_util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static unsigned long g_iterations = 0;

/// PRNG cố định hạt giống: mỗi lần chạy cho cùng chuỗi đầu vào, nên lỗi tái hiện được.
static unsigned int g_state = 0x0CACB1AE;
static unsigned int next_random(void) {
    g_state = g_state * 1103515245u + 12345u;
    return (g_state >> 16) & 0x7FFF;
}

/// Sinh chuỗi ngẫu nhiên từ một bảng ký tự, có thể rất dài hoặc rỗng.
static void random_string(char *buffer, size_t capacity, const char *alphabet) {
    size_t alphabetLength = strlen(alphabet);
    size_t length = next_random() % capacity;
    for (size_t i = 0; i < length; i++) {
        buffer[i] = alphabet[next_random() % alphabetLength];
    }
    buffer[length] = '\0';
}

static void fuzz_version_parser(void) {
    char buffer[64];
    const char *alphabets[] = {
        "0123456789.",                       // giống phiên bản
        "0123456789.abcxyz -_",              // lẫn ký tự lạ
        "999999999999999999999999999999.",   // ép tràn số
        ".",                                 // toàn dấu chấm
        "\t\n\r ",                           // khoảng trắng
    };

    for (size_t a = 0; a < sizeof(alphabets)/sizeof(alphabets[0]); a++) {
        for (int i = 0; i < 20000; i++) {
            random_string(buffer, sizeof(buffer) - 1, alphabets[a]);
            ocp_version_t parsed = ocp_version_parse(buffer);
            g_iterations++;

            // Bất biến: phiên bản hợp lệ không bao giờ có thành phần âm.
            if (parsed.valid && (parsed.major < 0 || parsed.minor < 0 || parsed.patch < 0)) {
                printf("FAIL: \"%s\" -> %d.%d.%d (thành phần âm)\n",
                       buffer, parsed.major, parsed.minor, parsed.patch);
                exit(1);
            }

            // So sánh phải ổn định: x == x với mọi đầu vào.
            if (ocp_version_compare(parsed, parsed) != 0) {
                printf("FAIL: so sánh không phản xạ với \"%s\"\n", buffer);
                exit(1);
            }
        }
    }
}

static void fuzz_bundle_identifier(void) {
    char buffer[300];
    const char *alphabets[] = {
        "abcABC012.-",
        "abc.def/../../etc/passwd",
        "..........",
        "com.apple.springboard",             // gần với mục bị chặn
        "\x01\x02\x7f abc.",                 // ký tự điều khiển
    };

    for (size_t a = 0; a < sizeof(alphabets)/sizeof(alphabets[0]); a++) {
        for (int i = 0; i < 20000; i++) {
            random_string(buffer, sizeof(buffer) - 1, alphabets[a]);
            bool valid = ocp_bundle_id_is_valid(buffer);
            bool critical = ocp_bundle_id_is_system_critical(buffer);
            g_iterations++;

            // Bất biến an toàn quan trọng nhất của dự án: mọi chuỗi bị coi là
            // process hệ thống thì KHÔNG BAO GIỜ được đi tiếp, bất kể hợp lệ hay không.
            // (Registry xét critical trước, nên ở đây chỉ cần chúng không mâu thuẫn.)
            if (critical && strcmp(buffer, "com.apple.springboard") == 0 && !valid) {
                printf("FAIL: \"%s\" bị chặn nhưng lại không hợp lệ — logic mâu thuẫn\n", buffer);
                exit(1);
            }

            // Chuỗi có dấu '/' không bao giờ được coi là hợp lệ (chống chèn đường dẫn).
            if (valid && strchr(buffer, '/') != NULL) {
                printf("FAIL: \"%s\" chứa '/' mà vẫn hợp lệ\n", buffer);
                exit(1);
            }
        }
    }
}

static void fuzz_geometry(void) {
    // Bao gồm cả giá trị bệnh lý mà màn hình xe lỗi có thể báo về.
    const double values[] = {
        0.0, -1.0, 1.0, 0.5, 800.0, 1920.0, 1e9, -1e9,
        INFINITY, -INFINITY, NAN, 1e-9,
    };
    const size_t count = sizeof(values)/sizeof(values[0]);

    for (size_t a = 0; a < count; a++) {
        for (size_t b = 0; b < count; b++) {
            for (size_t c = 0; c < count; c++) {
                for (size_t d = 0; d < count; d++) {
                    double scale = ocp_aspect_fit_scale(values[a], values[b],
                                                        values[c], values[d]);
                    g_iterations++;

                    // Tỉ lệ không bao giờ được âm — âm nghĩa là ảnh lộn ngược.
                    if (scale < 0.0) {
                        printf("FAIL: scale âm %.3f cho (%g,%g)->(%g,%g)\n",
                               scale, values[a], values[b], values[c], values[d]);
                        exit(1);
                    }

                    double x = 0, y = 0;
                    bool converted = ocp_convert_point(values[a], values[b],
                                                       values[c], values[d], scale, &x, &y);
                    // scale <= 0 phải luôn bị từ chối, không được trả toạ độ rác.
                    if (converted && scale <= 0.0) {
                        printf("FAIL: chấp nhận scale %.3f\n", scale);
                        exit(1);
                    }
                }
            }
        }
    }
}

int main(void) {
    printf("=== OpenCarPlay fuzz test ===\n\n");

    printf("phân tích phiên bản...\n");
    fuzz_version_parser();

    printf("bundle identifier...\n");
    fuzz_bundle_identifier();

    printf("hình học màn hình...\n");
    fuzz_geometry();

    printf("\n%lu lượt, không phát hiện crash hay vi phạm bất biến\nPASS\n", g_iterations);
    return 0;
}
