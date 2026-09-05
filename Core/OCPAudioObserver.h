// OpenCarPlay — quan sát tuyến âm thanh, KHÔNG can thiệp.
//
// Kết luận từ RESEARCH.md §6: ứng dụng chạy qua scene re-parenting vẫn là scene của
// màn hình chính, nên âm thanh đi theo tuyến mặc định của hệ thống — mà khi CarPlay
// đang kết nối thì tuyến mặc định đã là CarPlay. Vì vậy MVP không cần code audio.
//
// Tự ý gọi setCategory:/setActive: từ một tweak trong SpringBoard là cách chắc chắn
// phá ducking, chỉ dẫn dẫn đường và cuộc gọi của xe. Lớp này CHỈ ĐỌC: nó ghi lại
// tuyến âm thanh tại các thời điểm quan trọng để lần chạy thật xác nhận (hoặc bác bỏ)
// kết luận trên.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_AUDIO_OBSERVER_H
#define OCP_AUDIO_OBSERVER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCPAudioObserver : NSObject

+ (instancetype)sharedObserver;

/// Bắt đầu theo dõi thay đổi tuyến âm thanh. Không thay đổi cấu hình audio nào.
- (void)start;
- (void)stop;

/// Mô tả tuyến âm thanh hiện tại, ví dụ "CarAudio (Vehicle Audio)".
/// Trả "(không đọc được)" nếu AVAudioSession không dùng được trong process này.
- (NSString *)currentRouteDescription;

/// Tuyến hiện tại có đi qua hệ thống âm thanh của xe không.
@property (nonatomic, readonly) BOOL routedToVehicle;

/// Ghi lại tuyến hiện tại kèm nhãn ngữ cảnh (ví dụ "sau khi mở ứng dụng").
- (void)logCurrentRouteWithContext:(NSString *)context;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_AUDIO_OBSERVER_H */
