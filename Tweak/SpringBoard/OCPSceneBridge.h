// OpenCarPlay — dựng scene của ứng dụng và lấy view của nó để đặt lên màn hình xe.
//
// TRẠNG THÁI: THỬ NGHIỆM, RỦI RO CAO NHẤT TRONG DỰ ÁN.
//
// Toàn bộ chuỗi dưới đây gồm class nội bộ của SpringBoard.app. Chúng KHÔNG có trong
// SDK nên không thể xác minh trước; RESEARCH.md đánh dấu cả nhóm là [DEVICE] và Q5
// vẫn chưa có lời giải. Giữa iOS 14 (nơi chuỗi này được biết là hoạt động) và iOS 18.6
// có bốn vòng tái cấu trúc scene.
//
// Vì vậy bridge được chia thành các bước có tiền đề rõ ràng: mỗi bước kiểm tra
// class/selector trước khi gọi, và thất bại ở bất kỳ bước nào cũng dừng sạch sẽ với
// tên bước cụ thể — không bao giờ để lại trạng thái nửa vời trong SpringBoard.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_SCENE_BRIDGE_H
#define OCP_SCENE_BRIDGE_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCPBridgeStage) {
    OCPBridgeStageResolveApplication = 0,
    OCPBridgeStageResolveSceneManager,
    OCPBridgeStageResolveSceneIdentity,
    OCPBridgeStageCreateSceneHandle,
    OCPBridgeStageCreateSceneEntity,
    OCPBridgeStageCreateViewController,
    OCPBridgeStageExtractView,
    OCPBridgeStageCount
};

@interface OCPSceneBridge : NSObject

/// Toàn bộ tiền đề của mọi bước có mặt trên hệ thống này không.
+ (BOOL)isSupported;

/// Những tiền đề còn thiếu, dạng "ClassName" hoặc "-[Class selector]".
+ (NSArray<NSString *> *)missingRequirements;

+ (NSString *)nameForStage:(OCPBridgeStage)stage;

/// Dựng scene cho ứng dụng và trả về view có thể đặt lên cửa sổ màn hình xe.
/// nil nếu thất bại; `error` mang tên bước hỏng.
- (nullable UIView *)viewForApplicationWithBundleIdentifier:(NSString *)bundleIdentifier
                                                      error:(NSError **)error;

/// Giải phóng mọi thứ bridge đang giữ. An toàn khi gọi nhiều lần.
- (void)teardown;

/// View controller đang giữ scene (dùng cho Phase 10 khi xử lý chạm).
@property (nonatomic, readonly, nullable, strong) id applicationViewController;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_SCENE_BRIDGE_H */
