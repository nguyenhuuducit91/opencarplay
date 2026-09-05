// OpenCarPlay — đưa ứng dụng được phép vào danh sách của CarPlay dashboard.
//
// TRẠNG THÁI: THỬ NGHIỆM. Cách làm ở đây dựa trên kiến trúc phân tích trong
// RESEARCH.md §2.5 và §3.4, nhưng các câu hỏi Q1–Q4 (§7.4) CHƯA có lời giải từ
// thiết bị thật. Vì vậy:
//
//   • toàn bộ nằm sau khoá ExperimentalDiscovery (mặc định NO)
//   • mỗi bước đều probe trước, thiếu thì dừng và ghi log, không đoán tiếp
//   • giữ %orig thay vì thay thế app library như carplay-cast, để CarPlay nguyên bản
//     vẫn hoạt động nếu adapter thất bại
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_DISCOVERY_ADAPTER_H
#define OCP_DISCOVERY_ADAPTER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Tag gắn vào app đã được đưa lên dashboard, để nhận ra chúng khi người dùng chạm.
FOUNDATION_EXPORT NSString *const OCPApplicationTag;

typedef NS_ENUM(NSInteger, OCPDiscoveryStrategy) {
    /// Gắn CRCarPlayAppDeclaration giả vào thông tin ứng dụng (cách của iOS 14).
    OCPDiscoveryStrategyDeclaration = 0,
    /// Can thiệp tầng chính sách CRCarPlayAppPolicy (iOS 16+). Chưa triển khai —
    /// cần dữ liệu từ OCPRuntimeSurvey trước, xem RESEARCH.md Q1.
    OCPDiscoveryStrategyPolicy,
};

@interface OCPDiscoveryAdapter : NSObject

/// Tính năng có được bật và đủ điều kiện chạy không.
+ (BOOL)isEnabled;

/// Chiến lược khả dụng trên hệ thống này (dựa trên probe). Mảng rỗng nghĩa là
/// không có cách nào đưa app lên dashboard — tweak sẽ không làm gì.
+ (NSArray<NSNumber *> *)availableStrategies;

/// Thêm các ứng dụng được phép vào một FBSApplicationLibrary đã tồn tại.
/// Trả về số ứng dụng đã thêm thành công.
+ (NSUInteger)augmentApplicationLibrary:(nullable id)applicationLibrary;

/// Thông tin ứng dụng này có phải do OpenCarPlay đưa lên không.
+ (BOOL)isOpenCarPlayApplication:(nullable id)applicationInfo;

+ (NSString *)nameForStrategy:(OCPDiscoveryStrategy)strategy;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_DISCOVERY_ADAPTER_H */
