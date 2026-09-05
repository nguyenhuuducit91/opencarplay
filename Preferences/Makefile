# OpenCarPlay — bảng cài đặt.
#
# Không link Preferences.framework: bundle không tham chiếu lớp nào của nó lúc biên
# dịch. Xem ghi chú đầu OCPPrefsEntry.m về lý do.

ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OpenCarPlayPrefs

# Gộp cả lớp Core vào bundle — không phải vì cần chúng, mà vì ld64-609 sinh
# LC_DYLD_CHAINED_FIXUPS RỖNG cho binary quá nhỏ. Dylib chính (nhiều mã, nhiều symbol)
# lại có fixups hợp lệ. Thêm nội dung là cách rẻ nhất để kiểm chứng giả thuyết đó.
OpenCarPlayPrefs_FILES = OCPPrefsEntry.m $(wildcard ../Core/*.m) $(wildcard ../Core/*.c)
OpenCarPlayPrefs_INSTALL_PATH = /Library/PreferenceBundles
OpenCarPlayPrefs_FRAMEWORKS = Foundation UIKit
OpenCarPlayPrefs_CFLAGS = -fobjc-arc -Wall -I../Core -fno-ptrauth-calls -fno-ptrauth-returns \
                          -fno-ptrauth-indirect-gotos -fno-ptrauth-auth-traps

include $(THEOS_MAKE_PATH)/bundle.mk
