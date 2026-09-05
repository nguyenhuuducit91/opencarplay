#!/usr/bin/env python3
"""Đổi phụ thuộc CydiaSubstrate từ bắt buộc sang weak trong một Mach-O.

Vì sao cần: nếu dyld không tìm thấy một phụ thuộc BẮT BUỘC, nó giết luôn process đang
nạp dylib. Với tweak nạp vào SpringBoard, điều đó nghĩa là máy không khởi động được và
mọi kill switch bên trong code đều vô dụng vì constructor chưa từng chạy.

Với phụ thuộc weak, dyld chỉ để các symbol bằng NULL và process vẫn sống. Tweak sẽ mất
khả năng hook, nhưng máy vẫn dùng được — đánh đổi đúng đắn cho một tweak.

    python3 scripts/weaken_substrate.py <mach-o>

Sau khi chạy phải ký lại (ldid -S) vì chữ ký cũ không còn khớp.
"""

import struct
import sys
from pathlib import Path

LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x18
FAT_MAGIC = 0xCAFEBABE
NEEDLE = b"CydiaSubstrate"


def weaken_slice(data: bytearray, base: int) -> int:
    """Trả về số lệnh đã đổi trong một slice bắt đầu tại `base`."""
    ncmds = struct.unpack_from("<I", data, base + 16)[0]
    offset = base + 32
    changed = 0

    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmd == LC_LOAD_DYLIB:
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            name = bytes(data[offset + name_offset:offset + cmdsize]).split(b"\x00")[0]
            if NEEDLE in name:
                struct.pack_into("<I", data, offset, LC_LOAD_WEAK_DYLIB)
                changed += 1
                print(f"    weak: {name.decode(errors='ignore')}")
        offset += cmdsize

    return changed


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("dùng: weaken_substrate.py <mach-o>")

    path = Path(sys.argv[1])
    data = bytearray(path.read_bytes())
    magic = struct.unpack_from(">I", data, 0)[0]

    total = 0
    if magic == FAT_MAGIC:
        count = struct.unpack_from(">I", data, 4)[0]
        for i in range(count):
            _, _, offset, _, _ = struct.unpack_from(">iiIII", data, 8 + i * 20)
            total += weaken_slice(data, offset)
    else:
        total += weaken_slice(data, 0)

    if total == 0:
        print("    (không có phụ thuộc CydiaSubstrate nào để đổi)")
        return

    path.write_bytes(bytes(data))


if __name__ == "__main__":
    main()
