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
    for missing in sorted(collect_detail_classes(items) - declared):
        problems.append(f"{name}/Root.plist trỏ tới lớp {missing} nhưng binary không "
                        f"định nghĩa nó — chạm vào dòng đó Settings sẽ không mở được gì")

    return problems


def check_preference_loader_entries(root: Path, bundles: list) -> list:
    problems = []
    entries = list(root.rglob("Library/PreferenceLoader/Preferences/*.plist"))

    if bundles and not entries:
        return ["có preference bundle nhưng thiếu mục trong "
                "Library/PreferenceLoader/Preferences — Settings sẽ không hiện gì. "
                "Đây chính là lý do 'không thấy OpenCarPlay trong Cài đặt'."]

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


def check_tweak_layout(root: Path) -> list:
    problems = []
    dylibs = list(root.rglob("Library/MobileSubstrate/DynamicLibraries/*.dylib"))
    if not dylibs:
        return ["gói không chứa dylib nào trong Library/MobileSubstrate/DynamicLibraries"]

    for dylib in dylibs:
        filter_plist = dylib.with_suffix(".plist")
        if not filter_plist.exists():
            problems.append(f"{dylib.name}: thiếu file filter cùng tên — ElleKit không "
                            f"biết nạp vào process nào")
            continue
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

        if not bundles:
            problems.append("gói không chứa preference bundle nào — sẽ không có mục "
                            "OpenCarPlay trong Cài đặt")
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
