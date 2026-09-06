# OpenCarPlay — rootless tweak for iOS 18.6.x (arm64e)
# Build:  make clean package
#         make package FINALPACKAGE=1

export THEOS_PACKAGE_SCHEME = rootless

# arm64e, KHÔNG tắt pointer authentication.
#
# Process hệ thống trên A12+ là arm64e và dyld từ chối thư viện arm64:
# "incompatible architecture (have 'arm64', need 'arm64e')". Không có đường vòng —
# đánh dấu slice arm64 thành arm64e thì dyld lại báo "bad bind opcode 0x09" vì luật
# đọc binding của arm64e khác.
#
# VÌ SAO BỎ -fno-ptrauth-* (từ 0.39.0)
#
# Các bản 0.24–0.38 dùng bộ cờ đó, với lý do "clang 13 sinh lệnh PAC không đúng chuẩn
# iOS 18.6". Lý do đó sai, và chính bộ cờ mới là nguyên nhân của cả chuỗi sự cố.
#
# Đo trực tiếp — biên dịch cùng một hàm tạo block trên stack rồi quét opcode:
#
#     có -fno-ptrauth-*   -> __text: braa                          (KHÔNG có pacia)
#     không có cờ         -> __text: pacia, pacibsp, retab, braa
#
# `pacia` chính là lệnh ký con trỏ `invoke` của block. Trên arm64e trường đó khai báo
# __ptrauth(ptrauth_key_function_pointer, true, 0xc0bb) và bên GỌI — libdispatch,
# UIKit, Foundation — xác thực nó. Thiếu `pacia` nghĩa là mọi block và mọi con trỏ hàm
# ta đưa cho hệ thống đều chưa ký, và lần gọi đầu tiên là EXC_BAD_ACCESS ở địa chỉ còn
# nguyên bits chữ ký. Crash report từ máy người dùng xác nhận đúng chữ đó:
#
#     EXC_BAD_ACCESS ... 0x00200001fc76dff8 -> 0x00000001fc76dff8
#     (possible pointer authentication failure)
#     objc_msgSend <- NSClassFromString <- OpenCarPlayPrefs <- findAndRunAllInitializers
#
# GHI CHÚ VỀ PHÉP ĐO CŨ: kết luận "toolchain không ký con trỏ dù có cờ hay không" ở các
# bản trước là sai, do bộ quét opcode trong scripts/macho.py chỉ so khớp PACDA/AUTDA
# (0xDAC10800/0xDAC11800) mà bỏ sót PACIA (0xDAC10000) và PACIZA (0xDAC12000) — đúng
# hai lệnh mà trình biên dịch thật sự dùng. Đã sửa; xem _PAC_OPCODES trong macho.py.
ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES = SpringBoard CarPlay

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OpenCarPlay

OpenCarPlay_FILES  = $(wildcard Tweak/*.xm) $(wildcard Tweak/*.mm)
OpenCarPlay_FILES += $(wildcard Tweak/*/*.xm) $(wildcard Tweak/*/*.mm)
OpenCarPlay_FILES += $(wildcard Core/*.m) $(wildcard Core/*.mm) $(wildcard Core/*.c)
OpenCarPlay_CFLAGS = -fobjc-arc -Wall -Wno-unused-variable -ICore -ITweak/CarPlayApp -ITweak/SpringBoard
OpenCarPlay_FRAMEWORKS = UIKit

# ĐƯỜNG DẪN MÀ ELLEKIT THỰC SỰ ĐỌC.
#
# Theos mặc định cài tweak vào /Library/MobileSubstrate/DynamicLibraries. Trên Dopamine
# + ElleKit, thư mục đó KHÔNG được đọc: injector chỉ quét /var/jb/usr/lib/TweakInject.
#
# Đo trên 66 crash report lấy từ máy người dùng — thống kê thư mục của mọi dylib mà các
# process thực sự nạp:
#
#     20x  /var/jb/usr/lib/TweakInject          (PreferenceLoader.dylib)
#      0x  /var/jb/Library/MobileSubstrate/DynamicLibraries
#
# Hậu quả của việc cài sai chỗ: dylib CHƯA TỪNG được nạp vào process nào. Không có
# /var/mobile/Media/OpenCarPlay/loaded-SpringBoard.txt, không có hook nào chạy, và
# CarPlay không hiện ứng dụng nào — đúng triệu chứng người dùng báo.
#
# Cài vào ĐÚNG MỘT chỗ. Cài cả hai thì nơi nào đọc cả hai sẽ nạp dylib hai lần: lớp
# Objective-C đăng ký trùng, hook cài chồng.
OpenCarPlay_INSTALL_PATH = /usr/lib/TweakInject

# install_name mặc định là @rpath/OpenCarPlay.dylib. Mọi tweak khác trên thiết bị dùng
# đường dẫn tuyệt đối; đặt cho khớp để bớt một biến số khác biệt.
OpenCarPlay_LDFLAGS = -install_name /var/jb/usr/lib/TweakInject/OpenCarPlay.dylib
OpenCarPlay_LDFLAGS += -Wl,-segalign,4000
OpenCarPlay_LDFLAGS += -Wl,-rpath,/var/jb/Library/Frameworks
OpenCarPlay_LDFLAGS += -Wl,-rpath,/Library/Frameworks

include $(THEOS_MAKE_PATH)/tweak.mk

# Công cụ chẩn đoán: gọi dlopen lên chính dylib rồi in dlerror(). Xem Tools/selftest.c.
TOOL_NAME = opencarplay-selftest
opencarplay-selftest_FILES = Tools/selftest.c
opencarplay-selftest_INSTALL_PATH = /usr/bin
opencarplay-selftest_CFLAGS = -Wall

include $(THEOS_MAKE_PATH)/tool.mk

# Preference bundle KHÔNG được đóng gói.
#
# Bảng cài đặt là một file plist thuần trong layout/Library/PreferenceLoader/Preferences/,
# PreferenceLoader tự dựng bằng PLCustomListController của nó. Không có binary nào của ta
# được Settings nạp, nên Settings không thể chết vì ta.
#
# VÌ SAO: bốn bản liên tiếp (0.31–0.34) đóng gói một bundle có lớp khai báo lúc biên dịch
# kế thừa PSListController, và cả bốn đều làm Settings crash khi mở bảng. Bản 0.34 sạch
# theo mọi phép đo tĩnh có được — không block, không phụ thuộc ivar ngoài, initializer
# dạng offset, relative method list, mọi symbol đều bind được — mà vẫn crash. Tức lỗi nằm
# ở khâu NẠP binary, không nằm trong logic của ta, và không có thiết bị thì không đo tiếp
# được. Cấu hình duy nhất từng nạp được (commit 1dc27ee) là bundle không khai báo lớp nào.
#
# Mã nguồn trong Preferences/ được giữ lại để dựng lại khi có Xcode trên macOS, hoặc khi
# lấy được crash log để biết chính xác nó chết ở đâu. Dựng riêng:  cd Preferences && make
#
# SUBPROJECTS += Preferences
# include $(THEOS_MAKE_PATH)/aggregate.mk

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
	@for dylib in `find $(THEOS_STAGING_DIR) -name '*.dylib' -o -path '*/usr/bin/opencarplay-selftest'`; do \
		echo "  sửa phụ thuộc CydiaSubstrate: $$dylib"; \
		$(THEOS)/toolchain/linux/iphone/bin/install_name_tool -change \
			@rpath/CydiaSubstrate.framework/CydiaSubstrate \
			/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
			$$dylib || exit 1; \
		python3 scripts/weaken_substrate.py $$dylib || exit 1; \
		python3 scripts/mark_ptrauth_abi.py $$dylib || exit 1; \
		$(LDID) -S $$dylib || exit 1; \
	done
	@python3 scripts/stamp_version.py $(THEOS_STAGING_DIR)
	@python3 scripts/binary_plist.py $(THEOS_STAGING_DIR)/usr/lib/TweakInject/*.plist
	@find $(THEOS_STAGING_DIR) -type d -exec chmod 755 {} +
	@find $(THEOS_STAGING_DIR) -type f -exec chmod 644 {} +
	@find $(THEOS_STAGING_DIR) -name '*.dylib' -exec chmod 755 {} +
	@find $(THEOS_STAGING_DIR)/usr/bin -type f -exec chmod 755 {} + 2>/dev/null || true
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
