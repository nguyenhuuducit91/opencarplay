# OpenCarPlay — rootless tweak for iOS 18.6.x (arm64e)
# Build:  make clean package
#         make package FINALPACKAGE=1

export THEOS_PACKAGE_SCHEME = rootless

# arm64e.
#
# Process hệ thống trên A12+ là arm64e và dyld từ chối thư viện arm64:
# "incompatible architecture (have 'arm64', need 'arm64e')". Không có đường vòng —
# đánh dấu slice arm64 thành arm64e thì dyld lại báo "bad bind opcode 0x09" vì luật
# đọc binding của arm64e khác.
#
# -fno-ptrauth-*: trình biên dịch không sinh lệnh PAC trong mã của chính nó. Đây KHÔNG
# phải để né một mâu thuẫn ABI như ghi chú cũ nói — linker vẫn sinh __auth_stubs dùng
# braa và dyld vẫn ký con trỏ trong __auth_got (đo được: 82 lệnh braa, pointer_format
# ARM64E), tức binary theo đúng ABI arm64e. Giữ các cờ này vì đó là cấu hình duy nhất
# đã thực sự chạy trên máy; bỏ chúng cần một lần thử có kiểm chứng, không phải suy đoán.
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
OpenCarPlay_LDFLAGS = -Wl,-segalign,4000
OpenCarPlay_LDFLAGS += -Wl,-rpath,/var/jb/Library/Frameworks
OpenCarPlay_LDFLAGS += -Wl,-rpath,/Library/Frameworks

include $(THEOS_MAKE_PATH)/tweak.mk

# Preference bundle — bảng cài đặt trong Settings.
#
# Bật lại ở 0.31.0 sau khi đo lại Mach-O bằng hằng số ĐÚNG. Các bản 0.17–0.30 loại nó
# ra dựa trên hai phép đo sai trong scripts/:
#
#   • LC_DYLD_CHAINED_FIXUPS bị ghi là 0x80000033 — đó là LC_DYLD_EXPORTS_TRIE.
#     Script đọc export trie rồi kết luận "chained fixups rỗng". Đo lại: binary của
#     bundle có 944 byte chained fixups, pointer_format ARM64E, y hệt dylib này.
#   • Số lệnh PAC đếm bằng objdump của Linux, mà objdump không đọc được Mach-O
#     ("file format not recognized") nên luôn trả về 0. Đếm lại bằng cách quét opcode:
#     __auth_stubs của dylib này có 82 lệnh braa. Tức là binary vẫn theo đúng ABI
#     arm64e — dyld ký con trỏ trong __auth_got, auth stub xác thực lại. Không có
#     mâu thuẫn nào cần né.
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

# Sau khi stage: đổi phụ thuộc CydiaSubstrate sang đường dẫn tuyệt đối, rồi chuẩn hoá
# quyền (umask của máy build — thường 002 — để lại bit group-write, không phù hợp cho
# file cài vào hệ thống).
#
# Theos CÓ sinh LC_RPATH (kiểm chứng: dylib mang /var/jb/Library/Frameworks và
# @loader_path/.jbroot/Library/Frameworks), nên @rpath vốn đã resolve được. Đổi sang
# đường tuyệt đối chỉ để bớt một biến số. Sửa Mach-O làm hỏng chữ ký nên phải ký lại.
#
# Phụ thuộc này PHẢI là weak. Bản 0.31.0 bỏ bước làm weak với lý do "Theos có sinh
# LC_RPATH nên @rpath vẫn resolve được" — và làm treo máy người dùng.
#
# Lý lẽ đó trả lời sai câu hỏi. @rpath có resolve được hay không là chuyện thứ yếu;
# chuyện chính là FILE ĐÓ CÓ TỒN TẠI TRÊN MÁY hay không. ElleKit không phải bản cài nào
# cũng đặt CydiaSubstrate.framework ở /var/jb/Library/Frameworks. Khi một phụ thuộc BẮT
# BUỘC không resolve được, dyld giết luôn process đang nạp — SpringBoard chết trước cả
# khi constructor chạy, nên kill switch trong code lẫn kill switch qua cáp USB đều vô
# dụng. Máy chỉ còn đường Safe Mode.
#
# Với weak, dyld để symbol bằng NULL và process vẫn sống. Rủi ro "Logos gọi thẳng vào
# NULL" được chặn bằng OCPHookingRuntimeAvailable() trong Tweak/CarPlayApp/Hooks.xm:
# kiểm tra dlsym trước mọi %init. Tweak mất khả năng hook, máy vẫn dùng được — đó là
# đánh đổi đúng.

# ldid không nằm trong PATH mặc định của make (shell không nạp profile của người dùng).
LDID ?= $(firstword $(wildcard $(HOME)/.local/bin/ldid) \
                    $(wildcard $(THEOS)/toolchain/linux/iphone/bin/ldid) \
                    $(shell command -v ldid 2>/dev/null) ldid)

after-stage::
	@for dylib in `find $(THEOS_STAGING_DIR) -name '*.dylib'`; do \
		echo "  sửa phụ thuộc CydiaSubstrate: $$dylib"; \
		$(THEOS)/toolchain/linux/iphone/bin/install_name_tool -change \
			@rpath/CydiaSubstrate.framework/CydiaSubstrate \
			/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
			$$dylib || exit 1; \
		python3 scripts/weaken_substrate.py $$dylib || exit 1; \
		$(LDID) -S $$dylib || exit 1; \
	done
	@python3 scripts/stamp_version.py $(THEOS_STAGING_DIR)
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
