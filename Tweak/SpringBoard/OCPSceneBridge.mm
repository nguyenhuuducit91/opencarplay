// OpenCarPlay — xem OCPSceneBridge.h.
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPSceneBridge.h"

#import "OCPLog.h"
#import "OCPProbe.h"

static NSString *const kErrorDomain = @"com.opencarplay.scenebridge";

/// Tiền đề của từng bước: class -> selector cần có ("+" class method, "-" instance).
/// Bảng này chính là bản ghi những gì dự án ĐANG GIẢ ĐỊNH về SpringBoard iOS 18.6.
/// Khi khảo sát runtime cho kết quả khác, sửa ở đây trước khi sửa code.
static NSDictionary<NSString *, NSArray<NSString *> *> *OCPBridgeRequirements(void) {
    return @{
        @"SBApplicationController":        @[ @"+sharedInstance",
                                              @"-applicationWithBundleIdentifier:" ],
        @"SBSceneManagerCoordinator":      @[ @"+mainDisplaySceneManager" ],
        @"SBApplicationSceneHandleRequest":@[ @"+defaultRequestForApplication:sceneIdentity:displayIdentity:" ],
        @"SBDeviceApplicationSceneEntity": @[ @"-initWithApplicationSceneHandle:" ],
        @"SBAppViewController":            @[ @"-initWithIdentifier:andApplicationSceneEntity:" ],
    };
}

@interface OCPSceneBridge ()
@property (nonatomic, strong, nullable) id applicationViewController;
@property (nonatomic, strong, nullable) id sceneHandle;
@property (nonatomic, copy, nullable) NSString *bundleIdentifier;
@end

@implementation OCPSceneBridge

#pragma mark - Tiền đề

+ (NSArray<NSString *> *)missingRequirements {
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    NSDictionary<NSString *, NSArray<NSString *> *> *requirements = OCPBridgeRequirements();

    for (NSString *className in requirements) {
        if ([OCPProbe classNamed:className] == Nil) {
            [missing addObject:className];
            continue;
        }
        for (NSString *spec in requirements[className]) {
            NSString *selectorName = [spec substringFromIndex:1];
            BOOL ok = [spec hasPrefix:@"+"]
                ? [OCPProbe metaClass:className respondsTo:selectorName]
                : [OCPProbe class:className respondsTo:selectorName];
            if (!ok) {
                [missing addObject:[NSString stringWithFormat:@"%@[%@ %@]",
                                    [spec substringToIndex:1], className, selectorName]];
            }
        }
    }
    return [missing sortedArrayUsingSelector:@selector(compare:)];
}

+ (BOOL)isSupported {
    return [self missingRequirements].count == 0;
}

+ (NSString *)nameForStage:(OCPBridgeStage)stage {
    switch (stage) {
        case OCPBridgeStageResolveApplication:   return @"ResolveApplication";
        case OCPBridgeStageResolveSceneManager:  return @"ResolveSceneManager";
        case OCPBridgeStageResolveSceneIdentity: return @"ResolveSceneIdentity";
        case OCPBridgeStageCreateSceneHandle:    return @"CreateSceneHandle";
        case OCPBridgeStageCreateSceneEntity:    return @"CreateSceneEntity";
        case OCPBridgeStageCreateViewController: return @"CreateViewController";
        case OCPBridgeStageExtractView:          return @"ExtractView";
        case OCPBridgeStageCount:                break;
    }
    return @"Unknown";
}

+ (NSError *)errorForStage:(OCPBridgeStage)stage detail:(NSString *)detail {
    return [NSError errorWithDomain:kErrorDomain
                               code:stage
                           userInfo:@{ NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"%@ — %@",
                                          [self nameForStage:stage], detail] }];
}

#pragma mark - Dựng scene

- (nullable UIView *)viewForApplicationWithBundleIdentifier:(NSString *)bundleIdentifier
                                                      error:(NSError **)error {
    if (bundleIdentifier.length == 0) {
        if (error) *error = [[self class] errorForStage:OCPBridgeStageResolveApplication
                                                 detail:@"bundle identifier rỗng"];
        return nil;
    }

    NSArray<NSString *> *missing = [[self class] missingRequirements];
    if (missing.count > 0) {
        if (error) {
            *error = [[self class] errorForStage:OCPBridgeStageResolveApplication
                                          detail:[NSString stringWithFormat:
                                                  @"thiếu tiền đề: %@",
                                                  [missing componentsJoinedByString:@", "]]];
        }
        return nil;
    }

    @try {
        // Bước 1 — đối tượng ứng dụng của SpringBoard.
        id controller = [OCPProbe invokeClassNamed:@"SBApplicationController"
                                          selector:@"sharedInstance"
                                         arguments:nil];
        id application = [OCPProbe invokeTarget:controller
                                       selector:@"applicationWithBundleIdentifier:"
                                      arguments:@[ bundleIdentifier ]];
        if (application == nil) {
            if (error) *error = [[self class] errorForStage:OCPBridgeStageResolveApplication
                                                     detail:@"SpringBoard không biết ứng dụng này"];
            return nil;
        }

        // Bước 2 — trình quản lý scene của màn hình chính.
        //
        // Lưu ý kiến trúc: scene vẫn thuộc MÀN HÌNH CHÍNH, ta chỉ mượn view của nó
        // đặt sang cửa sổ trên màn hình xe. Đó là lý do ứng dụng không thể hiện
        // đồng thời ở hai nơi (RESEARCH.md §2.4).
        id sceneManager = [OCPProbe invokeClassNamed:@"SBSceneManagerCoordinator"
                                            selector:@"mainDisplaySceneManager"
                                           arguments:nil];
        if (sceneManager == nil) {
            if (error) *error = [[self class] errorForStage:OCPBridgeStageResolveSceneManager
                                                     detail:@"mainDisplaySceneManager trả nil"];
            return nil;
        }

        // Ba selector dưới đây được gọi trên chính đối tượng này. Không đưa vào bảng
        // tiền đề ở đầu file được vì bảng đó tra theo TÊN CLASS, mà tên class của scene
        // manager là thứ ta không được phép đoán. Kiểm tra ngay trên đối tượng thật, và
        // kiểm tra TRƯỚC khi tạo ra bất cứ thứ gì — thiếu một selector ở giữa chuỗi
        // nghĩa là bỏ lại một scene đã dựng dở.
        for (NSString *required in @[ @"displayIdentity",
                                      @"_sceneIdentityForApplication:createPrimaryIfRequired:",
                                      @"fetchOrCreateApplicationSceneHandleForRequest:" ]) {
            if (![sceneManager respondsToSelector:NSSelectorFromString(required)]) {
                if (error) {
                    *error = [[self class] errorForStage:OCPBridgeStageResolveSceneManager
                                                  detail:[NSString stringWithFormat:
                                                          @"-[%@ %@] không tồn tại",
                                                          NSStringFromClass([sceneManager class]),
                                                          required]];
                }
                return nil;
            }
        }

        id displayIdentity = [OCPProbe invoke:sceneManager selector:@"displayIdentity"];

        // Bước 3 — định danh scene, tạo mới nếu ứng dụng chưa có.
        id sceneIdentity =
            [OCPProbe invokeTarget:sceneManager
                          selector:@"_sceneIdentityForApplication:createPrimaryIfRequired:"
                         arguments:@[ application, @YES ]];
        if (sceneIdentity == nil) {
            if (error) *error = [[self class] errorForStage:OCPBridgeStageResolveSceneIdentity
                                                     detail:@"không lấy được scene identity"];
            return nil;
        }

        // Bước 4 — scene handle.
        id request = [OCPProbe invokeClassNamed:@"SBApplicationSceneHandleRequest"
                                       selector:@"defaultRequestForApplication:sceneIdentity:displayIdentity:"
                                      arguments:@[ application, sceneIdentity,
                                                   displayIdentity ?: [NSNull null] ]];
        if (request == nil) {
            if (error) *error = [[self class] errorForStage:OCPBridgeStageCreateSceneHandle
                                                     detail:@"không dựng được request"];
            return nil;
        }

        id sceneHandle = [OCPProbe invokeTarget:sceneManager
                                       selector:@"fetchOrCreateApplicationSceneHandleForRequest:"
                                      arguments:@[ request ]];
        if (sceneHandle == nil) {
            if (error) *error = [[self class] errorForStage:OCPBridgeStageCreateSceneHandle
                                                     detail:@"fetchOrCreate trả nil"];
            return nil;
        }
        self.sceneHandle = sceneHandle;

        // Bước 5 — entity bọc scene handle.
        id entity = [OCPProbe instantiateClassNamed:@"SBDeviceApplicationSceneEntity"
                                        initialiser:@"initWithApplicationSceneHandle:"
                                          arguments:@[ sceneHandle ]];
        if (entity == nil) {
            if (error) *error = [[self class] errorForStage:OCPBridgeStageCreateSceneEntity
                                                     detail:@"không dựng được entity"];
            return nil;
        }

        // Bước 6 — view controller giữ scene.
        id viewController =
            [OCPProbe instantiateClassNamed:@"SBAppViewController"
                                initialiser:@"initWithIdentifier:andApplicationSceneEntity:"
                                  arguments:@[ bundleIdentifier, entity ]];
        if (viewController == nil) {
            if (error) *error = [[self class] errorForStage:OCPBridgeStageCreateViewController
                                                     detail:@"không dựng được SBAppViewController"];
            return nil;
        }
        self.applicationViewController = viewController;
        self.bundleIdentifier = bundleIdentifier;

        // Bước 7 — lấy view.
        UIView *view = [OCPProbe invoke:viewController selector:@"view"];
        if (![view isKindOfClass:[UIView class]]) {
            if (error) *error = [[self class] errorForStage:OCPBridgeStageExtractView
                                                     detail:@"view controller không trả về UIView"];
            [self teardown];
            return nil;
        }

        OCPLogError_(@"scene bridge dựng xong cho %@", bundleIdentifier);
        return view;
    } @catch (NSException *exception) {
        OCPLogError_(@"scene bridge ném exception: %@ — %@", exception.name, exception.reason);
        if (error) *error = [[self class] errorForStage:OCPBridgeStageCreateViewController
                                                 detail:exception.reason ?: @"exception"];
        [self teardown];
        return nil;
    }
}

- (void)teardown {
    @try {
        UIView *view = [OCPProbe invoke:self.applicationViewController selector:@"view"];
        if ([view isKindOfClass:[UIView class]] && view.superview != nil) {
            [view removeFromSuperview];
        }
    } @catch (NSException *exception) {
        OCPLogError_(@"gỡ view thất bại: %@", exception.reason);
    }

    self.applicationViewController = nil;
    self.sceneHandle = nil;
    self.bundleIdentifier = nil;
    OCPLogC(OCPLogRendering, @"scene bridge đã dọn dẹp");
}

@end
