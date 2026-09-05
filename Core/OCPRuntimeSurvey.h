// OpenCarPlay — khảo sát Objective-C runtime của process đang chạy.
//
// Đây là công cụ NGHIÊN CỨU, không phải tính năng. Nó trả lời các câu hỏi Q1–Q6
// trong RESEARCH.md §7.4 bằng dữ liệu từ chính iOS 18.6.2, thay vì suy đoán từ
// class-dump của các bản iOS cũ.
//
// Chỉ chạy khi preferences có RuntimeSurvey = YES. Chỉ đọc runtime, không sửa gì.
// Kết quả ghi vào /var/mobile/Media/OpenCarPlay/ để lấy được qua USB (AFC) mà
// không cần SSH.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_RUNTIME_SURVEY_H
#define OCP_RUNTIME_SURVEY_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCPRuntimeSurvey : NSObject

/// Chạy khảo sát nếu preferences bật. Không chặn: thực thi trên background queue.
+ (void)runIfEnabled;

/// Chạy khảo sát ngay và trả về đường dẫn file kết quả (nil nếu không ghi được).
+ (nullable NSString *)runNow;

/// Tên class đang tồn tại có tiền tố cho trước, đã sắp xếp.
+ (NSArray<NSString *> *)classNamesWithPrefix:(NSString *)prefix;

/// Toàn bộ selector của một class (cả instance và class method), đã sắp xếp.
/// Mảng rỗng nếu class không tồn tại.
+ (NSArray<NSString *> *)selectorsForClassNamed:(NSString *)className;

/// Tên ivar của một class.
+ (NSArray<NSString *> *)ivarsForClassNamed:(NSString *)className;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_RUNTIME_SURVEY_H */
