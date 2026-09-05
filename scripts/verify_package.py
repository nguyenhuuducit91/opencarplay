#!/usr/bin/env python3
"""Kiểm tra mọi Mach-O trong gói .deb trước khi phát hành.

Sinh ra sau khi tám bản liên tiếp được giao mà không bản nào chạy. Mỗi kiểm tra dưới
đây ứng với một lỗi đã gặp thật trên máy người dùng:

  cpusubtype = arm64e     | thiếu -> incompatible architecture (have arm64, need arm64e)
  chained fixups có data  | rỗng  -> readClass() chết, dlopen thất bại
                                     (ld64-609 sinh fixups RỖNG cho binary quá nhỏ)
  không có lệnh PAC       | có    -> possible pointer authentication failure
  có chữ ký               | thiếu -> dyld từ chối
  CydiaSubstrate là weak  | bắt buộc -> dyld giết process nếu không tìm thấy

    python3 scripts/verify_package.py packages/*.deb
"""

import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

LC_DYLD_CHAINED_FIXUPS = 0x80000033
LC_DYLD_INFO_ONLY = 0x80000022
LC_CODE_SIGNATURE = 0x1D
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x18


def slices(data: bytes):
    if struct.unpack_from(">I", data, 0)[0] == 0xCAFEBABE:
        for i in range(struct.unpack_from(">I", data, 4)[0]):
            _, _, offset, _, _ = struct.unpack_from(">iiIII", data, 8 + i * 20)
            yield offset
    else:
        yield 0


def pac_count(path: Path) -> int:
    for tool in ("objdump", "llvm-objdump"):
        try:
            out = subprocess.run([tool, "-d", "--arch-name=aarch64", str(path)],
                                 capture_output=True, text=True, timeout=180).stdout
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
        return len(re.findall(r"\b(pac[a-z]+|aut[a-z]+|retab|blraa|braa)\b", out))
    return -1


def check_macho(path: Path) -> list:
    problems = []
    data = path.read_bytes()

    for offset in slices(data):
        cpusubtype = struct.unpack_from("<i", data, offset + 8)[0]
        if (cpusubtype & 0xFFFFFF) != 2:
            problems.append(f"{path.name}: không phải arm64e (cpusubtype={cpusubtype})")

        ncmds = struct.unpack_from("<I", data, offset + 16)[0]
        p = offset + 32
        fixups_size = None
        classic = False
        signed = False
        substrate = None

        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", data, p)
            if cmd == LC_DYLD_CHAINED_FIXUPS:
                fixups_size = struct.unpack_from("<I", data, p + 12)[0]
            elif cmd == LC_DYLD_INFO_ONLY:
                classic = True
            elif cmd == LC_CODE_SIGNATURE:
                signed = True
            elif cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
                name_offset = struct.unpack_from("<I", data, p + 8)[0]
                name = data[p + name_offset:p + cmdsize].split(b"\x00")[0].decode(errors="ignore")
                if "Substrate" in name:
                    substrate = (cmd == LC_LOAD_WEAK_DYLIB, name)
            p += cmdsize

        if fixups_size is None:
            problems.append(f"{path.name}: không có chained fixups"
                            + (" (dùng binding cổ điển — arm64e không đọc được)" if classic else ""))
        elif fixups_size == 0:
            problems.append(f"{path.name}: chained fixups RỖNG — binary không bind được symbol nào. "
                            f"ld64 sinh ra thế này khi binary quá nhỏ; thêm nội dung hoặc đổi linker.")

        if not signed:
            problems.append(f"{path.name}: chưa ký")

        if substrate is not None and not substrate[0]:
            problems.append(f"{path.name}: phụ thuộc CydiaSubstrate ở dạng BẮT BUỘC — "
                            f"dyld sẽ giết process nếu không tìm thấy")

        count = pac_count(path)
        if count > 0:
            problems.append(f"{path.name}: có {count} lệnh PAC — iOS 18.6 sẽ báo "
                            f"pointer authentication failure")

        size = len(data) if offset == 0 else None
        detail = f"fixups={fixups_size} ký={signed} PAC={count}"
        if substrate: detail += f" substrate={'weak' if substrate[0] else 'BẮT BUỘC'}"
        if size: detail += f" size={size}"
        print(f"  {path.name:24} arm64e  {detail}")

    return problems


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("dùng: verify_package.py <file.deb> [...]")

    all_problems = []
    for deb in sys.argv[1:]:
        print(f"\n=== {Path(deb).name} ===")
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["dpkg-deb", "-x", deb, tmp], check=True)
            for path in sorted(Path(tmp).rglob("*")):
                if not path.is_file():
                    continue
                head = path.read_bytes()[:4]
                if head in (b"\xca\xfe\xba\xbe", b"\xcf\xfa\xed\xfe"):
                    all_problems += check_macho(path)

    print()
    if all_problems:
        print("KHÔNG ĐẠT — không phát hành:")
        for problem in all_problems:
            print(f"  - {problem}")
        sys.exit(1)

    print("ĐẠT — gói an toàn để phát hành")


if __name__ == "__main__":
    main()
