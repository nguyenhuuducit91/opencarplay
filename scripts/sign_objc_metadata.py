#!/usr/bin/env python3
"""Ký con trỏ isa/superclass trong metadata lớp Objective-C (arm64e).

    python3 scripts/sign_objc_metadata.py <mach-o> [...]

VÌ SAO CẦN

clang 13 của toolchain Linux không sinh con trỏ đã ký cho metadata lớp Objective-C.
Apple clang có -fptrauth-objc-isa / -fptrauth-objc-class-ro; clang này chỉ có
-fptrauth-calls/-returns/-intrinsics/-indirect-gotos/-auth-traps/-soft.

Hậu quả, đo trên máy thật bằng opencarplay-selftest:

    dlopen(.../OpenCarPlay.dylib): EXC_BREAKPOINT
    libobjc  readClass()  <-  map_images  <-  dlopen_from

libobjc trên arm64e đọc objc_class.isa và .superclass qua trường có __ptrauth. Con trỏ
chưa ký làm lệnh xác thực hỏng và sinh brk — process chết ngay trong map_images.

LƯỢC ĐỒ lấy từ Cephei, một tweak ĐANG CHẠY ĐƯỢC trên chính thiết bị đó (không phải từ
tài liệu, không phải suy đoán):

    objc_class + 0   isa          auth  key=DA  diversity=0x6ae1  addrDiv=1
    objc_class + 8   superclass   auth  key=DA  diversity=0xb5ab  addrDiv=1
    objc_class + 16  cache        không ký
    objc_class + 32  bits         không ký

Hai giá trị đó khớp ISA_SIGNING_DISCRIMINATOR và discriminator superclass của objc4.

Chạy SAU khi link, TRƯỚC ldid.
"""

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macho

OBJC_CLASS_SIZE = 40
KEY_DA = 2                      # ptrauth_key_process_independent_data
FIELDS = {0: 0x6AE1, 8: 0xB5AB}  # offset trong objc_class -> diversity


def encode_auth_rebase(target: int, diversity: int, next_: int) -> int:
    if target >> 32:
        raise ValueError(f"target {target:#x} không vừa 32 bit của auth_rebase")
    return (target
            | (diversity << 32)
            | (1 << 48)            # addrDiv
            | (KEY_DA << 49)
            | (next_ << 51)
            | (0 << 62)            # bind = 0
            | (1 << 63))           # auth = 1


def encode_auth_bind(ordinal: int, diversity: int, next_: int) -> int:
    return (ordinal
            | (diversity << 32)
            | (1 << 48)
            | (KEY_DA << 49)
            | (next_ << 51)
            | (1 << 62)
            | (1 << 63))


def convert(value: int, diversity: int) -> int:
    auth = (value >> 63) & 1
    if auth:
        return value                       # đã ký rồi
    bind = (value >> 62) & 1
    next_ = (value >> 51) & 0x7FF

    if bind:
        ordinal = value & 0xFFFF
        addend = (value >> 32) & 0x7FFFF
        if addend:
            raise ValueError("bind có addend khác 0 — không chuyển sang auth_bind được")
        return encode_auth_bind(ordinal, diversity, next_)

    target = value & 0x7FFFFFFFFFF
    high8 = (value >> 43) & 0xFF
    if high8:
        raise ValueError("rebase có high8 khác 0 — không chuyển được")
    return encode_auth_rebase(target, diversity, next_)


def patch(path: Path) -> int:
    data = bytearray(path.read_bytes())
    images = macho.read(path)
    changed = 0

    for image in images:
        if image.arch != "arm64e" or not image.chained_fixups:
            continue
        section = image.sections.get("__DATA,__objc_data")
        if not section:
            continue
        sect_addr, sect_size, _ = section

        base = image.offset + image.chained_fixups[0]
        header = struct.unpack_from("<7I", data, base)
        starts = base + header[1]
        seg_count = struct.unpack_from("<I", data, starts)[0]

        for i in range(seg_count):
            info = struct.unpack_from("<I", data, starts + 4 + i * 4)[0]
            if info == 0:
                continue
            b = starts + info
            _, page_size, ptr_format, seg_offset, _, page_count = \
                struct.unpack_from("<IHHQIH", data, b)
            if ptr_format != 1:               # chỉ DYLD_CHAINED_PTR_ARM64E
                continue
            seg_fileoff = next((fo for nm, va, vs, fo in image.segments
                                if va == seg_offset), None)
            if seg_fileoff is None:
                continue
            page_starts = struct.unpack_from(f"<{page_count}H", data, b + 22)

            for page_index, page_start in enumerate(page_starts):
                if page_start == 0xFFFF:
                    continue
                address = seg_offset + page_index * page_size + page_start
                while True:
                    file_offset = image.offset + seg_fileoff + (address - seg_offset)
                    value = struct.unpack_from("<Q", data, file_offset)[0]
                    next_ = (value >> 51) & 0x7FF

                    if sect_addr <= address < sect_addr + sect_size:
                        diversity = FIELDS.get((address - sect_addr) % OBJC_CLASS_SIZE)
                        if diversity is not None:
                            new = convert(value, diversity)
                            if new != value:
                                struct.pack_into("<Q", data, file_offset, new)
                                changed += 1

                    if next_ == 0:
                        break
                    address += next_ * 8

    if changed:
        path.write_bytes(bytes(data))
        print(f"    ký metadata ObjC: {path.name} — {changed} con trỏ isa/superclass")
    return changed


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("dùng: sign_objc_metadata.py <mach-o> [...]")
    for argument in sys.argv[1:]:
        path = Path(argument)
        if path.is_file():
            patch(path)


if __name__ == "__main__":
    main()
