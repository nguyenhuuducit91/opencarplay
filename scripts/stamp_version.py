#!/usr/bin/env python3
"""Đồng bộ phiên bản trong mọi Info.plist của bundle với `control`.

    python3 scripts/stamp_version.py <thư mục staging>

Bảng cài đặt hiển thị CFBundleShortVersionString cho người dùng đối chiếu với bản đã
cài. Nếu hai con số lệch nhau thì dòng đó nói dối, và nó nói dối đúng vào lúc người
dùng đang cố xác định mình có đang chạy bản mới hay không.
"""

import plistlib
import re
import sys
from pathlib import Path


def control_version(root: Path) -> str:
    text = (root / "control").read_text(encoding="utf-8")
    match = re.search(r"^Version:\s*(\S+)\s*$", text, re.M)
    if not match:
        sys.exit("không đọc được Version trong control")
    return match.group(1)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("dùng: stamp_version.py <thư mục staging>")

    project = Path(__file__).resolve().parent.parent
    version = control_version(project)
    staging = Path(sys.argv[1])

    for info in staging.rglob("*.bundle/Info.plist"):
        data = plistlib.loads(info.read_bytes())
        if data.get("CFBundleShortVersionString") == version and \
           data.get("CFBundleVersion") == version:
            continue
        data["CFBundleShortVersionString"] = version
        data["CFBundleVersion"] = version
        info.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
        print(f"  phiên bản {version}: {info.parent.name}/Info.plist")


if __name__ == "__main__":
    main()
