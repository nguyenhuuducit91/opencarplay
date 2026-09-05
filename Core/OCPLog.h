// OpenCarPlay — logging có phân loại, tắt được.
//
// Mặc định chỉ ghi OCPLogError. Bật đầy đủ bằng khoá DebugLogging trong preferences.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_LOG_H
#define OCP_LOG_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCPLogCategory) {
    OCPLogCore = 0,
    OCPLogCarPlay,
    OCPLogApplication,
    OCPLogRendering,
    OCPLogTouch,
    OCPLogAudio,
    OCPLogCompatibility,
    OCPLogError,
};

@interface OCPLog : NSObject

/// Bật/tắt mọi danh mục trừ OCPLogError (luôn được ghi).
@property (class, nonatomic, assign) BOOL debugLoggingEnabled;

/// Đọc lại DebugLogging từ preferences. Gọi khi preferences thay đổi.
+ (void)reloadConfiguration;

+ (void)log:(OCPLogCategory)category
     format:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3);

/// Nhãn hiển thị của danh mục, ví dụ "[CarPlay]".
+ (NSString *)tagForCategory:(OCPLogCategory)category;

@end

#define OCPLogC(category, fmt, ...) [OCPLog log:(category) format:(fmt), ##__VA_ARGS__]
#define OCPLogError_(fmt, ...)      [OCPLog log:OCPLogError format:(fmt), ##__VA_ARGS__]

NS_ASSUME_NONNULL_END

#endif /* OCP_LOG_H */
