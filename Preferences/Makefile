# OpenCarPlay — preference bundle cho Settings (qua PreferenceLoader).

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OpenCarPlayPrefs

OpenCarPlayPrefs_FILES = $(wildcard *.m)
OpenCarPlayPrefs_INSTALL_PATH = /Library/PreferenceBundles
OpenCarPlayPrefs_FRAMEWORKS = UIKit
OpenCarPlayPrefs_PRIVATE_FRAMEWORKS = Preferences
OpenCarPlayPrefs_CFLAGS = -fobjc-arc -Wall

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/OpenCarPlay.plist$(ECHO_END)
