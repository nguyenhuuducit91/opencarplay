// OpenCarPlay — bộ tự kiểm tra chạy trên thiết bị.
//
// Phần lớn Phase 14 là thao tác vật lý (cắm/rút cáp, chạm màn hình xe) mà phần mềm
// không thay thế được. Nhưng ba thứ thì đo được bằng máy và chính chúng là nơi lỗi
// hay ẩn: rò rỉ tài nguyên khi tạo/huỷ lặp lại, trạng thái không sạch sau khi dọn,
// và suy giảm hiệu năng qua nhiều vòng.
//
// Chạy khi preferences có SelfTest = YES. Kết quả ghi vào
// /var/mobile/Media/OpenCarPlay/ để lấy qua USB bằng scripts/fetch_survey.sh.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_SELF_TEST_H
#define OCP_SELF_TEST_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCPSelfTest : NSObject

/// Chạy nếu preferences bật. Không chặn; thực thi sau khi hệ thống ổn định.
+ (void)runIfEnabled;

/// Chạy ngay và trả về đường dẫn báo cáo (nil nếu không ghi được).
+ (nullable NSString *)runNow;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_SELF_TEST_H */
