# OpenCarPlay — bảng cài đặt.
#
# Bundle này được PreferenceLoader nạp vào Settings. Nó là một preference bundle bình
# thường: khai báo lớp bằng @interface, liên kết Preferences.framework, đặt
# NSPrincipalClass trong Info.plist.
#
# GHI CHÚ LỊCH SỬ: các bản 0.17–0.30 dựng lớp lúc chạy bằng objc_allocateClassPair vì
# tin rằng toolchain Linux sinh ra chained fixups rỗng cho binary nhỏ. Đo lại bằng hằng
# số Mach-O đúng cho thấy điều đó sai — binary của bundle có 944 byte chained fixups,
# pointer_format ARM64E, y hệt dylib chính. Hằng số trong scripts/inspect_macho.py bị
# hoán đổi: LC_DYLD_CHAINED_FIXUPS là 0x80000034, còn 0x80000033 là LC_DYLD_EXPORTS_TRIE.

ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OpenCarPlayPrefs

OpenCarPlayPrefs_FILES = OCPPrefsTrace.c OCPPrefsCommon.m OCPRootListController.m \
                         OCPApplicationListController.m
OpenCarPlayPrefs_INSTALL_PATH = /Library/PreferenceBundles
OpenCarPlayPrefs_FRAMEWORKS = UIKit
OpenCarPlayPrefs_PRIVATE_FRAMEWORKS = Preferences
OpenCarPlayPrefs_CFLAGS = -fobjc-arc -Wall
# KHÔNG dùng -fno-ptrauth-*. Bộ cờ đó làm trình biên dịch bỏ lệnh `pacia`, tức mọi block
# và con trỏ hàm đưa cho hệ thống đều chưa ký — chính là lý do bundle này từng làm
# Settings chết với "possible pointer authentication failure". Xem ghi chú đầu Makefile
# ở thư mục gốc.

include $(THEOS_MAKE_PATH)/bundle.mk
