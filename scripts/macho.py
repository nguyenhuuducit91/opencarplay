#!/usr/bin/env python3
"""Đọc Mach-O đủ để trả lời các câu hỏi mà dự án này thực sự cần.

Tồn tại vì hai phép đo sai đã dẫn dắt tám bản phát hành liên tiếp:

  • LC_DYLD_CHAINED_FIXUPS bị viết nhầm là 0x80000033. Hằng số ĐÚNG:
        LC_DYLD_EXPORTS_TRIE   = 0x33 | LC_REQ_DYLD = 0x80000033
        LC_DYLD_CHAINED_FIXUPS = 0x34 | LC_REQ_DYLD = 0x80000034
    Đọc nhầm export trie thành chained fixups cho ra "datasize = 0" và kết luận sai
    rằng ld64 sinh fixups rỗng cho binary nhỏ.

  • Số lệnh PAC đếm bằng `objdump -d`. objdump của Linux KHÔNG đọc được Mach-O
    ("file format not recognized"), stdout rỗng, nên phép đếm luôn ra 0. Ở đây quét
    thẳng opcode trong section, không phụ thuộc công cụ ngoài.
"""

import struct

FAT_MAGIC = 0xCAFEBABE
MH_MAGIC_64 = 0xFEEDFACF

LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x02
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x18
LC_CODE_SIGNATURE = 0x1D
LC_DYLD_INFO_ONLY = 0x80000022
LC_DYLD_EXPORTS_TRIE = 0x80000033
LC_DYLD_CHAINED_FIXUPS = 0x80000034

POINTER_FORMATS = {
    1: ("ARM64E", True), 2: ("PTR_64", False), 3: ("PTR_32", False),
    4: ("PTR_32_CACHE", False), 5: ("PTR_32_FIRMWARE", False),
    6: ("PTR_64_OFFSET", False), 7: ("ARM64E_KERNEL", True),
    8: ("ARM64E_USERLAND", True), 9: ("ARM64E_FIRMWARE", True),
    10: ("X86_64_KERNEL_CACHE", False), 11: ("ARM64E_USERLAND24", True),
}

# Lệnh pointer authentication trên arm64e. Nhóm braa/blraa/brab/blrab có toán hạng
# thanh ghi nên phải so sánh sau khi che 10 bit thấp.
_PAC_EXACT = {
    0xD61F081F: "braaz", 0xD63F081F: "blraaz",
    0xD65F0BFF: "retaa", 0xD65F0FFF: "retab",
    0xD503233F: "paciasp", 0xD50323BF: "autiasp",
    0xD503237F: "pacibsp", 0xD50323FF: "autibsp",
}
_PAC_MASKED = {
    0xD71F0800: "braa", 0xD73F0800: "blraa",
    0xD71F0C00: "brab", 0xD73F0C00: "blrab",
}

# Họ lệnh PAC/AUT dạng "data-processing (1 source)":
#     1101 1010 1100 0001 | opcode2=00001 | opcode(6) | Rn(5) | Rd(5)
# tức 0xDAC10000 | (opcode << 10) | (Rn << 5) | Rd, với opcode 0..17.
#
# Bản trước chỉ so khớp 0xDAC10800 và 0xDAC11800 — đó là PACDA và AUTDA, hai lệnh
# hiếm dùng. PACIA (opcode 0) và PACIZA (opcode 8) — hai lệnh mà trình biên dịch thật
# sự dùng để ký con trỏ hàm — đều bị bỏ sót, nên phép đo "mã không có lệnh ký con trỏ
# nào" là sai.
_PAC_OPCODES = {
    0: "pacia", 1: "pacib", 2: "pacda", 3: "pacdb",
    4: "autia", 5: "autib", 6: "autda", 7: "autdb",
    8: "paciza", 9: "pacizb", 10: "pacdza", 11: "pacdzb",
    12: "autiza", 13: "autizb", 14: "autdza", 15: "autdzb",
    16: "xpaci", 17: "xpacd",
}


def _pac_family(word: int):
    if (word & 0xFFFFC000) != 0xDAC10000:
        return None
    return _PAC_OPCODES.get((word >> 10) & 0x3F)


class MachO:
    def __init__(self, data: bytes, offset: int = 0):
        self.data = data
        self.offset = offset
        magic, self.cputype, self.cpusubtype = struct.unpack_from("<Iii", data, offset)
        if magic != MH_MAGIC_64:
            raise ValueError(f"không phải Mach-O 64-bit (magic={magic:#x})")
        self.ncmds = struct.unpack_from("<I", data, offset + 16)[0]

        self.segments = []          # (name, vmaddr, vmsize, fileoff)
        self.sections = {}          # "SEG,sect" -> (addr, size, fileoff)
        self.dylibs = []            # (name, is_weak)
        self.rpaths = []
        self.chained_fixups = None  # (dataoff, datasize)
        self.exports_trie = None
        self.signed = False
        self.classic_binding = False
        self.symtab = None          # (symoff, nsyms, stroff, strsize)
        self.code_signature = None  # (dataoff, datasize)
        self._parse()

    @property
    def arch(self) -> str:
        if self.cputype != 0x0100000C:
            return f"cputype={self.cputype:#x}"
        return "arm64e" if (self.cpusubtype & 0x00FFFFFF) == 2 else "arm64"

    def _parse(self):
        p = self.offset + 32
        for _ in range(self.ncmds):
            cmd, cmdsize = struct.unpack_from("<II", self.data, p)
            if cmd == LC_SEGMENT_64:
                name = self.data[p + 8:p + 24].split(b"\x00")[0].decode()
                vmaddr, vmsize, fileoff, _ = struct.unpack_from("<QQQQ", self.data, p + 24)
                self.segments.append((name, vmaddr, vmsize, fileoff))
                nsects = struct.unpack_from("<I", self.data, p + 64)[0]
                sp = p + 72
                for _ in range(nsects):
                    sect = self.data[sp:sp + 16].split(b"\x00")[0].decode()
                    addr, size = struct.unpack_from("<QQ", self.data, sp + 32)
                    off = struct.unpack_from("<I", self.data, sp + 48)[0]
                    self.sections[f"{name},{sect}"] = (addr, size, off)
                    sp += 80
            elif cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
                n = struct.unpack_from("<I", self.data, p + 8)[0]
                name = self.data[p + n:p + cmdsize].split(b"\x00")[0].decode(errors="replace")
                self.dylibs.append((name, cmd == LC_LOAD_WEAK_DYLIB))
            elif cmd == 0x8000001C:  # LC_RPATH
                n = struct.unpack_from("<I", self.data, p + 8)[0]
                self.rpaths.append(
                    self.data[p + n:p + cmdsize].split(b"\x00")[0].decode(errors="replace"))
            elif cmd == LC_DYLD_CHAINED_FIXUPS:
                self.chained_fixups = struct.unpack_from("<II", self.data, p + 8)
            elif cmd == LC_DYLD_EXPORTS_TRIE:
                self.exports_trie = struct.unpack_from("<II", self.data, p + 8)
            elif cmd == LC_DYLD_INFO_ONLY:
                self.classic_binding = True
            elif cmd == LC_SYMTAB:
                self.symtab = struct.unpack_from("<IIII", self.data, p + 8)
            elif cmd == LC_CODE_SIGNATURE:
                self.signed = True
                self.code_signature = struct.unpack_from("<II", self.data, p + 8)
            p += cmdsize

    def pointer_formats(self):
        """[(tên segment, mã pointer_format)] — rỗng nếu không có chained fixups."""
        if not self.chained_fixups or self.chained_fixups[1] == 0:
            return []
        base = self.offset + self.chained_fixups[0]
        starts_offset = struct.unpack_from("<I", self.data, base + 4)[0]
        starts = base + starts_offset
        seg_count = struct.unpack_from("<I", self.data, starts)[0]

        result = []
        for i in range(seg_count):
            info = struct.unpack_from("<I", self.data, starts + 4 + i * 4)[0]
            if info == 0:
                continue
            b = starts + info
            _, _, fmt, seg_off = struct.unpack_from("<IHHQ", self.data, b)
            name = next((s[0] for s in self.segments if s[1] == seg_off), f"seg{i}")
            result.append((name, fmt))
        return result

    def pac_instructions(self):
        """{tên lệnh: số lần} trên toàn bộ vùng mã thực thi."""
        found = {}
        for key, (addr, size, off) in self.sections.items():
            if not key.startswith("__TEXT,"):
                continue
            if key.split(",")[1] not in ("__text", "__auth_stubs", "__stubs",
                                         "__stub_helper"):
                continue
            for i in range(0, size - 3, 4):
                word = struct.unpack_from("<I", self.data, self.offset + off + i)[0]
                name = (_PAC_EXACT.get(word) or _PAC_MASKED.get(word & 0xFFFFFC00)
                        or _pac_family(word))
                if name:
                    found[name] = found.get(name, 0) + 1
        return found

    def defined_objc_classes(self) -> set:
        """Tên các lớp Objective-C mà binary này ĐỊNH NGHĨA.

        Dùng để kiểm tra một tên lớp viết trong plist có thật sự tồn tại trong binary
        hay không — đúng loại lỗi đã làm bảng cài đặt trống suốt nhiều bản.
        """
        if not self.symtab:
            return set()
        symoff, nsyms, stroff, strsize = self.symtab
        strings = self.data[self.offset + stroff:self.offset + stroff + strsize]
        result = set()
        for i in range(nsyms):
            base = self.offset + symoff + i * 16
            n_strx, n_type = struct.unpack_from("<IB", self.data, base)
            if (n_type & 0x0E) != 0x0E:      # chỉ symbol định nghĩa trong section
                continue
            end = strings.find(b"\x00", n_strx)
            name = strings[n_strx:end if end >= 0 else None].decode(errors="replace")
            if name.startswith("_OBJC_CLASS_$_"):
                result.add(name[len("_OBJC_CLASS_$_"):])
        return result

    def undefined_symbols(self) -> set:
        """Tên các symbol binary này cần từ nơi khác."""
        if not self.symtab:
            return set()
        symoff, nsyms, stroff, strsize = self.symtab
        strings = self.data[self.offset + stroff:self.offset + stroff + strsize]
        result = set()
        for i in range(nsyms):
            base = self.offset + symoff + i * 16
            n_strx, n_type = struct.unpack_from("<IB", self.data, base)
            # Chỉ symbol NGOÀI thực sự chưa định nghĩa: N_UNDF | N_EXT.
            # ld64 còn sinh bản sao N_PEXT|N_UNDF cho symbol của chính binary — tính
            # cả chúng thì mọi ivar của chính ta cũng bị báo là thiếu.
            if n_type != 0x01:
                continue
            end = strings.find(b"\x00", n_strx)
            result.add(strings[n_strx:end if end >= 0 else None].decode(errors="replace"))
        return result

    def uses_blocks(self) -> bool:
        """Binary có tạo block Objective-C không.

        Quan trọng vì trên arm64e, trường `invoke` của block được khai báo
        __ptrauth(ptrauth_key_function_pointer, true, 0xc0bb): bên GỌI xác thực nó.
        Nếu binary này không ký con trỏ (xem signs_pointers), block sẽ làm process
        gọi nó chết ở một địa chỉ còn nguyên bits chữ ký.
        """
        undefined = self.undefined_symbols()
        return bool(undefined & {"__NSConcreteStackBlock", "__NSConcreteGlobalBlock",
                                 "_NSConcreteStackBlock", "_NSConcreteGlobalBlock"})

    def signs_pointers(self) -> bool:
        """Mã của binary này có sinh lệnh ký con trỏ không (pac*/aut* trên thanh ghi)."""
        found = self.pac_instructions()
        return any(name.startswith(("pac", "aut")) and name not in ("pacibsp", "autibsp",
                                                                    "paciasp", "autiasp")
                   for name in found)

    def code_signature_matches(self):
        """Chữ ký có bao trùm đúng nội dung file hiện tại không.

        Trả (số trang khớp, tổng số trang), hoặc None nếu không đọc được chữ ký.

        Cần thiết vì quy trình đóng gói sửa Mach-O SAU khi link: đổi phụ thuộc, làm
        weak, bật cờ PTRAUTH_ABI. Mỗi bước đó làm hỏng chữ ký cũ, và nếu ký lại bị đặt
        sai thứ tự thì binary vẫn "có chữ ký" nhưng nội dung không khớp — AMFI từ chối
        và tweak im lặng không nạp.
        """
        import hashlib
        if not self.code_signature:
            return None
        base = self.offset + self.code_signature[0]
        data = self.data
        try:
            count = struct.unpack_from(">I", data, base + 8)[0]
            cd_off = None
            for i in range(count):
                blob_type, offset = struct.unpack_from(">II", data, base + 12 + i * 8)
                if struct.unpack_from(">I", data, base + offset)[0] == 0xFADE0C02:
                    cd_off = base + offset
                    break
            if cd_off is None:
                return None

            hash_offset, _, _, slots, code_limit = struct.unpack_from("<xxxx", data, 0) \
                if False else struct.unpack_from(">IIIII", data, cd_off + 16)
            hash_size = data[cd_off + 36]
            hash_type = data[cd_off + 37]
            page_size = 1 << data[cd_off + 39]
            digest = {1: hashlib.sha1, 2: hashlib.sha256, 3: hashlib.sha256}.get(hash_type)
            if digest is None or page_size <= 1:
                return None

            matched = 0
            for i in range(slots):
                start = i * page_size
                end = min(start + page_size, code_limit)
                stored = data[cd_off + hash_offset + i * hash_size:
                              cd_off + hash_offset + (i + 1) * hash_size]
                if digest(data[start:end]).digest()[:hash_size] == stored:
                    matched += 1
            return matched, slots
        except Exception:
            return None

    def objc_class_count(self) -> int:
        entry = self.sections.get("__DATA_CONST,__objc_classlist") \
            or self.sections.get("__DATA,__objc_classlist")
        return entry[1] // 8 if entry else 0


def read(path) -> list:
    """Mọi slice trong file, dạng đối tượng MachO."""
    with open(path, "rb") as handle:
        data = handle.read()
    if not data:
        return []
    if struct.unpack_from(">I", data, 0)[0] == FAT_MAGIC:
        offsets = []
        for i in range(struct.unpack_from(">I", data, 4)[0]):
            _, _, off, _, _ = struct.unpack_from(">iiIII", data, 8 + i * 20)
            offsets.append(off)
    else:
        offsets = [0]
    return [MachO(data, off) for off in offsets]


def is_macho(path) -> bool:
    try:
        with open(path, "rb") as handle:
            return handle.read(4) in (b"\xca\xfe\xba\xbe", b"\xcf\xfa\xed\xfe")
    except OSError:
        return False
