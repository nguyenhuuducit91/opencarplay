// OpenCarPlay — xem OCPDisplayConfiguration.h.
//
// CẢNH BÁO: cách nhận diện màn hình CarPlay ở đây dựa trên phân tích trong
// RESEARCH.md §3.5/§7.4 (Q7) và CHƯA được xác minh trên iOS 18.6.2. Mỗi nhánh đều
// probe trước và ghi log nguồn đã dùng, để lần chạy thật trả lời được câu hỏi đó.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import "OCPDisplayConfiguration.h"
#import "OCPLog.h"
#import "OCPProbe.h"
#import "ocp_util.h"

@interface OCPDisplayConfiguration ()
@property (nonatomic, assign) CGSize pointSize;
@property (nonatomic, assign) CGSize pixelSize;
@property (nonatomic, assign) CGFloat scale;
@property (nonatomic, copy) NSString *sourceName;
@property (nonatomic, strong, nullable) id backingObject;
@end

@implementation OCPDisplayConfiguration

#pragma mark - Nguồn 1: FrontBoardServices (đường mà SpringBoard thực sự dùng)

+ (nullable instancetype)configurationFromFrontBoard {
    // FBSDisplayMonitor liệt kê mọi display hệ thống biết. Xem RESEARCH.md §3.6.
    id monitor = [OCPProbe invokeClass:@"FBSDisplayMonitor" selector:@"sharedInstance"];
    if (monitor == nil) return nil;

    id configurations = [OCPProbe invoke:monitor selector:@"displayConfigurations"];
    if (![configurations isKindOfClass:[NSArray class]]) return nil;

    for (id configuration in (NSArray *)configurations) {
        if ([OCPProbe invokeBool:configuration selector:@"isMainDisplay" fallback:NO]) continue;

        // Không đoán tên thuộc tính CarPlay — chỉ nhận display phụ và ghi lại mô tả
        // để lần chạy thật cho biết display xe trông như thế nào.
        OCPLogC(OCPLogCarPlay, @"display phụ: %@", configuration);

        CGSize pointSize = CGSizeZero;
        CGFloat scale = 0.0;
        NSValue *sizeValue = [OCPProbe valueForKey:@"pointSize" onObject:configuration];
        if ([sizeValue isKindOfClass:[NSValue class]]) pointSize = [sizeValue CGSizeValue];
        NSNumber *scaleValue = [OCPProbe valueForKey:@"scale" onObject:configuration];
        if ([scaleValue isKindOfClass:[NSNumber class]]) scale = scaleValue.doubleValue;

        if (pointSize.width <= 0 || pointSize.height <= 0) continue;

        OCPDisplayConfiguration *result = [[self alloc] init];
        result.pointSize = pointSize;
        result.scale = (scale > 0) ? scale : 1.0;
        result.pixelSize = CGSizeMake(pointSize.width * result.scale,
                                      pointSize.height * result.scale);
        result.sourceName = @"FBSDisplayConfiguration";
        result.backingObject = configuration;
        return result;
    }
    return nil;
}

#pragma mark - Nguồn 2: CADisplay + AVExternalDevice (cách của carplay-cast, iOS 14)

+ (nullable instancetype)configurationFromCADisplay {
    id device = [OCPProbe invokeClass:@"AVExternalDevice"
                             selector:@"currentCarPlayExternalDevice"];
    if (device == nil) return nil;

    id screenIDs = [OCPProbe invoke:device selector:@"screenIDs"];
    if (![screenIDs isKindOfClass:[NSArray class]] || [(NSArray *)screenIDs count] == 0) return nil;
    NSString *targetID = [(NSArray *)screenIDs firstObject];
    if (![targetID isKindOfClass:[NSString class]]) return nil;

    id displays = [OCPProbe invokeClass:@"CADisplay" selector:@"displays"];
    if (![displays isKindOfClass:[NSArray class]]) return nil;

    for (id display in (NSArray *)displays) {
        id uniqueID = [OCPProbe invoke:display selector:@"uniqueId"];
        if (![uniqueID isKindOfClass:[NSString class]] || ![targetID isEqualToString:uniqueID]) {
            continue;
        }

        NSValue *boundsValue = [OCPProbe valueForKey:@"bounds" onObject:display];
        CGSize pointSize = CGSizeZero;
        if ([boundsValue isKindOfClass:[NSValue class]]) pointSize = [boundsValue CGRectValue].size;
        if (pointSize.width <= 0 || pointSize.height <= 0) continue;

        OCPDisplayConfiguration *result = [[self alloc] init];
        result.pointSize = pointSize;
        result.scale = 1.0;
        result.pixelSize = pointSize;
        result.sourceName = @"CADisplay";
        result.backingObject = display;
        return result;
    }
    return nil;
}

#pragma mark - Nguồn 3: UIScreen (public, deprecated từ iOS 16 nhưng còn dùng được)

+ (nullable instancetype)configurationFromUIScreen {
    NSArray<UIScreen *> *screens = [UIScreen screens];
    UIScreen *main = [UIScreen mainScreen];

    for (UIScreen *screen in screens) {
        if (screen == main) continue;

        // _isCarScreen là private; nếu không có thì mọi màn hình phụ đều là ứng viên.
        BOOL looksLikeCar = [OCPProbe invokeBool:screen selector:@"_isCarScreen" fallback:YES];
        if (!looksLikeCar) continue;

        CGSize pointSize = screen.bounds.size;
        if (pointSize.width <= 0 || pointSize.height <= 0) continue;

        OCPDisplayConfiguration *result = [[self alloc] init];
        result.pointSize = pointSize;
        result.scale = screen.scale > 0 ? screen.scale : 1.0;
        result.pixelSize = CGSizeMake(pointSize.width * result.scale,
                                      pointSize.height * result.scale);
        result.sourceName = @"UIScreen";
        result.backingObject = screen;
        return result;
    }
    return nil;
}

#pragma mark - Công khai

+ (nullable instancetype)currentCarPlayConfiguration {
    @try {
        OCPDisplayConfiguration *configuration = [self configurationFromFrontBoard];
        if (configuration == nil) configuration = [self configurationFromCADisplay];
        if (configuration == nil) configuration = [self configurationFromUIScreen];

        if (configuration != nil) {
            OCPLogC(OCPLogCarPlay, @"cấu hình màn hình xe: %@", [configuration summary]);
        }
        return configuration;
    } @catch (NSException *exception) {
        OCPLogError_(@"đọc cấu hình màn hình thất bại: %@", exception.reason);
        return nil;
    }
}

- (BOOL)isValid {
    return _pointSize.width > 0 && _pointSize.height > 0 && _scale > 0;
}

- (CGFloat)fitScaleForContentSize:(CGSize)contentSize {
    return ocp_aspect_fit_scale(contentSize.width, contentSize.height,
                                _pointSize.width, _pointSize.height);
}

- (CGPoint)convertPoint:(CGPoint)point
        fromContentSize:(CGSize)contentSize
                 offset:(CGPoint)offset {
    CGFloat scale = [self fitScaleForContentSize:contentSize];
    double x = 0, y = 0;
    if (!ocp_convert_point(point.x, point.y, offset.x, offset.y, scale, &x, &y)) {
        return CGPointZero;
    }
    return CGPointMake(x, y);
}

- (NSString *)summary {
    return [NSString stringWithFormat:@"%.0fx%.0f pt @%.1fx (%.0fx%.0f px) qua %@",
            _pointSize.width, _pointSize.height, _scale,
            _pixelSize.width, _pixelSize.height, _sourceName ?: @"?"];
}

@end
