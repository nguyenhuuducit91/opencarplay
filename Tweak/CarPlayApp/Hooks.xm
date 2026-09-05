// OpenCarPlay — hook trong process CarPlay dashboard.
//
// Đây là những hook ĐẦU TIÊN của dự án thực sự thay đổi hành vi hệ thống. Nguyên tắc:
//
//   • không hook nếu class hoặc selector không tồn tại — kiểm tra trước khi %init
//   • luôn gọi %orig và chỉ bổ sung vào kết quả, không thay thế nó như carplay-cast
//     (nếu phần bổ sung hỏng, CarPlay nguyên bản vẫn chạy)
//   • mọi thân hook bọc trong @try/@catch
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#import <Foundation/Foundation.h>

#import <dlfcn.h>

#import "OCPDiscoveryAdapter.h"
#import "OCPLog.h"
#import "OCPProbe.h"
#import "OCPTransport.h"

#pragma mark - Danh sách ứng dụng của dashboard

%group OCPApplicationLibrary

%hook CARApplication

/// CarPlay dựng danh sách ứng dụng sẽ hiện trên dashboard.
/// %orig chỉ trả về ứng dụng có entitlement CarPlay; ta thêm ứng dụng người dùng
/// đã cho phép vào đúng danh sách đó thay vì tạo danh sách mới.
+ (id)_newApplicationLibrary {
    id library = %orig;
    @try {
        [OCPDiscoveryAdapter augmentApplicationLibrary:library];
    } @catch (NSException *exception) {
        OCPLogError_(@"augment library thất bại: %@ — %@", exception.name, exception.reason);
    }
    return library;
}

%end

%end

#pragma mark - Giữ danh sách sau khi hệ thống làm mới

%group OCPDashboardRefresh

%hook _CARDashboardHomeViewController

/// Được gọi khi ứng dụng được cài/gỡ. Hệ thống dựng lại danh sách, nên phần bổ sung
/// của ta biến mất và phải thêm lại.
- (void)_handleAppLibraryRefresh {
    @try {
        id library = [OCPProbe invoke:self selector:@"library"];
        [OCPDiscoveryAdapter augmentApplicationLibrary:library];
    } @catch (NSException *exception) {
        OCPLogError_(@"làm mới library thất bại: %@", exception.reason);
    }
    %orig;
}

%end

%end

#pragma mark - Chạm icon trên dashboard

%group OCPLaunchInterception

%hook CARApplicationLaunchInfo

/// CarPlay dựng thông tin khởi chạy khi người dùng chạm một icon.
///
/// Với ứng dụng do OpenCarPlay đưa lên, để CarPlay tự khởi chạy là không dùng được:
/// ứng dụng không có scene CarPlay nên hệ thống sẽ đi vào nhánh template và thất bại.
/// Ta chặn nhánh đó và chuyển yêu cầu sang SpringBoard.
///
/// Ứng dụng CarPlay chính hãng đi qua %orig nguyên vẹn.
+ (id)launchInfoForApplication:(id)application withActivationSettings:(id)settings {
    @try {
        if ([OCPDiscoveryAdapter isOpenCarPlayApplication:application]) {
            NSString *bundleIdentifier = [OCPProbe invoke:application
                                                 selector:@"bundleIdentifier"];
            if ([bundleIdentifier isKindOfClass:[NSString class]]) {
                OCPLogError_(@"chạm icon OpenCarPlay: %@", bundleIdentifier);
                [[OCPTransport sharedTransport]
                    postMessage:OCPMessageLaunchApplication
                        payload:@{ @"bundleIdentifier": bundleIdentifier }];
                // Trả nil để CarPlay không tự khởi chạy theo nhánh template.
                return nil;
            }
            OCPLogError_(@"không đọc được bundleIdentifier từ thông tin ứng dụng");
        }
    } @catch (NSException *exception) {
        OCPLogError_(@"xử lý chạm icon thất bại: %@ — %@", exception.name, exception.reason);
    }
    return %orig;
}

%end

%end

#pragma mark - Cài đặt

/// Runtime hook có sẵn không.
///
/// Logos gọi thẳng MSHookMessageEx trong %init mà không kiểm tra NULL. Nếu
/// CydiaSubstrate vắng mặt — hoặc được liên kết weak như bản 0.24–0.30 từng làm — thì
/// symbol bằng NULL và %init nhảy vào địa chỉ 0. Kiểm tra trước để lỗi hiện ra ở dạng
/// một dòng log thay vì một crash không lần được nguyên nhân.
static BOOL OCPHookingRuntimeAvailable(void) {
    return dlsym(RTLD_DEFAULT, "MSHookMessageEx") != NULL;
}

/// Gọi từ Entry.xm sau khi đã xác nhận process, phiên bản iOS và cấu hình.
void OCPInstallCarPlayHooks(void) {
    @try {
        if (!OCPHookingRuntimeAvailable()) {
            OCPLogError_(@"không tìm thấy MSHookMessageEx — runtime hook không khả dụng, "
                         @"không cài hook nào. Kiểm tra gói ellekit.");
            return;
        }

        if (![OCPDiscoveryAdapter isEnabled]) {
            OCPLogC(OCPLogApplication,
                    @"discovery chưa bật (cần Enabled và ExperimentalDiscovery) — không hook");
            return;
        }

        if ([[OCPDiscoveryAdapter availableStrategies] count] == 0) {
            OCPLogError_(@"không có chiến lược discovery khả dụng — không hook");
            return;
        }

        // Chỉ hook khi cả class lẫn selector đều có mặt. Thiếu một trong hai nghĩa là
        // iOS đã đổi cơ chế; khi đó ghi log để RESEARCH.md được cập nhật, không đoán tiếp.
        if ([OCPProbe metaClass:@"CARApplication" respondsTo:@"_newApplicationLibrary"]) {
            %init(OCPApplicationLibrary);
            OCPLogError_(@"đã hook +[CARApplication _newApplicationLibrary]");
        } else {
            OCPLogError_(@"+[CARApplication _newApplicationLibrary] KHÔNG tồn tại trên iOS này — "
                         @"xem RESEARCH.md Q2, cần khảo sát runtime để tìm điểm thay thế");
        }

        if ([OCPProbe class:@"_CARDashboardHomeViewController"
                 respondsTo:@"_handleAppLibraryRefresh"]) {
            %init(OCPDashboardRefresh);
            OCPLogC(OCPLogApplication, @"đã hook -[_CARDashboardHomeViewController _handleAppLibraryRefresh]");
        }

        if ([OCPProbe metaClass:@"CARApplicationLaunchInfo"
                     respondsTo:@"launchInfoForApplication:withActivationSettings:"]) {
            %init(OCPLaunchInterception);
            OCPLogError_(@"đã hook +[CARApplicationLaunchInfo launchInfoForApplication:...]");
        } else {
            OCPLogError_(@"+[CARApplicationLaunchInfo launchInfoForApplication:...] KHÔNG tồn tại "
                         @"— chạm icon sẽ đi theo đường mặc định của CarPlay, xem RESEARCH.md Q2");
        }
    } @catch (NSException *exception) {
        OCPLogError_(@"cài hook CarPlay thất bại: %@ — %@", exception.name, exception.reason);
    }
}
