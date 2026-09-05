// OpenCarPlay — tự vô hiệu hoá khi phát hiện vòng lặp crash.
//
// Từ Phase 9, tweak chạm vào bộ máy scene của SpringBoard. Sai ở đó không phải là
// "tính năng không chạy" mà là SpringBoard chết lặp, tức máy không dùng được nữa.
//
// Cơ chế: mỗi lần nạp vào SpringBoard ghi lại một dấu thời gian. Nếu số lần nạp
// trong một khoảng ngắn vượt ngưỡng, tweak tự tạo file kill switch và ngừng hoạt
// động — máy trở lại bình thường sau lần respring kế tiếp mà không cần người dùng
// làm gì.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_CRASH_GUARD_H
#define OCP_CRASH_GUARD_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCPCrashGuard : NSObject

/// Ghi nhận một lần nạp. Trả NO nếu phát hiện vòng lặp crash — khi đó bên gọi
/// PHẢI dừng ngay, không khởi tạo gì thêm.
+ (BOOL)recordLoadAndCheckHealth;

/// Đánh dấu phiên hiện tại là ổn định (gọi sau khi đã chạy được một lúc).
/// Xoá lịch sử để những lần crash cũ không cộng dồn sang phiên mới.
+ (void)markSessionHealthy;

/// Số lần nạp gần đây trong cửa sổ theo dõi.
+ (NSUInteger)recentLoadCount;

/// Đánh dấu bắt đầu một thao tác rủi ro và cho biết có được phép chạy không.
///
/// Vì sao cần, ngoài bộ đếm crash ở trên: một tweak làm SpringBoard ĐƠ (chứ không
/// crash) sẽ không tạo crash report và cũng không làm SpringBoard tự khởi động lại —
/// người dùng buộc phải nhấn nút nguồn. Bộ đếm crash không thấy gì cả.
///
/// Cách hoạt động: ghi một dấu trước khi chạy phần rủi ro, xoá dấu sau khi qua được.
/// Nếu lần nạp sau vẫn thấy dấu cũ, nghĩa là lần trước đã chết ở đúng chỗ đó — khi
/// đó hàm trả NO và tự tắt khoá preferences tương ứng, để máy không treo lần thứ hai.
///
/// `preferenceKey` là khoá sẽ bị tắt (nil nếu không có khoá nào tương ứng).
+ (BOOL)beginRiskyOperation:(NSString *)name disablingPreference:(nullable NSString *)preferenceKey;

/// Xoá dấu sau khi thao tác đã qua an toàn.
+ (void)endRiskyOperation:(NSString *)name;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_CRASH_GUARD_H */
