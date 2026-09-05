# OpenCarPlay — rootless tweak for iOS 18.6.x (arm64e)
# Build:  make clean package
#         make package FINALPACKAGE=1

export THEOS_PACKAGE_SCHEME = rootless

# arm64e, nhưng KHÔNG sinh lệnh pointer authentication.
#
# Ba ràng buộc phải thoả cùng lúc, tìm ra qua bốn lần thử trên máy thật:
#
#   1. Phải là arm64e. Process hệ thống trên A12+ là arm64e và dyld từ chối thư viện
#      arm64: "incompatible architecture (have 'arm64', need 'arm64e')".
#   2. Không được chứa lệnh PAC. Toolchain Linux (clang 13 + ld64-609) sinh ra lệnh
#      xác thực con trỏ mà iOS 18.6 từ chối: lời gọi Objective-C đầu tiên đã chết với
#      "possible pointer authentication failure".
#   3. Phải dùng chained fixups. Đánh dấu binary arm64 thành arm64e mà giữ binding cổ
#      điển thì dyld báo "bad bind opcode 0x09" — luật đọc bind của arm64e khác.
#
# -fno-ptrauth-* thoả cả ba: binary vẫn là arm64e đúng định dạng (dyld xử lý bình
# thường, chained fixups đúng loại), nhưng trình biên dịch không phát sinh lệnh PAC nào.
#
# ĐÁNH ĐỔI: thư viện không được PAC bảo vệ. Có Xcode trên macOS thì bỏ các cờ này.
ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES = SpringBoard CarPlay

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OpenCarPlay

OpenCarPlay_FILES  = $(wildcard Tweak/*.xm) $(wildcard Tweak/*.mm)
OpenCarPlay_FILES += $(wildcard Tweak/*/*.xm) $(wildcard Tweak/*/*.mm)
OpenCarPlay_FILES += $(wildcard Core/*.m) $(wildcard Core/*.mm) $(wildcard Core/*.c)
OpenCarPlay_CFLAGS = -fobjc-arc -Wall -Wno-unused-variable -ICore -ITweak/CarPlayApp -ITweak/SpringBoard
OpenCarPlay_CFLAGS += -fno-ptrauth-calls -fno-ptrauth-returns -fno-ptrauth-indirect-gotos -fno-ptrauth-auth-traps
OpenCarPlay_FRAMEWORKS = UIKit
# CydiaSubstrate được Theos liên kết qua @rpath khi dùng scheme rootless, nhưng nó
# KHÔNG sinh LC_RPATH tương ứng. Hậu quả: dyld không resolve được phụ thuộc bắt buộc
# này và GIẾT process đang nạp dylib — SpringBoard chết trước cả khi constructor chạy,
# nên mọi kill switch bên trong code đều vô dụng. Đây là nguyên nhân của ba lần treo máy.
OpenCarPlay_LDFLAGS = -Wl,-segalign,4000
OpenCarPlay_LDFLAGS += -Wl,-rpath,/var/jb/Library/Frameworks
OpenCarPlay_LDFLAGS += -Wl,-rpath,/Library/Frameworks

include $(THEOS_MAKE_PATH)/tweak.mk

# Preference bundle: xem Preferences/Makefile.
#
# GHI CHÚ CŨ (giữ lại vì lý do vẫn còn giá trị):
#
# ld64-609 của toolchain Linux sinh ra LC_DYLD_CHAINED_FIXUPS RỖNG (datasize = 0) cho
# binary của bundle, trong khi dylib chính lại có dữ liệu hợp lệ (1440 byte). Binary với
# chained fixups rỗng không bind được gì, nên Settings chết ngay khi dlopen nó — dù bundle
# không khai báo lớp nào, dù đã tắt sinh lệnh PAC.
#
# Bỏ bundle ra khỏi gói để phần còn lại có cơ hội chạy. Cấu hình dùng file plist trực tiếp.
# Muốn có lại bảng cài đặt thì cần toolchain sinh được chained fixups hợp lệ — thực tế là
# Xcode trên macOS.
#
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

# Chuẩn hoá quyền trước khi đóng gói: umask của máy build (thường 002) để lại bit
# group-write, không phù hợp cho file cài vào hệ thống.
# Sửa phụ thuộc CydiaSubstrate.
#
# Theos scheme rootless liên kết CydiaSubstrate qua @rpath nhưng không sinh LC_RPATH,
# và LDFLAGS không chèn được vào (Theos dựng lệnh link theo cách riêng). Kết quả là một
# phụ thuộc BẮT BUỘC không resolve được: dyld giết luôn process đang nạp dylib, tức
# SpringBoard chết trước cả khi constructor chạy — mọi kill switch trong code đều vô dụng.
#
# Đổi sang đường dẫn tuyệt đối của jailbreak rootless rồi ký lại, vì sửa Mach-O làm
# hỏng chữ ký cũ.
after-stage::
	@for dylib in `find $(THEOS_STAGING_DIR) -name '*.dylib'`; do \
		echo "  sửa phụ thuộc CydiaSubstrate: $$dylib"; \
		$(THEOS)/toolchain/linux/iphone/bin/install_name_tool -change \
			@rpath/CydiaSubstrate.framework/CydiaSubstrate \
			/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
			$$dylib || exit 1; \
		python3 scripts/weaken_substrate.py $$dylib || exit 1; \
		ldid -S $$dylib || exit 1; \
	done
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
	@$(MAKE) verify
	@$(MAKE) repo

# Kiểm tra gói trước khi phát hành. Sinh ra sau khi tám bản liên tiếp được giao mà
# không bản nào chạy — mỗi kiểm tra trong script ứng với một lỗi đã gặp thật.
verify::
	@PATH=$(THEOS)/toolchain/linux/iphone/bin:$$PATH \
		python3 scripts/verify_package.py `ls -t packages/*.deb | head -1`
