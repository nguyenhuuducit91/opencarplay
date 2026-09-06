#!/usr/bin/env python3
"""Kiểm tra một gói .deb trước khi phát hành.

    python3 scripts/verify_package.py packages/*.deb

Mỗi kiểm tra ứng với một lỗi đã thực sự giao tới tay người dùng. Nhóm quan trọng nhất
không phải Mach-O mà là LIÊN KẾT GIỮA CÁC FILE: tên lớp viết trong plist có tồn tại
trong binary không, mục PreferenceLoader có trỏ tới bundle thật không. Bảng cài đặt
trống suốt nhiều bản chính vì không ai kiểm tra những liên kết đó.
"""

import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macho


# --- Mach-O ------------------------------------------------------------------

def check_macho(path: Path, relative: str) -> list:
    problems = []
    for image in macho.read(path):
        # dyld phân loại slice arm64e theo bit CPU_SUBTYPE_PTRAUTH_ABI. Thiếu bit đó,
        # dyld từ chối nạp và với tweak thì thất bại hoàn toàn im lặng: injector gọi
        # dlopen, nhận NULL, bỏ qua. Đo trên thiết bị: Cephei và PreferenceLoader —
        # hai tweak nạp được — đều có 0x80000002; bản 0.30-0.42 của ta có 0x2 và chưa
        # từng được nạp lần nào.
        if image.arch == "arm64e" and not (image.cpusubtype & 0x80000000):
            problems.append(
                f"{relative}: arm64e nhưng thiếu cờ CPU_SUBTYPE_PTRAUTH_ABI "
                f"(cpusubtype={image.cpusubtype & 0xFFFFFFFF:#x}, cần {0x80000002:#x}). "
                f"dyld sẽ từ chối nạp và injector bỏ qua trong im lặng. "
                f"Chạy scripts/mark_ptrauth_abi.py rồi ký lại.")

        if image.arch != "arm64e":
            problems.append(f"{relative}: {image.arch}, không phải arm64e — "
                            f"dyld sẽ báo incompatible architecture")
        if image.classic_binding:
            problems.append(f"{relative}: dùng binding cổ điển (LC_DYLD_INFO_ONLY) — "
                            f"arm64e không đọc được, dyld báo bad bind opcode")
        if not image.chained_fixups or image.chained_fixups[1] == 0:
            problems.append(f"{relative}: chained fixups rỗng — không bind được symbol nào")
        if not image.signed:
            problems.append(f"{relative}: chưa ký — dyld từ chối")
        else:
            result = image.code_signature_matches()
            if result is not None and result[0] != result[1]:
                problems.append(
                    f"{relative}: chữ ký KHÔNG khớp nội dung ({result[0]}/{result[1]} trang). "
                    f"Binary bị sửa sau khi ký — kiểm tra thứ tự các bước trong after-stage; "
                    f"ldid phải chạy SAU cùng.")

        for name, weak in image.dylibs:
            if "Substrate" not in name and "ellekit" not in name:
                continue
            if not weak:
                problems.append(
                    f"{relative}: phụ thuộc {name} ở dạng BẮT BUỘC. Nếu file đó không có "
                    f"trên máy người dùng, dyld GIẾT process đang nạp — SpringBoard chết "
                    f"trước khi constructor chạy, nên mọi kill switch đều vô dụng và máy "
                    f"chỉ còn đường Safe Mode. Đây chính là lỗi của bản 0.31.0. "
                    f"Chạy scripts/weaken_substrate.py rồi ký lại.")
            if name.startswith("@rpath/") and not image.rpaths:
                problems.append(f"{relative}: {name} qua @rpath nhưng binary không có "
                                f"LC_RPATH nào")

        # Block trên arm64e: trường `invoke` khai báo
        # __ptrauth(key_function_pointer, true, 0xc0bb) và bên GỌI (libdispatch, UIKit)
        # xác thực nó. Nếu binary tạo block mà mã không có lệnh ký con trỏ (pacia/paciza)
        # thì lần gọi đầu tiên là EXC_BAD_ACCESS ở địa chỉ còn nguyên bits chữ ký.
        #
        # Nguyên nhân duy nhất đã gặp: biên dịch với -fno-ptrauth-calls. Xem ghi chú
        # đầu Makefile.
        if image.uses_blocks() and not image.signs_pointers():
            problems.append(
                f"{relative}: tạo block Objective-C nhưng mã KHÔNG có lệnh ký con trỏ "
                f"(pacia/paciza). Trên arm64e bên gọi sẽ xác thực con trỏ `invoke` và "
                f"process sẽ chết ở địa chỉ còn nguyên bits chữ ký. "
                f"Gần như chắc chắn do -fno-ptrauth-calls — bỏ cờ đó đi.")

        fixups = image.chained_fixups[1] if image.chained_fixups else 0
        print(f"  {relative:58} {image.arch} fixups={fixups} ký={image.signed} "
              f"objc={image.objc_class_count()} pac={sum(image.pac_instructions().values())}")
    return problems


# --- Bảng cài đặt ------------------------------------------------------------

def read_plist(path: Path):
    try:
        return plistlib.loads(path.read_bytes()), None
    except Exception as error:
        return None, str(error)


# Khoá mà Preferences.framework đọc bằng -isEqualToString: hoặc dùng thẳng như NSString.
# Đưa số vào một trong số này thì Settings chết với
#   -[__NSCFNumber isEqualToString:]: unrecognized selector
# và không có gì trong plist gợi ý điều đó. Đây là lỗi đã làm bản 0.35.0 crash: khoá
# autoCaps ghi là <integer>0</integer> thay vì <string>none</string>.
STRING_ONLY_KEYS = {
    "cell", "label", "footerText", "headerDetailText", "defaults", "key", "detail",
    "action", "icon", "placeholder", "autoCaps", "autoCorrection", "keyboard",
    "PostNotification", "id", "staticTextMessage", "cellClass", "pane",
    "customControllerClass", "bundle", "alignment",
}


def check_specifier_types(label: str, items) -> list:
    """Mọi khoá kiểu chuỗi phải thật sự là chuỗi."""
    problems = []
    for index, item in enumerate(items or []):
        if not isinstance(item, dict):
            continue
        for key, value in item.items():
            if key in STRING_ONLY_KEYS and not isinstance(value, str):
                problems.append(
                    f"{label}: items[{index}].{key} = {value!r} ({type(value).__name__}), "
                    f"phải là chuỗi. Preferences so sánh khoá này bằng -isEqualToString:, "
                    f"đưa số vào sẽ làm Settings chết với 'unrecognized selector sent to "
                    f"instance'.")
    return problems


def collect_detail_classes(items) -> set:
    """Mọi tên lớp mà Root.plist yêu cầu Settings dựng."""
    classes = set()
    for item in items or []:
        if not isinstance(item, dict):
            continue
        for key in ("detail", "cellClass", "pane", "customControllerClass"):
            value = item.get(key)
            if isinstance(value, str) and value.startswith("OCP"):
                classes.add(value)
    return classes


def check_preference_bundle(bundle: Path, root: Path) -> list:
    problems = []
    name = bundle.name
    declared = set()

    info, error = read_plist(bundle / "Info.plist") if (bundle / "Info.plist").exists() \
        else (None, "không có file")
    if info is None:
        return [f"{name}/Info.plist: {error}"]

    executable = info.get("CFBundleExecutable")
    if not executable:
        problems.append(f"{name}: Info.plist thiếu CFBundleExecutable")
    elif not (bundle / executable).exists():
        problems.append(f"{name}: Info.plist khai báo {executable} nhưng không có file đó")
    else:
        for image in macho.read(bundle / executable):
            declared |= image.defined_objc_classes()

    principal = info.get("NSPrincipalClass")
    if not principal:
        problems.append(
            f"{name}: Info.plist thiếu NSPrincipalClass. PreferenceLoader gọi "
            f"-[NSBundle principalClass] để lấy lớp điều khiển; thiếu khoá này thì "
            f"Settings hiện trang lỗi 'There was an error loading the preference bundle'.")
    elif declared and principal not in declared:
        problems.append(f"{name}: NSPrincipalClass = {principal} nhưng binary không "
                        f"định nghĩa lớp đó (có: {', '.join(sorted(declared)) or 'không lớp nào'})")

    root_plist = bundle / "Root.plist"
    if not root_plist.exists():
        problems.append(f"{name}: thiếu Root.plist — bảng cài đặt sẽ trống")
        return problems

    data, error = read_plist(root_plist)
    if data is None:
        problems.append(f"{name}/Root.plist: {error}")
        return problems
    items = data.get("items")
    if not items:
        problems.append(f"{name}/Root.plist: không có mục nào trong 'items'")
    problems += check_specifier_types(f"{name}/Root.plist", items)
    for missing in sorted(collect_detail_classes(items) - declared):
        problems.append(f"{name}/Root.plist trỏ tới lớp {missing} nhưng binary không "
                        f"định nghĩa nó — chạm vào dòng đó Settings sẽ không mở được gì")

    return problems


def check_inline_entry(path: Path, data: dict, entry: dict) -> list:
    """Mục PreferenceLoader không có bundle — trang nằm ngay trong file này.

    PreferenceLoader dựng trang bằng PLCustomListController của nó. Không có binary nào
    được nạp, nên bảng không thể làm Settings crash — nhưng bù lại nó phụ thuộc vào một
    quy tắc dễ vi phạm mà không có thông báo lỗi nào, kiểm ở đây.
    """
    problems = []
    title = path.stem

    if entry.get("label") == title:
        problems.append(
            f"{path.name}: entry.label trùng tên file ('{title}'). PreferenceLoader chỉ đặt "
            f"pl_alt_plist_name khi hai giá trị này KHÁC nhau, và chính khoá đó khiến nó đi "
            f"nạp trang. Trùng tên thì bảng hiện ra TRỐNG. Đổi tên file hoặc đổi label.")

    items = data.get("items")
    if not items:
        problems.append(f"{path.name}: không có 'items' ở cấp cao nhất — bảng sẽ trống")
        return problems

    problems += check_specifier_types(path.name, items)
    problems += check_subpage_links(path, items, path.parent)

    for index, item in enumerate(items):
        if not isinstance(item, dict):
            problems.append(f"{path.name}: items[{index}] không phải dictionary")
            continue
        if item.get("detail"):
            problems.append(
                f"{path.name}: items[{index}] khai báo detail = {item['detail']}, nhưng gói "
                f"không có binary nào định nghĩa lớp đó — chạm vào dòng đó sẽ không mở "
                f"được gì")
        if item.get("action"):
            problems.append(
                f"{path.name}: items[{index}] khai báo action = {item['action']}, nhưng "
                f"không có mã nào chạy để nhận. Nút sẽ không làm gì.")
        if "key" in item and not item.get("defaults"):
            problems.append(f"{path.name}: items[{index}] có 'key' nhưng thiếu 'defaults' — "
                            f"giá trị sẽ không được lưu ở đâu cả")

    icon = entry.get("icon")
    if icon and not (path.parent / icon).exists():
        problems.append(f"{path.name}: icon '{icon}' không có cạnh file này")
    return problems


def check_subpage_links(path: Path, items, directory: Path) -> list:
    """Mọi PSLinkCell dùng pl_alt_plist_name phải trỏ tới một file có thật.

    Trang con nạp theo TÊN từ cùng thư mục. Sai tên thì PreferenceLoader hiện
    "There appears to be an error with these preferences" — không có gì trong plist
    gợi ý nguyên nhân.
    """
    problems = []
    for index, item in enumerate(items or []):
        if not isinstance(item, dict) or item.get("cell") != "PSLinkCell":
            continue
        name = item.get("pl_alt_plist_name")
        if not name:
            if not item.get("detail") and not item.get("bundle"):
                problems.append(f"{path.name}: items[{index}] là PSLinkCell nhưng không có "
                                f"pl_alt_plist_name, detail hay bundle — chạm vào sẽ không "
                                f"mở được gì")
            continue

        target = directory / f"{name}.plist"
        if not target.exists():
            problems.append(f"{path.name}: items[{index}] trỏ tới trang con '{name}' nhưng "
                            f"không có {target.name} cạnh nó")
            continue

        data, error = read_plist(target)
        if data is None:
            problems.append(f"{target.name}: {error}")
            continue
        if "entry" in data:
            problems.append(f"{target.name}: trang con KHÔNG được có khoá 'entry' — có nó "
                            f"thì PreferenceLoader tạo thêm một dòng thừa ở gốc Cài đặt")
        if not data.get("items"):
            problems.append(f"{target.name}: không có 'items' — trang con sẽ trống")
        problems += check_specifier_types(target.name, data.get("items"))
    return problems


def check_preference_loader_entries(root: Path, bundles: list) -> list:
    problems = []
    entries = list(root.rglob("Library/PreferenceLoader/Preferences/*.plist"))
    # Trang con không có 'entry'; chúng được kiểm qua liên kết từ trang chính.
    entries = [p for p in entries
               if isinstance(read_plist(p)[0], dict) and "entry" in read_plist(p)[0]]

    if not entries:
        return ["gói không có mục nào trong Library/PreferenceLoader/Preferences — "
                "sẽ không có OpenCarPlay trong Cài đặt"]

    for path in entries:
        data, error = read_plist(path)
        if data is None:
            problems.append(f"{path.name}: {error}")
            continue

        entry = data.get("entry")
        if not isinstance(entry, dict):
            problems.append(f"{path.name}: thiếu khoá 'entry'")
            continue
        if not entry.get("label"):
            problems.append(f"{path.name}: entry thiếu 'label' — dòng trong Settings không có tên")

        bundle_name = entry.get("bundle")
        if not bundle_name:
            problems += check_inline_entry(path, data, entry)
            continue

        target = next((b for b in bundles if b.name == f"{bundle_name}.bundle"), None)
        if target is None:
            problems.append(f"{path.name}: entry trỏ tới bundle {bundle_name} nhưng gói "
                            f"không chứa /Library/PreferenceBundles/{bundle_name}.bundle")
            continue

        icon = entry.get("icon")
        if icon and not (target / icon).exists():
            problems.append(f"{path.name}: icon '{icon}' không có trong {target.name}")

        if entry.get("isController"):
            info, _ = read_plist(target / "Info.plist")
            executable = (info or {}).get("CFBundleExecutable")
            if not executable or not (target / executable).exists():
                problems.append(
                    f"{path.name}: isController = true nhưng {target.name} không có binary "
                    f"nạp được. PreferenceLoader kiểm tra [bundle isLoaded] sau khi "
                    f"lazyLoadBundle: và thay bằng trang lỗi nếu bundle không nạp.")
                continue
            declared = set()
            for image in macho.read(target / executable):
                declared |= image.defined_objc_classes()
            detail = entry.get("detail")
            if detail and detail not in declared:
                problems.append(f"{path.name}: detail = {detail} nhưng {target.name} không "
                                f"định nghĩa lớp đó")
    return problems


# Thư mục mà injector thực sự quét. Trên Dopamine + ElleKit chỉ có TweakInject; đo trên
# 66 crash report lấy từ máy thật, MobileSubstrate/DynamicLibraries không xuất hiện lần
# nào. Cài sai chỗ thì dylib không bao giờ được nạp và tweak im lặng không làm gì —
# không lỗi, không log, không dấu hiệu nào.
INJECTION_DIRS = ("usr/lib/TweakInject", "Library/MobileSubstrate/DynamicLibraries")


def check_tweak_layout(root: Path) -> list:
    problems = []
    dylibs = [p for p in root.rglob("*.dylib") if p.is_file()]
    if not dylibs:
        return ["gói không chứa dylib nào"]

    for dylib in dylibs:
        parent = str(dylib.parent).replace(str(root), "").lstrip("/")
        parent = parent[len("var/jb/"):] if parent.startswith("var/jb/") else parent
        if parent not in INJECTION_DIRS:
            problems.append(
                f"{dylib.name}: cài vào '{parent}', không phải thư mục injector đọc "
                f"({' hoặc '.join(INJECTION_DIRS)}). Tweak sẽ không bao giờ được nạp.")
        elif parent == "Library/MobileSubstrate/DynamicLibraries":
            print(f"  CẢNH BÁO: {dylib.name} cài vào MobileSubstrate/DynamicLibraries — "
                  f"ElleKit trên jailbreak rootless hiện đại chỉ quét usr/lib/TweakInject.")

    if len({p.name for p in dylibs}) != len(dylibs):
        problems.append("cùng một dylib được cài vào nhiều thư mục injector — "
                        "nơi nào đọc cả hai sẽ nạp nó hai lần")

    for dylib in dylibs:
        filter_plist = dylib.with_suffix(".plist")
        if not filter_plist.exists():
            problems.append(f"{dylib.name}: thiếu file filter cùng tên — ElleKit không "
                            f"biết nạp vào process nào")
            continue
        if filter_plist.read_bytes()[:8] != b"bplist00":
            problems.append(
                f"{filter_plist.name}: còn ở dạng XML. Mọi tweak khác trên thiết bị dùng "
                f"plist nhị phân; Theos định tự chuyển nhưng bỏ qua trên máy build Linux "
                f"(dòng Notice 'plist files were not optimized'). Chạy "
                f"scripts/binary_plist.py.")

        data, error = read_plist(filter_plist)
        if data is None:
            problems.append(f"{filter_plist.name}: {error}")
            continue
        bundles = (data.get("Filter") or {}).get("Bundles")
        executables = (data.get("Filter") or {}).get("Executables")
        if not bundles and not executables:
            problems.append(f"{filter_plist.name}: Filter rỗng — dylib sẽ nạp vào MỌI "
                            f"process, hoặc không process nào")
    return problems


# --- Điểm vào ----------------------------------------------------------------

def check_package(deb: str) -> list:
    problems = []
    print(f"\n=== {Path(deb).name} ===")
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["dpkg-deb", "-x", deb, tmp], check=True)
        root = Path(tmp)

        for path in sorted(root.rglob("*")):
            if path.is_file() and macho.is_macho(path):
                problems += check_macho(path, str(path.relative_to(root)))

        bundles = sorted(root.rglob("Library/PreferenceBundles/*.bundle"))
        for bundle in bundles:
            problems += check_preference_bundle(bundle, root)
        problems += check_preference_loader_entries(root, bundles)
        problems += check_tweak_layout(root)

    return problems


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("dùng: verify_package.py <file.deb> [...]")

    problems = []
    for deb in sys.argv[1:]:
        problems += check_package(deb)

    print()
    if problems:
        print("KHÔNG ĐẠT — không phát hành:")
        for problem in problems:
            print(f"  - {problem}")
        sys.exit(1)
    print("ĐẠT — gói an toàn để phát hành")


if __name__ == "__main__":
    main()
