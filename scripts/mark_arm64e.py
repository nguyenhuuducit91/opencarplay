#!/usr/bin/env python3
"""Đánh dấu một slice arm64 là arm64e để dyld chấp nhận nạp vào process arm64e.

VÌ SAO CẦN

Trên iPhone A12 trở lên, các process hệ thống (SpringBoard, Preferences) là arm64e và
dyld từ chối nạp thư viện arm64:

    mach-o file, but is an incompatible architecture (have 'arm64', need 'arm64e')

Nhưng toolchain Linux hiện có (clang 13 + ld64-609) sinh ra arm64e slice không tương
thích pointer authentication của iOS 18.6 — lời gọi Objective-C đầu tiên đã chết với
EXC_BAD_ACCESS ... possible pointer authentication failure.

CÁCH LÀM

Biên dịch code arm64 thuần — trong đó KHÔNG có một lệnh PAC nào, và các con trỏ trong
metadata không được ký — rồi chỉ đổi cpusubtype trong header thành arm64e. CPU arm64e
chạy lệnh arm64 bình thường; điều duy nhất thay đổi là dyld chấp nhận nạp.

Slice giữ nguyên kiểu binding cổ điển (LC_DYLD_INFO_ONLY) chứ không phải chained
fixups, nên dyld không đi vào nhánh ký con trỏ vốn là chỗ hỏng.

ĐÁNH ĐỔI: thư viện không được PAC bảo vệ. Đó là điều chấp nhận được với một tweak, và
là cái giá để nó chạy được khi không có Xcode.

    python3 scripts/mark_arm64e.py <mach-o>

Sau khi chạy phải ký lại (ldid -S).
"""

import struct
import sys
from pathlib import Path

FAT_MAGIC = 0xCAFEBABE
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64_ALL = 0
CPU_SUBTYPE_ARM64E = 2


def patch_mach_header(data: bytearray, offset: int) -> bool:
    magic = struct.unpack_from("<I", data, offset)[0]
    if magic != MH_MAGIC_64:
        return False

    cputype, cpusubtype = struct.unpack_from("<ii", data, offset + 4)
    if cputype != CPU_TYPE_ARM64 or (cpusubtype & 0x00FFFFFF) != CPU_SUBTYPE_ARM64_ALL:
        return False

    struct.pack_into("<i", data, offset + 8, CPU_SUBTYPE_ARM64E)
    return True


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("dùng: mark_arm64e.py <mach-o>")

    path = Path(sys.argv[1])
    data = bytearray(path.read_bytes())
    patched = 0

    if struct.unpack_from(">I", data, 0)[0] == FAT_MAGIC:
        count = struct.unpack_from(">I", data, 4)[0]
        for i in range(count):
            entry = 8 + i * 20
            cputype, cpusubtype, offset, size, align = struct.unpack_from(">iiIII", data, entry)
            if cputype == CPU_TYPE_ARM64 and (cpusubtype & 0x00FFFFFF) == CPU_SUBTYPE_ARM64_ALL:
                struct.pack_into(">i", data, entry + 4, CPU_SUBTYPE_ARM64E)
                if patch_mach_header(data, offset):
                    patched += 1
    else:
        if patch_mach_header(data, 0):
            patched += 1

    if patched == 0:
        print("    (không có slice arm64 nào để đánh dấu)")
        return

    path.write_bytes(bytes(data))
    print(f"    đánh dấu {patched} slice arm64 -> arm64e: {path.name}")


if __name__ == "__main__":
    main()
