# OpenCarPlay — bảng cài đặt.
#
# Subproject không kế thừa ARCHS của Makefile gốc; xem ghi chú ở đó về lý do bỏ arm64e.

ARCHS = arm64
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OpenCarPlayPrefs

OpenCarPlayPrefs_FILES = $(wildcard *.m)
OpenCarPlayPrefs_INSTALL_PATH = /Library/PreferenceBundles
OpenCarPlayPrefs_FRAMEWORKS = UIKit
OpenCarPlayPrefs_PRIVATE_FRAMEWORKS = Preferences
OpenCarPlayPrefs_CFLAGS = -fobjc-arc -Wall

include $(THEOS_MAKE_PATH)/bundle.mk
