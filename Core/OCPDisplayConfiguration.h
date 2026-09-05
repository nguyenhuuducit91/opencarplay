// OpenCarPlay — thông tin màn hình CarPlay, lấy từ hệ thống lúc chạy.
//
// Không hard-code 800x480 hay bất kỳ kích thước nào. Ba nguồn dữ liệu được thử
// theo thứ tự tin cậy giảm dần; nguồn nào dùng được sẽ ghi vào `sourceName`.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_DISPLAY_CONFIGURATION_H
#define OCP_DISPLAY_CONFIGURATION_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCPDisplayConfiguration : NSObject

/// Kích thước theo point và theo pixel của màn hình xe.
@property (nonatomic, readonly) CGSize pointSize;
@property (nonatomic, readonly) CGSize pixelSize;
@property (nonatomic, readonly) CGFloat scale;

/// Nguồn dữ liệu đã dùng: "FBSDisplayConfiguration" | "CADisplay" | "UIScreen".
@property (nonatomic, readonly, copy) NSString *sourceName;

/// Đối tượng gốc của hệ thống (FBSDisplayConfiguration / CADisplay / UIScreen).
/// Các phase sau cần nó để tạo cửa sổ. nil nếu chỉ suy ra được kích thước.
@property (nonatomic, readonly, nullable, strong) id backingObject;

/// Có số liệu dùng được không.
@property (nonatomic, readonly) BOOL isValid;

/// Cấu hình màn hình CarPlay hiện tại, hoặc nil nếu không phát hiện được màn hình nào.
/// Mỗi lần gọi đều truy vấn lại hệ thống — không cache, vì trạng thái thay đổi khi cắm/rút.
+ (nullable instancetype)currentCarPlayConfiguration;

/// Tỉ lệ để đưa nội dung kích thước `contentSize` vừa khung màn hình xe.
- (CGFloat)fitScaleForContentSize:(CGSize)contentSize;

/// Quy đổi điểm chạm trên màn hình xe về hệ toạ độ ứng dụng.
- (CGPoint)convertPoint:(CGPoint)point
        fromContentSize:(CGSize)contentSize
                 offset:(CGPoint)offset;

/// Mô tả một dòng để ghi log.
- (NSString *)summary;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_DISPLAY_CONFIGURATION_H */
