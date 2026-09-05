// OpenCarPlay — kiểm tra sự tồn tại của class/selector trước khi dùng.
//
// Nguyên tắc 2 (ARCHITECTURE.md): không API nào được dùng nếu chưa probe.
// Mọi module khác phải đi qua đây, không gọi objc_getClass trực tiếp.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_PROBE_H
#define OCP_PROBE_H

#import <Foundation/Foundation.h>

#import "OCPLog.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCPFeature) {
    /// Nhận biết màn hình/phiên CarPlay và cấu hình hiển thị.
    OCPFeatureCarPlayDetection = 0,
    /// Đưa ứng dụng vào danh sách hiển thị trên dashboard.
    OCPFeatureAppDiscovery,
    /// Dựng scene của ứng dụng và gắn lên cửa sổ màn hình xe.
    OCPFeatureSceneHosting,
    /// Tạo cửa sổ trên màn hình ngoài.
    OCPFeatureExternalWindow,
    /// Giữ ứng dụng không bị suspend khi khoá máy.
    OCPFeatureLockAssertion,
    /// Kênh liên lạc giữa các process.
    OCPFeatureTransport,

    OCPFeatureCount
};

@interface OCPProbe : NSObject

/// Class nếu tồn tại, nil nếu không. Ghi log một lần cho mỗi tên bị thiếu.
+ (nullable Class)classNamed:(NSString *)name;

/// Instance method có tồn tại trên class không (kể cả kế thừa)?
+ (BOOL)class:(NSString *)className respondsTo:(NSString *)selectorName;

/// Class method có tồn tại không?
+ (BOOL)metaClass:(NSString *)className respondsTo:(NSString *)selectorName;

/// Object có ivar tên này không? (dùng trước khi valueForKey:/setValue:forKey:)
+ (BOOL)object:(id)object hasIvar:(NSString *)ivarName;

/// Tính năng có đủ điều kiện tiền đề không. Kết quả được cache.
+ (BOOL)featureAvailable:(OCPFeature)feature;

/// Tên đọc được của tính năng.
+ (NSString *)nameForFeature:(OCPFeature)feature;

/// Những yêu cầu bị thiếu của một tính năng, dạng "ClassName" hoặc "-[Class selector]".
+ (NSArray<NSString *> *)missingRequirementsForFeature:(OCPFeature)feature;

/// Bảng kết quả đầy đủ: tên tính năng -> @(BOOL). Dùng cho diagnose.
+ (NSDictionary<NSString *, NSNumber *> *)diagnosticsReport;

#pragma mark - Gọi private API an toàn

/// Gọi selector không tham số trên một object. Trả nil nếu selector không tồn tại,
/// nếu kiểu trả về không phải object, hoặc nếu lời gọi ném exception.
/// Dùng NSInvocation thay vì ép kiểu objc_msgSend — an toàn hơn trên arm64e (PAC).
+ (nullable id)invoke:(nullable id)target selector:(NSString *)selectorName;

/// Như trên, với một tham số object.
+ (nullable id)invoke:(nullable id)target
             selector:(NSString *)selectorName
           withObject:(nullable id)argument;

/// Gọi class method không tham số.
+ (nullable id)invokeClass:(NSString *)className selector:(NSString *)selectorName;

/// Gọi selector trả về BOOL. `fallback` được dùng khi không gọi được.
+ (BOOL)invokeBool:(nullable id)target
          selector:(NSString *)selectorName
          fallback:(BOOL)fallback;

/// Đọc ivar/property bằng KVC nhưng an toàn: kiểm tra ivar tồn tại trước,
/// và nuốt exception nếu class từ chối KVC.
+ (nullable id)valueForKey:(NSString *)key onObject:(nullable id)object;

/// Ghi toàn bộ kết quả probe ra log (danh mục Compatibility).
/// Đây là công cụ thu thập bằng chứng runtime chính của dự án — xem RESEARCH.md §7.
+ (void)logFullReport;

/// Như trên nhưng ghi ở danh mục chỉ định. Trong giai đoạn phát triển, Entry.xm gọi
/// với OCPLogError để báo cáo hiện ra kể cả khi DebugLogging còn tắt; khi dự án ổn định
/// sẽ chuyển về OCPLogCompatibility.
+ (void)logFullReportAtCategory:(OCPLogCategory)category;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_PROBE_H */
