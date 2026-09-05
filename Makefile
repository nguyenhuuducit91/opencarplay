# OpenCarPlay — rootless tweak for iOS 18.6.x (arm64e)
# Build:  make clean package
#         make package FINALPACKAGE=1

export THEOS_PACKAGE_SCHEME = rootless

ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES = SpringBoard CarPlay

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OpenCarPlay

OpenCarPlay_FILES  = $(wildcard Tweak/*.xm) $(wildcard Tweak/*.mm)
OpenCarPlay_FILES += $(wildcard Tweak/*/*.xm) $(wildcard Tweak/*/*.mm)
OpenCarPlay_FILES += $(wildcard Core/*.m) $(wildcard Core/*.mm) $(wildcard Core/*.c)
OpenCarPlay_CFLAGS = -fobjc-arc -Wall -Wno-unused-variable -ICore -ITweak/CarPlayApp -ITweak/SpringBoard
OpenCarPlay_FRAMEWORKS = UIKit
OpenCarPlay_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

# Chuẩn hoá quyền trước khi đóng gói: umask của máy build (thường 002) để lại bit
# group-write, không phù hợp cho file cài vào hệ thống.
after-stage::
	@find $(THEOS_STAGING_DIR) -type d -exec chmod 755 {} +
	@find $(THEOS_STAGING_DIR) -type f -exec chmod 644 {} +
	@find $(THEOS_STAGING_DIR) -name '*.dylib' -exec chmod 755 {} +
	@find $(THEOS_STAGING_DIR) -path '*.bundle/*' -type f ! -name '*.plist' ! -name '*.png' \
		-exec chmod 755 {} +
	@[ -d $(THEOS_STAGING_DIR)/DEBIAN ] && chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/post* || true

# --- APT repository cho Sileo (GitHub Pages) --------------------------------
# Sinh docs/ từ các .deb trong packages/:
#     make package FINALPACKAGE=1 && make repo
REPO_URL ?= https://nguyenhuuducit91.github.io/opencarplay

repo::
	@OCP_REPO_URL=$(REPO_URL) python3 scripts/make_repo.py

# Build và cập nhật repo trong một lệnh — dùng cái này để không quên bước thứ hai.
release::
	@$(MAKE) package FINALPACKAGE=1
	@$(MAKE) repo
