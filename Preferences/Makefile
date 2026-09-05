# OpenCarPlay — bảng cài đặt.
#
# Bundle này cố tình KHÔNG định nghĩa lớp Objective-C nào ở thời điểm biên dịch; xem
# ghi chú đầu OCPPrefsEntry.m. Vì vậy nó cũng không cần link Preferences.framework:
# PSListController được tra cứu qua NSClassFromString lúc chạy.

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OpenCarPlayPrefs

OpenCarPlayPrefs_FILES = OCPPrefsEntry.m
OpenCarPlayPrefs_INSTALL_PATH = /Library/PreferenceBundles
OpenCarPlayPrefs_FRAMEWORKS = Foundation
OpenCarPlayPrefs_CFLAGS = -fobjc-arc -Wall

include $(THEOS_MAKE_PATH)/bundle.mk
