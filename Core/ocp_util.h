// OpenCarPlay — logic thuần C, không phụ thuộc Foundation.
//
// Mọi thứ ở đây phải kiểm chứng được bằng unit test trên máy build (tests/).
// Đó là lý do nó tách khỏi lớp Objective-C.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_UTIL_H
#define OCP_UTIL_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int major;
    int minor;
    int patch;
    bool valid;
} ocp_version_t;

/// Phân tích "18.6.2" / "18.6" / "18". Chuỗi rác trả về valid=false.
ocp_version_t ocp_version_parse(const char *string);

/// -1 nếu a < b, 0 nếu bằng, 1 nếu a > b. Thành phần thiếu coi như 0.
int ocp_version_compare(ocp_version_t a, ocp_version_t b);

/// Nằm trong [min, max) — max là biên trên loại trừ.
bool ocp_version_in_range(ocp_version_t v, ocp_version_t min_inclusive, ocp_version_t max_exclusive);

/// Bundle identifier hợp lệ theo quy ước Apple: các đoạn phân tách bằng '.',
/// mỗi đoạn khác rỗng, chỉ gồm [A-Za-z0-9-], phải có ít nhất 2 đoạn.
/// Từ chối chuỗi rỗng, quá dài, có khoảng trắng, hoặc ký tự đường dẫn.
bool ocp_bundle_id_is_valid(const char *identifier);

#define OCP_BUNDLE_ID_MAX_LENGTH 255

/// Tỉ lệ co để đưa nội dung kích thước `src` vừa vào khung `dst`, giữ nguyên tỉ lệ khung hình.
/// Trả về 0 nếu tham số không hợp lệ (<= 0).
double ocp_aspect_fit_scale(double src_w, double src_h, double dst_w, double dst_h);

/// Quy đổi điểm chạm trên màn hình CarPlay về hệ toạ độ của ứng dụng.
/// `scale` là hệ số đã dùng để hiển thị app, `offset_*` là vị trí khung app trong cửa sổ.
/// Trả về false (và không ghi kết quả) nếu scale <= 0.
bool ocp_convert_point(double car_x, double car_y,
                       double offset_x, double offset_y, double scale,
                       double *out_app_x, double *out_app_y);

#ifdef __cplusplus
}
#endif

#endif /* OCP_UTIL_H */
