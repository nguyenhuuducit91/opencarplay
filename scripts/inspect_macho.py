#!/usr/bin/env python3
"""Kiểm tra một Mach-O có nạp được vào process arm64e trên iOS 18 hay không.

    python3 scripts/inspect_macho.py <mach-o> [...]

Điều kiện, mỗi cái ứng với một lỗi đã gặp thật trên máy:

  1. cpusubtype = arm64e   | nếu không: incompatible architecture
  2. chained fixups có dữ liệu, không phải binding cổ điển
                           | classic: bad bind opcode 0x09
  3. có chữ ký             | thiếu: dyld từ chối

Số lệnh PAC và pointer_format được IN RA nhưng không dùng để đánh trượt. Bản trước
đánh trượt theo chúng và đó là sai lầm: pointer_format ARM64E cùng với __auth_stubs
dùng braa chính là ABI arm64e ĐÚNG — dyld ký con trỏ trong __auth_got, auth stub xác
thực lại. Xem ghi chú đầu scripts/macho.py.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macho


def check(path: Path) -> bool:
    ok = True
    print(f"\n=== {path.name} ===")

    for image in macho.read(path):
        formats = image.pointer_formats()
        pac = image.pac_instructions()

        print(f"  kiến trúc     : {image.arch} (cpusubtype={image.cpusubtype})")
        if image.chained_fixups:
            print(f"  binding       : chained fixups, {image.chained_fixups[1]} byte")
        elif image.classic_binding:
            print(f"  binding       : cổ điển (LC_DYLD_INFO_ONLY)")
        else:
            print(f"  binding       : (không có)")
        for name, fmt in formats:
            label = macho.POINTER_FORMATS.get(fmt, (f"unknown({fmt})", None))[0]
            print(f"  pointer_format: {name} -> {label}")
        print(f"  lệnh PAC      : {pac or 'không có'}")
        print(f"  lớp ObjC      : {image.objc_class_count()}")
        print(f"  đã ký         : {image.signed}")
        for name, weak in image.dylibs:
            if "Substrate" in name or "ellekit" in name:
                print(f"  hooking       : {name} ({'weak' if weak else 'bắt buộc'})")

        if image.arch != "arm64e":
            print("  KHÔNG ĐẠT: dyld sẽ từ chối — cần arm64e")
            ok = False
        if image.classic_binding:
            print("  KHÔNG ĐẠT: arm64e không đọc được binding cổ điển (bad bind opcode)")
            ok = False
        if not image.chained_fixups or image.chained_fixups[1] == 0:
            print("  KHÔNG ĐẠT: thiếu chained fixups — binary không bind được symbol nào")
            ok = False
        if not image.signed:
            print("  KHÔNG ĐẠT: thiếu chữ ký")
            ok = False

    return ok


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("dùng: inspect_macho.py <mach-o> [...]")

    all_ok = True
    for arg in sys.argv[1:]:
        all_ok &= check(Path(arg))

    print("\n" + ("TẤT CẢ ĐẠT" if all_ok else "CÓ MỤC KHÔNG ĐẠT"))
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
