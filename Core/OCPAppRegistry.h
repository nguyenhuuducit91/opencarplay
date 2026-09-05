// OpenCarPlay — danh sách ứng dụng được phép dùng với CarPlay.
//
// Không hard-code bundle identifier nào của người dùng. Chỉ có một danh sách chặn
// cứng cho các process hệ thống mà việc host chắc chắn phá hệ thống — danh sách đó
// nằm trong ocp_util.c để unit test kiểm chứng được.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_APP_REGISTRY_H
#define OCP_APP_REGISTRY_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Lý do một bundle identifier bị từ chối.
typedef NS_ENUM(NSInteger, OCPRegistryDecision) {
    OCPRegistryDecisionAllowed = 0,
    /// Tweak đang tắt (Enabled = NO hoặc chưa cấu hình).
    OCPRegistryDecisionTweakDisabled,
    /// Không nằm trong AllowedApplications.
    OCPRegistryDecisionNotListed,
    /// Chuỗi không phải bundle identifier hợp lệ.
    OCPRegistryDecisionInvalidIdentifier,
    /// Process hệ thống bị chặn cứng — luôn thắng danh sách cho phép.
    OCPRegistryDecisionSystemCritical,
};

@interface OCPAppRegistry : NSObject

+ (instancetype)sharedRegistry;

/// Nạp lại từ preferences. Tự động chạy khi preferences đổi.
- (void)reload;

/// Quyết định cuối cùng cho một bundle identifier.
- (OCPRegistryDecision)decisionForBundleIdentifier:(nullable NSString *)bundleIdentifier;

/// Rút gọn của decisionForBundleIdentifier: == Allowed.
- (BOOL)isAllowed:(nullable NSString *)bundleIdentifier;

/// Danh sách đã lọc: bỏ chuỗi không hợp lệ và process bị chặn cứng.
@property (nonatomic, readonly, copy) NSArray<NSString *> *allowedApplications;

/// Các mục trong preferences bị loại, kèm lý do — để hiển thị cho người dùng biết
/// vì sao app họ thêm không xuất hiện.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *rejectedEntries;

+ (NSString *)nameForDecision:(OCPRegistryDecision)decision;

/// Mô tả một dòng cho log.
- (NSString *)summary;

@end

NS_ASSUME_NONNULL_END

#endif /* OCP_APP_REGISTRY_H */
