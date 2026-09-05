# OpenCarPlay — bảng cài đặt.
#
# Không link Preferences.framework: bundle không tham chiếu lớp nào của nó lúc biên
# dịch. Xem ghi chú đầu OCPPrefsEntry.m về lý do.

ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OpenCarPlayPrefs

OpenCarPlayPrefs_FILES = OCPPrefsEntry.m
OpenCarPlayPrefs_INSTALL_PATH = /Library/PreferenceBundles
OpenCarPlayPrefs_FRAMEWORKS = Foundation
OpenCarPlayPrefs_CFLAGS = -fobjc-arc -Wall -fno-ptrauth-calls -fno-ptrauth-returns \
                          -fno-ptrauth-indirect-gotos -fno-ptrauth-auth-traps

include $(THEOS_MAKE_PATH)/bundle.mk
