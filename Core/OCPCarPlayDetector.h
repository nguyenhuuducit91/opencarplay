// OpenCarPlay — phát hiện CarPlay kết nối / ngắt kết nối.
//
// Không dựa vào một tín hiệu duy nhất. Mỗi nguồn được probe riêng; nguồn nào không
// có thì bỏ qua và ghi log. Mọi tín hiệu chỉ đóng vai trò "đánh thức" — trạng thái
// thật luôn được xác nhận lại bằng OCPDisplayConfiguration.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_CARPLAY_DETECTOR_H
#define OCP_CARPLAY_DETECTOR_H

#import <Foundation/Foundation.h>

@class OCPDisplayConfiguration;

NS_ASSUME_NONNULL_BEGIN

/// Phát khi trạng thái đổi. userInfo[@"summary"] mô tả màn hình (chỉ khi kết nối).
FOUNDATION_EXPORT NSString *const OCPCarPlayDidConnectNotification;
FOUNDATION_EXPORT NSString *const OCPCarPlayDidDisconnectNotification;

@interface OCPCarPlayDetector : NSObject

+ (instancetype)sharedDetector;

/// Trạng thái hiện tại theo lần đánh giá gần nhất.
@property (nonatomic, readonly, getter=isCarPlayConnected) BOOL carPlayConnected;

/// Cấu hình màn hình xe khi đang kết nối; nil khi không.
@property (nonatomic, readonly, nullable) OCPDisplayConfiguration *displayConfiguration;

/// Bật theo dõi. Gọi nhiều lần là vô hại.
- (void)start;
- (void)stop;

/// Đánh giá lại ngay lập tức (đồng bộ, phải gọi trên main thread).
- (void)evaluateNow;

/// Danh sách nguồn tín hiệu đang hoạt động, để ghi log/diagnose.
@property (nonatomic, readonly, copy) NSArray<NSString *> *activeSignalSources;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_CARPLAY_DETECTOR_H */
