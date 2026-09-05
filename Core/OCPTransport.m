// OpenCarPlay — xem OCPTransport.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPTransport.h"

#import "OCPDefines.h"
#import "OCPLog.h"

#import <notify.h>

NSString *const OCPMessagePreferencesChanged = @"prefs-changed";
NSString *const OCPMessageLaunchApplication  = @"launch-application";
NSString *const OCPMessageDismissApplication = @"dismiss-application";

@interface OCPTransport ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *tokens;
@property (nonatomic, assign) OCPTransportBackend activeBackend;
@end

@implementation OCPTransport

+ (instancetype)sharedTransport {
    static OCPTransport *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _tokens = [NSMutableDictionary dictionary];
        _activeBackend = OCPTransportBackendDarwinNotify;
    }
    return self;
}

- (void)dealloc {
    for (NSNumber *token in _tokens.allValues) {
        notify_cancel(token.intValue);
    }
}

- (NSString *)activeBackendName {
    switch (_activeBackend) {
        case OCPTransportBackendDarwinNotify: return @"DarwinNotify";
        case OCPTransportBackendUnavailable:  return @"Unavailable";
    }
    return @"Unknown";
}

#pragma mark - Đặt tên

/// Tên Darwin notification đầy đủ, có tiền tố domain để không đụng ai khác.
- (NSString *)darwinNameFor:(NSString *)message {
    return [NSString stringWithFormat:@"%@.%@", OCPPreferencesDomain, message];
}

/// File chứa payload của message. Darwin notification không mang dữ liệu, nên payload
/// đi qua đây. Đặt trong thư mục preferences để mọi process đọc được.
- (NSString *)payloadPathFor:(NSString *)message {
    NSString *directory = [OCPPreferencesPath() stringByDeletingLastPathComponent];
    return [directory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.%@.payload.plist", OCPPreferencesDomain, message]];
}

#pragma mark - Gửi / nhận

- (void)postMessage:(NSString *)name payload:(nullable NSDictionary *)payload {
    if (name.length == 0) return;

    @try {
        if (payload.count > 0) {
            NSString *path = [self payloadPathFor:name];
            if (![payload writeToFile:path atomically:YES]) {
                OCPLogError_(@"không ghi được payload cho %@", name);
            }
        }

        NSString *darwinName = [self darwinNameFor:name];
        uint32_t status = notify_post(darwinName.UTF8String);
        if (status != NOTIFY_STATUS_OK) {
            OCPLogError_(@"notify_post(%@) trả về %u", darwinName, status);
            return;
        }
        OCPLogC(OCPLogCore, @"gửi message: %@%@", name, payload.count ? @" (có payload)" : @"");
    } @catch (NSException *exception) {
        OCPLogError_(@"gửi message %@ thất bại: %@", name, exception.reason);
    }
}

- (void)observeMessage:(NSString *)name handler:(void (^)(NSDictionary *payload))handler {
    if (name.length == 0 || handler == nil) return;

    @synchronized (self.tokens) {
        if (self.tokens[name] != nil) {
            OCPLogC(OCPLogCore, @"đã đăng ký message %@ rồi — bỏ qua", name);
            return;
        }

        NSString *darwinName = [self darwinNameFor:name];
        NSString *payloadPath = [self payloadPathFor:name];

        int token = 0;
        uint32_t status = notify_register_dispatch(
            darwinName.UTF8String, &token, dispatch_get_main_queue(), ^(int registeredToken) {
                NSDictionary *payload = nil;
                @try {
                    payload = [NSDictionary dictionaryWithContentsOfFile:payloadPath];
                } @catch (NSException *exception) {
                    payload = nil;
                }
                @try {
                    handler(payload ?: @{});
                } @catch (NSException *exception) {
                    OCPLogError_(@"xử lý message %@ thất bại: %@", name, exception.reason);
                }
            });

        if (status != NOTIFY_STATUS_OK) {
            OCPLogError_(@"đăng ký %@ thất bại (status %u)", darwinName, status);
            self.activeBackend = OCPTransportBackendUnavailable;
            return;
        }

        self.tokens[name] = @(token);
        OCPLogC(OCPLogCore, @"lắng nghe message: %@ (%@)", name, darwinName);
    }
}

@end
