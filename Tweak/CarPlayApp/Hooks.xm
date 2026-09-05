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

#import "OCPDiscoveryAdapter.h"
#import "OCPLog.h"
#import "OCPProbe.h"

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

#pragma mark - Cài đặt

/// Gọi từ Entry.xm sau khi đã xác nhận process, phiên bản iOS và cấu hình.
void OCPInstallCarPlayHooks(void) {
    @try {
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
    } @catch (NSException *exception) {
        OCPLogError_(@"cài hook CarPlay thất bại: %@ — %@", exception.name, exception.reason);
    }
}
