#!/usr/bin/env python3
"""So sánh dylib của ta với một tweak ĐANG CHẠY ĐƯỢC trên cùng thiết bị.

    python3 scripts/compare_tweak.py ref-Cephei OpenCarPlay.dylib

Sinh ra sau khi hết cách suy luận: dylib nằm đúng thư mục, plist đúng, chữ ký hợp lệ,
kiến trúc đúng, mà ElleKit vẫn bỏ qua. Khi mọi giả thuyết đều sai, thứ còn lại là so
từng thuộc tính với một binary mà chính injector đó nạp được.
"""

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macho

FLAGS = {
    0x1: "NOUNDEFS", 0x4: "DYLDLINK", 0x80: "TWOLEVEL", 0x100: "BINDATLOAD",
    0x1000: "PREBOUND", 0x2000: "SPLIT_SEGS", 0x80000: "WEAK_DEFINES",
    0x100000: "BINDS_TO_WEAK", 0x200000: "ALLOW_STACK_EXECUTION",
    0x800000: "NO_REEXPORTED_DYLIBS", 0x1000000: "PIE",
    0x2000000: "DEAD_STRIPPABLE_DYLIB", 0x4000000: "HAS_TLV_DESCRIPTORS",
    0x8000000: "NO_HEAP_EXECUTION", 0x10000000: "APP_EXTENSION_SAFE",
    0x80000000: "DYLIB_IN_CACHE",
}


def describe(path: Path) -> dict:
    data = path.read_bytes()
    image = macho.read(path)[0]
    magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags = \
        struct.unpack_from("<IiiIIII", data, 0)

    install_name = None
    minos = None
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x0D:
            n = struct.unpack_from("<I", data, off + 8)[0]
            install_name = data[off + n:off + cmdsize].split(b"\x00")[0].decode(errors="replace")
        elif cmd == 0x32:  # LC_BUILD_VERSION
            platform, min_os = struct.unpack_from("<II", data, off + 8)
            minos = f"platform={platform} minos={min_os >> 16}.{(min_os >> 8) & 0xff}"
        off += cmdsize

    return {
        "kích thước": len(data),
        "filetype": {6: "MH_DYLIB", 8: "MH_BUNDLE"}.get(filetype, filetype),
        "cpusubtype": hex(cpusubtype & 0xFFFFFFFF),
        "flags": " ".join(n for b, n in sorted(FLAGS.items()) if flags & b) or hex(flags),
        "install_name": install_name,
        "build": minos,
        "chained fixups": image.chained_fixups[1] if image.chained_fixups else 0,
        "đã ký": image.signed,
        "ký con trỏ": image.signs_pointers(),
        "lớp ObjC": image.objc_class_count(),
        "phụ thuộc": ", ".join(f"{'weak:' if w else ''}{n.split('/')[-1]}" for n, w in image.dylibs),
        "rpath": ", ".join(image.rpaths) or "(không có)",
    }


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("dùng: compare_tweak.py <tweak chạy được> <dylib của ta>")

    left, right = Path(sys.argv[1]), Path(sys.argv[2])
    a, b = describe(left), describe(right)

    width = max(len(k) for k in a)
    print(f"{'':{width}}  {left.name:38}  {right.name}")
    print("-" * (width + 42 + len(right.name)))
    for key in a:
        same = "" if a[key] == b[key] else "  <-- KHÁC"
        print(f"{key:{width}}  {str(a[key])[:38]:38}  {str(b[key])[:38]}{same}")


if __name__ == "__main__":
    main()
