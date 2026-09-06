#!/usr/bin/env python3
"""Bật cờ CPU_SUBTYPE_PTRAUTH_ABI trên các slice arm64e.

    python3 scripts/mark_ptrauth_abi.py <mach-o> [...]

VÌ SAO CẦN

dyld trên iOS hiện đại phân loại slice arm64e theo cpusubtype:

    bit 31 (0x80000000)  CPU_SUBTYPE_PTRAUTH_ABI — "ABI ptrauth có đánh phiên bản"
    bit 24-27            số phiên bản ABI

Binary arm64e KHÔNG có bit 31 bị coi là dùng ABI ptrauth đời cũ, và dyld từ chối nạp.
Với tweak thì thất bại đó hoàn toàn im lặng: injector gọi dlopen, dlopen trả về NULL,
tweak bị bỏ qua — không lỗi, không log, không dấu hiệu nào.

Đo trên chính thiết bị người dùng, hai tweak ElleKit nạp được:

    Cephei            arm64e  cpusubtype = 0x80000002   PTRAUTH_ABI=1  version=0
    PreferenceLoader  arm64e  cpusubtype = 0x80000002   PTRAUTH_ABI=1  version=0
    OpenCarPlay       arm64e  cpusubtype = 0x2          PTRAUTH_ABI=0  <- không nạp được

clang 13 của toolchain Linux không đặt bit này. Đặt sau khi link, rồi PHẢI ký lại vì
sửa header làm hỏng chữ ký cũ.

Chỉ đặt version = 0, đúng bằng giá trị của hai tweak đối chiếu — không đoán số khác.
"""

import struct
import sys
from pathlib import Path

FAT_MAGIC = 0xCAFEBABE
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64E = 2
CPU_SUBTYPE_PTRAUTH_ABI = 0x80000000
SUBTYPE_MASK = 0x00FFFFFF


def needs_flag(cpusubtype: int) -> bool:
    return (cpusubtype & SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E and \
           not (cpusubtype & CPU_SUBTYPE_PTRAUTH_ABI)


def patch(path: Path) -> int:
    data = bytearray(path.read_bytes())
    patched = 0

    if struct.unpack_from(">I", data, 0)[0] == FAT_MAGIC:
        count = struct.unpack_from(">I", data, 4)[0]
        for i in range(count):
            entry = 8 + i * 20
            cputype, cpusubtype, offset, _, _ = struct.unpack_from(">iiIII", data, entry)
            if cputype != CPU_TYPE_ARM64 or not needs_flag(cpusubtype):
                continue
            struct.pack_into(">I", data, entry + 4, cpusubtype | CPU_SUBTYPE_PTRAUTH_ABI)
            patched += patch_header(data, offset)
    else:
        patched += patch_header(data, 0)

    if patched:
        path.write_bytes(bytes(data))
    return patched


def patch_header(data: bytearray, offset: int) -> int:
    if struct.unpack_from("<I", data, offset)[0] != MH_MAGIC_64:
        return 0
    cputype, cpusubtype = struct.unpack_from("<ii", data, offset + 4)
    if cputype != CPU_TYPE_ARM64 or not needs_flag(cpusubtype):
        return 0
    struct.pack_into("<I", data, offset + 8, (cpusubtype | CPU_SUBTYPE_PTRAUTH_ABI) & 0xFFFFFFFF)
    return 1


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("dùng: mark_ptrauth_abi.py <mach-o> [...]")
    for argument in sys.argv[1:]:
        path = Path(argument)
        if not path.is_file():
            continue
        if patch(path):
            print(f"    PTRAUTH_ABI: {path.name} -> cpusubtype 0x80000002")


if __name__ == "__main__":
    main()
