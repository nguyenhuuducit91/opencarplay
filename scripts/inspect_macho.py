#!/usr/bin/env python3
"""Kiểm tra một Mach-O có nạp được vào process arm64e trên iOS 18 hay không.

Ba điều kiện phải thoả cùng lúc — mỗi cái ứng với một lỗi đã gặp thật trên máy:

  1. cpusubtype = arm64e          | nếu không: incompatible architecture
  2. không có lệnh PAC trong code | nếu có   : possible pointer authentication failure
  3. chained fixups, và pointer_format KHÔNG phải loại ARM64E
                                  | classic  : bad bind opcode 0x09
                                  | ARM64E   : dyld ký con trỏ mà code không xác thực

Điều kiện 3 là chỗ tinh tế: dyld quyết định có ký con trỏ hay không dựa trên
pointer_format ghi trong chính binary, không phải dựa trên cpusubtype. Nên một binary
đánh dấu arm64e nhưng khai báo pointer_format = PTR_64 sẽ được nạp mà con trỏ không bị
ký — đúng thứ mã arm64 không-PAC cần.

    python3 scripts/inspect_macho.py <mach-o> [...]
"""

import struct
import subprocess
import sys
from pathlib import Path

FAT_MAGIC = 0xCAFEBABE
LC_DYLD_INFO_ONLY = 0x80000022
LC_DYLD_CHAINED_FIXUPS = 0x80000033
LC_CODE_SIGNATURE = 0x1D

POINTER_FORMATS = {
    1: ("ARM64E", True), 2: ("PTR_64", False), 3: ("PTR_32", False),
    4: ("PTR_32_CACHE", False), 5: ("PTR_32_FIRMWARE", False),
    6: ("PTR_64_OFFSET", False), 7: ("ARM64E_KERNEL", True),
    8: ("ARM64E_USERLAND", True), 9: ("ARM64E_FIRMWARE", True),
    10: ("X86_64_KERNEL_CACHE", False), 11: ("ARM64E_USERLAND24", True),
}


def slices(data: bytes):
    if struct.unpack_from(">I", data, 0)[0] == FAT_MAGIC:
        count = struct.unpack_from(">I", data, 4)[0]
        for i in range(count):
            _, _, offset, size, _ = struct.unpack_from(">iiIII", data, 8 + i * 20)
            yield offset
    else:
        yield 0


def pointer_format(data: bytes, slice_off: int, fixups_off: int):
    base = slice_off + fixups_off
    starts_offset = struct.unpack_from("<I", data, base + 4)[0]
    starts = base + starts_offset
    seg_count = struct.unpack_from("<I", data, starts)[0]

    for i in range(seg_count):
        seg_info = struct.unpack_from("<I", data, starts + 4 + i * 4)[0]
        if seg_info == 0:
            continue
        fmt = struct.unpack_from("<H", data, starts + seg_info + 6)[0]
        return fmt
    return None


def pac_instruction_count(path: Path) -> str:
    for tool in ("objdump", "llvm-objdump"):
        try:
            out = subprocess.run(
                [tool, "-d", "--arch-name=aarch64", str(path)],
                capture_output=True, text=True, timeout=120).stdout
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
        import re
        return str(len(re.findall(r"\b(pac[a-z]+|aut[a-z]+|retab|blraa|braa)\b", out)))
    return "?"


def check(path: Path) -> bool:
    data = path.read_bytes()
    ok = True
    print(f"\n=== {path.name} ===")

    for slice_off in slices(data):
        cputype, cpusubtype = struct.unpack_from("<ii", data, slice_off + 4)
        arch = "arm64e" if (cpusubtype & 0xFFFFFF) == 2 else "arm64"

        ncmds = struct.unpack_from("<I", data, slice_off + 16)[0]
        p = slice_off + 32
        binding = "(không có)"
        fmt_note = ""
        signed = False

        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", data, p)
            if cmd == LC_DYLD_INFO_ONLY:
                binding = "classic (LC_DYLD_INFO_ONLY)"
            elif cmd == LC_DYLD_CHAINED_FIXUPS:
                dataoff = struct.unpack_from("<I", data, p + 8)[0]
                binding = "chained fixups"
                try:
                    fmt = pointer_format(data, slice_off, dataoff)
                    name, signs = POINTER_FORMATS.get(fmt, (f"unknown({fmt})", True))
                    fmt_note = f" pointer_format={name}"
                    if signs:
                        fmt_note += "  <-- dyld sẽ KÝ con trỏ"
                except Exception as error:
                    fmt_note = f" (không đọc được format: {error})"
            elif cmd == LC_CODE_SIGNATURE:
                signed = True
            p += cmdsize

        pac = pac_instruction_count(path)
        print(f"  kiến trúc     : {arch} (cpusubtype={cpusubtype})")
        print(f"  binding       : {binding}{fmt_note}")
        print(f"  lệnh PAC      : {pac}")
        print(f"  đã ký         : {signed}")

        if arch != "arm64e":
            print("  KHÔNG ĐẠT: dyld sẽ từ chối — cần arm64e")
            ok = False
        if binding.startswith("classic"):
            print("  KHÔNG ĐẠT: arm64e không đọc được binding cổ điển (bad bind opcode)")
            ok = False
        if "sẽ KÝ con trỏ" in fmt_note and pac == "0":
            print("  KHÔNG ĐẠT: dyld ký con trỏ nhưng mã không xác thực -> PAC failure")
            ok = False
        if pac not in ("0", "?") and "sẽ KÝ" not in fmt_note:
            print("  NGHI NGỜ: có lệnh PAC nhưng con trỏ không được ký")
            ok = False
        if not signed:
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
