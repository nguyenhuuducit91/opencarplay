#!/usr/bin/env python3
"""Chuyển plist sang định dạng nhị phân.

    python3 scripts/binary_plist.py <file.plist> [...]

VÌ SAO CẦN

Theos muốn tự làm việc này lúc đóng gói nhưng bỏ qua trên máy build Linux không có
plutil/libplist-utils, và chỉ in một dòng Notice:

    Neither plutil, ply, or libplist-utils are installed, so XML plist files were
    not optimized.

Hậu quả: plist filter của tweak ship ở dạng XML, trong khi MỌI tweak khác trên thiết bị
đều ở dạng nhị phân (PreferenceLoader.plist 56 byte, CepheiSpringBoard.plist 92 byte,
còn của ta 349 byte). Đó là khác biệt duy nhất nhìn thấy được giữa tweak chạy được và
tweak không được nạp.

Python có sẵn plistlib nên không cần công cụ ngoài nào.
"""

import plistlib
import sys
from pathlib import Path


def convert(path: Path) -> bool:
    raw = path.read_bytes()
    if raw[:8] == b"bplist00":
        return False
    try:
        data = plistlib.loads(raw)
    except Exception as error:
        sys.exit(f"{path}: không đọc được plist: {error}")

    encoded = plistlib.dumps(data, fmt=plistlib.FMT_BINARY)
    # Đọc lại để chắc chắn nội dung không đổi — plist filter sai một chút là tweak
    # không bao giờ được nạp, và không có thông báo lỗi nào.
    if plistlib.loads(encoded) != data:
        sys.exit(f"{path}: chuyển sang nhị phân làm đổi nội dung — dừng")

    path.write_bytes(encoded)
    print(f"  plist nhị phân: {path.name} ({len(raw)} -> {len(encoded)} byte)")
    return True


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("dùng: binary_plist.py <file.plist> [...]")
    for argument in sys.argv[1:]:
        path = Path(argument)
        if path.is_file():
            convert(path)


if __name__ == "__main__":
    main()
