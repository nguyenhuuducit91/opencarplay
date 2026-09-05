# OpenCarPlay — bảng cài đặt.
#
# Không link Preferences.framework: bundle không tham chiếu lớp nào của nó lúc biên
# dịch. Xem ghi chú đầu OCPPrefsEntry.m về lý do.

ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OpenCarPlayPrefs

# Bundle phải thoả HAI điều kiện cùng lúc, mỗi cái ứng với một lần crash đã đo được:
#
#   1. KHÔNG khai báo lớp Objective-C nào. Superclass của lớp khai báo lúc biên dịch
#      phải bind qua chained fixups arm64e, và đó là chỗ readClass() chết. Gộp các lớp
#      Core vào đã tái hiện đúng lỗi này ở bản 0.25.0.
#   2. Đủ lớn để ld64-609 sinh chained fixups có dữ liệu. Binary quá nhỏ thì nó sinh
#      LC_DYLD_CHAINED_FIXUPS rỗng, và binary không bind được gì.
#
# Vì vậy chỉ gộp thêm mã C THUẦN (ocp_util.c) — đủ nội dung cho điều kiện 2 mà không
# tạo ra lớp nào cho điều kiện 1.
OpenCarPlayPrefs_FILES = OCPPrefsEntry.m ../Core/ocp_util.c
OpenCarPlayPrefs_INSTALL_PATH = /Library/PreferenceBundles
OpenCarPlayPrefs_FRAMEWORKS = Foundation
OpenCarPlayPrefs_CFLAGS = -fobjc-arc -Wall -I../Core -fno-ptrauth-calls -fno-ptrauth-returns \
                          -fno-ptrauth-indirect-gotos -fno-ptrauth-auth-traps

include $(THEOS_MAKE_PATH)/bundle.mk
