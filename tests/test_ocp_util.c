// OpenCarPlay — unit test cho lớp logic thuần C.
// Chạy trên máy build, không cần thiết bị:  make -C tests test

#include "../Core/ocp_util.h"

#include <stdio.h>
#include <string.h>
#include <math.h>

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond, fmt, ...) do { \
    g_checks++; \
    if (!(cond)) { \
        g_failures++; \
        printf("  FAIL  %s:%d  " fmt "\n", __FILE__, __LINE__, ##__VA_ARGS__); \
    } \
} while (0)

static void test_version_parse_valid(void) {
    printf("version: chuỗi hợp lệ\n");
    struct { const char *in; int ma, mi, pa; } cases[] = {
        {"18.6.2", 18, 6, 2},
        {"18.6",   18, 6, 0},
        {"18",     18, 0, 0},
        {"0.0.0",   0, 0, 0},
        {"17.10.1",17,10, 1},
        {"18.6.2.1", 18, 6, 2},   // thành phần thứ 4 bị bỏ qua
    };
    for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); i++) {
        ocp_version_t v = ocp_version_parse(cases[i].in);
        CHECK(v.valid, "\"%s\" phải hợp lệ", cases[i].in);
        CHECK(v.major == cases[i].ma && v.minor == cases[i].mi && v.patch == cases[i].pa,
              "\"%s\" -> %d.%d.%d, mong đợi %d.%d.%d",
              cases[i].in, v.major, v.minor, v.patch, cases[i].ma, cases[i].mi, cases[i].pa);
    }
}

static void test_version_parse_invalid(void) {
    printf("version: chuỗi không hợp lệ\n");
    const char *bad[] = {NULL, "", "abc", "18.x", "18.", ".6", "18..2", "18 6", "-18", "18.6.2b",
                         "999999999999"};
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); i++) {
        ocp_version_t v = ocp_version_parse(bad[i]);
        CHECK(!v.valid, "\"%s\" phải bị từ chối", bad[i] ? bad[i] : "(null)");
    }
}

static void test_version_compare(void) {
    printf("version: so sánh\n");
    ocp_version_t a = ocp_version_parse("18.6.2");
    ocp_version_t b = ocp_version_parse("18.6.1");
    ocp_version_t c = ocp_version_parse("18.6.2");
    ocp_version_t d = ocp_version_parse("19.0");
    ocp_version_t e = ocp_version_parse("18.10.0");

    CHECK(ocp_version_compare(a, b) == 1,  "18.6.2 > 18.6.1");
    CHECK(ocp_version_compare(b, a) == -1, "18.6.1 < 18.6.2");
    CHECK(ocp_version_compare(a, c) == 0,  "18.6.2 == 18.6.2");
    CHECK(ocp_version_compare(a, d) == -1, "18.6.2 < 19.0");
    CHECK(ocp_version_compare(e, a) == 1,  "18.10.0 > 18.6.2 (so sánh số, không phải chuỗi)");
}

static void test_version_range(void) {
    printf("version: phạm vi hỗ trợ [18.0, 19.0)\n");
    ocp_version_t min = ocp_version_parse("18.0");
    ocp_version_t max = ocp_version_parse("19.0");

    struct { const char *v; bool expected; } cases[] = {
        {"18.6.2", true},
        {"18.0",   true},
        {"18.7.1", true},
        {"19.0",   false},   // biên trên loại trừ
        {"17.9.9", false},
        {"26.1",   false},
        {"abc",    false},   // chuỗi rác không bao giờ được hỗ trợ
    };
    for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); i++) {
        bool got = ocp_version_in_range(ocp_version_parse(cases[i].v), min, max);
        CHECK(got == cases[i].expected, "\"%s\" in_range -> %d, mong đợi %d",
              cases[i].v, got, cases[i].expected);
    }
}

static void test_bundle_id(void) {
    printf("bundle id: hợp lệ / không hợp lệ\n");
    const char *good[] = {
        "com.google.Maps", "com.apple.springboard", "com.vietmap.VietMapLive",
        "com.zhiliaoapp.musically", "a.b", "com.example.app-name", "com.example.App2",
    };
    for (size_t i = 0; i < sizeof(good)/sizeof(good[0]); i++) {
        CHECK(ocp_bundle_id_is_valid(good[i]), "\"%s\" phải hợp lệ", good[i]);
    }

    const char *bad[] = {
        NULL, "", "com", "com.", ".com", "com..app", "com.exam ple.app",
        "com/example/app", "../../etc/passwd", "com.example.app!", "com.example.app\n",
    };
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); i++) {
        CHECK(!ocp_bundle_id_is_valid(bad[i]), "\"%s\" phải bị từ chối",
              bad[i] ? bad[i] : "(null)");
    }

    // Quá dài
    char longID[OCP_BUNDLE_ID_MAX_LENGTH + 32];
    memset(longID, 'a', sizeof(longID) - 1);
    longID[sizeof(longID) - 1] = '\0';
    longID[3] = '.';
    CHECK(!ocp_bundle_id_is_valid(longID), "bundle id quá dài phải bị từ chối");
}

static void test_system_critical(void) {
    printf("bundle id: danh sách chặn cứng\n");
    const char *critical[] = {
        "com.apple.springboard", "com.apple.CarPlayApp", "com.apple.CarPlayTemplateUIHost",
        "com.apple.backboardd", "com.apple.mediaserverd", "com.opencarplay.tweak",
    };
    for (size_t i = 0; i < sizeof(critical)/sizeof(critical[0]); i++) {
        CHECK(ocp_bundle_id_is_system_critical(critical[i]),
              "\"%s\" phải bị chặn cứng", critical[i]);
    }

    const char *allowed[] = {
        "com.google.Maps", "com.vietmap.VietMapLive", "com.google.ios.youtube",
        "com.apple.Maps",          // app Apple thường thì không nằm trong danh sách chặn
        "com.apple.springboard.x", // gần giống nhưng khác -> không chặn
    };
    for (size_t i = 0; i < sizeof(allowed)/sizeof(allowed[0]); i++) {
        CHECK(!ocp_bundle_id_is_system_critical(allowed[i]),
              "\"%s\" không được nằm trong danh sách chặn", allowed[i]);
    }

    CHECK(ocp_bundle_id_is_system_critical(NULL), "NULL phải bị coi là nguy hiểm");
}

static bool approx(double a, double b) { return fabs(a - b) < 1e-9; }

static void test_aspect_fit(void) {
    printf("display: tỉ lệ co\n");
    // Màn hình iPhone 11 landscape (896x414 pt) đưa vào màn hình xe giả định 800x480
    CHECK(approx(ocp_aspect_fit_scale(896, 414, 800, 480), 800.0 / 896.0),
          "chiều rộng là ràng buộc");
    // Khung xe hẹp theo chiều cao
    CHECK(approx(ocp_aspect_fit_scale(400, 800, 800, 400), 400.0 / 800.0),
          "chiều cao là ràng buộc");
    CHECK(approx(ocp_aspect_fit_scale(100, 100, 100, 100), 1.0), "cùng kích thước -> 1.0");

    // Tham số không hợp lệ
    CHECK(approx(ocp_aspect_fit_scale(0, 100, 100, 100), 0.0), "src_w = 0");
    CHECK(approx(ocp_aspect_fit_scale(100, 100, -1, 100), 0.0), "dst_w âm");
}

static void test_convert_point(void) {
    printf("touch: quy đổi toạ độ\n");
    double x = 0, y = 0;

    // Dock rộng 40pt bên trái, app hiển thị ở tỉ lệ 0.5
    CHECK(ocp_convert_point(140, 100, 40, 0, 0.5, &x, &y), "quy đổi phải thành công");
    CHECK(approx(x, 200.0) && approx(y, 200.0), "(140,100) -> (%.1f,%.1f), mong đợi (200,200)", x, y);

    // Điểm ngay tại gốc khung app
    CHECK(ocp_convert_point(40, 0, 40, 0, 0.5, &x, &y), "gốc khung");
    CHECK(approx(x, 0.0) && approx(y, 0.0), "gốc -> (0,0), nhận (%.1f,%.1f)", x, y);

    // scale không hợp lệ
    CHECK(!ocp_convert_point(100, 100, 0, 0, 0.0, &x, &y), "scale = 0 phải thất bại");
    CHECK(!ocp_convert_point(100, 100, 0, 0, -1.0, &x, &y), "scale âm phải thất bại");
    CHECK(!ocp_convert_point(100, 100, 0, 0, 1.0, NULL, &y), "con trỏ NULL phải thất bại");
}

int main(void) {
    printf("=== OpenCarPlay unit tests ===\n\n");
    test_version_parse_valid();
    test_version_parse_invalid();
    test_version_compare();
    test_version_range();
    test_bundle_id();
    test_system_critical();
    test_aspect_fit();
    test_convert_point();

    printf("\n%d kiểm tra, %d lỗi\n", g_checks, g_failures);
    if (g_failures == 0) {
        printf("PASS\n");
        return 0;
    }
    printf("FAIL\n");
    return 1;
}
