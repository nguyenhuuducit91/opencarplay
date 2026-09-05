# OpenCarPlay — bảng cài đặt.
#
# Bundle này cố tình KHÔNG định nghĩa lớp Objective-C nào ở thời điểm biên dịch; xem
# ghi chú đầu OCPPrefsEntry.m. Vì vậy nó cũng không cần link Preferences.framework:
# PSListController được tra cứu qua NSClassFromString lúc chạy.

# Subproject không kế thừa ARCHS của Makefile gốc — xem ghi chú ở đó về lý do bỏ arm64e.
ARCHS = arm64
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OpenCarPlayPrefs

OpenCarPlayPrefs_FILES = OCPPrefsEntry.m
OpenCarPlayPrefs_INSTALL_PATH = /Library/PreferenceBundles
OpenCarPlayPrefs_FRAMEWORKS = Foundation
OpenCarPlayPrefs_CFLAGS = -fobjc-arc -Wall

include $(THEOS_MAKE_PATH)/bundle.mk
