// OpenCarPlay — xem ocp_util.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#include "ocp_util.h"

#include <string.h>
#include <ctype.h>

ocp_version_t ocp_version_parse(const char *string) {
    ocp_version_t v = {0, 0, 0, false};
    if (string == NULL || *string == '\0') {
        return v;
    }

    int components[3] = {0, 0, 0};
    int index = 0;
    bool sawDigit = false;
    const char *p = string;

    while (*p != '\0') {
        if (isdigit((unsigned char)*p)) {
            if (index > 2) {
                // Nhiều hơn 3 thành phần: phần thừa bị bỏ qua, không coi là lỗi.
                break;
            }
            int value = 0;
            while (isdigit((unsigned char)*p)) {
                int digit = *p - '0';
                if (value > (100000 - digit) / 10) {   // chặn tràn số
                    return (ocp_version_t){0, 0, 0, false};
                }
                value = value * 10 + digit;
                p++;
            }
            components[index++] = value;
            sawDigit = true;
        } else if (*p == '.') {
            if (!sawDigit) {
                return v;   // ".6" hoặc chuỗi bắt đầu bằng dấu chấm
            }
            p++;
            if (!isdigit((unsigned char)*p)) {
                return (ocp_version_t){0, 0, 0, false};   // "18." hoặc "18..2"
            }
        } else {
            return (ocp_version_t){0, 0, 0, false};       // ký tự lạ
        }
    }

    if (!sawDigit) {
        return v;
    }

    v.major = components[0];
    v.minor = components[1];
    v.patch = components[2];
    v.valid = true;
    return v;
}

int ocp_version_compare(ocp_version_t a, ocp_version_t b) {
    if (a.major != b.major) return (a.major < b.major) ? -1 : 1;
    if (a.minor != b.minor) return (a.minor < b.minor) ? -1 : 1;
    if (a.patch != b.patch) return (a.patch < b.patch) ? -1 : 1;
    return 0;
}

bool ocp_version_in_range(ocp_version_t v, ocp_version_t min_inclusive, ocp_version_t max_exclusive) {
    if (!v.valid) return false;
    return ocp_version_compare(v, min_inclusive) >= 0 &&
           ocp_version_compare(v, max_exclusive) < 0;
}

bool ocp_bundle_id_is_valid(const char *identifier) {
    if (identifier == NULL) return false;

    size_t length = strlen(identifier);
    if (length == 0 || length > OCP_BUNDLE_ID_MAX_LENGTH) return false;

    int segments = 0;
    size_t segmentLength = 0;

    for (size_t i = 0; i < length; i++) {
        char c = identifier[i];
        if (c == '.') {
            if (segmentLength == 0) return false;   // ".." hoặc bắt đầu/kết thúc bằng '.'
            segments++;
            segmentLength = 0;
            continue;
        }
        if (!(isalnum((unsigned char)c) || c == '-')) return false;
        segmentLength++;
    }

    if (segmentLength == 0) return false;   // kết thúc bằng '.'
    segments++;

    return segments >= 2;
}

bool ocp_bundle_id_is_system_critical(const char *identifier) {
    if (identifier == NULL) return true;   // không biết thì coi là nguy hiểm

    // Chỉ những process mà việc host chắc chắn phá hệ thống:
    //  - springboard: chính process đang host, sẽ đệ quy
    //  - backboardd/mediaserverd: hạ tầng hiển thị và âm thanh
    //  - các process dựng chính giao diện CarPlay: chiếm nó thì mất dashboard
    static const char *const critical[] = {
        "com.apple.springboard",
        "com.apple.backboardd",
        "com.apple.mediaserverd",
        "com.apple.CarPlayApp",
        "com.apple.CarPlayTemplateUIHost",
        "com.apple.CarPlaySettings",
        "com.apple.InCallService",
        "com.apple.MusicUIService",
        "com.opencarplay.tweak",
        NULL,
    };

    for (int i = 0; critical[i] != NULL; i++) {
        if (strcmp(identifier, critical[i]) == 0) return true;
    }
    return false;
}

double ocp_aspect_fit_scale(double src_w, double src_h, double dst_w, double dst_h) {
    if (src_w <= 0.0 || src_h <= 0.0 || dst_w <= 0.0 || dst_h <= 0.0) return 0.0;
    double sx = dst_w / src_w;
    double sy = dst_h / src_h;
    return (sx < sy) ? sx : sy;
}

bool ocp_convert_point(double car_x, double car_y,
                       double offset_x, double offset_y, double scale,
                       double *out_app_x, double *out_app_y) {
    if (scale <= 0.0 || out_app_x == NULL || out_app_y == NULL) return false;
    *out_app_x = (car_x - offset_x) / scale;
    *out_app_y = (car_y - offset_y) / scale;
    return true;
}
