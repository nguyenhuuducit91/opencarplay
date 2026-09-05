#!/usr/bin/env python3
"""Sinh APT repository (flat) cho Sileo từ các .deb trong packages/.

Kết quả nằm trong docs/ để GitHub Pages phục vụ trực tiếp:
    docs/Packages[.gz|.bz2|.xz]   danh mục gói
    docs/Release                  metadata repo
    docs/debs/*.deb               file gói

Chạy:  python3 scripts/make_repo.py
Không phụ thuộc dpkg-dev — chỉ dùng thư viện chuẩn.
"""

import bz2
import gzip
import hashlib
import lzma
import os
import shutil
import subprocess
import email.utils
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGES_DIR = ROOT / "packages"
DOCS = ROOT / "docs"
DEBS = DOCS / "debs"

# Thông tin repo. Sửa REPO_URL sau khi biết URL GitHub Pages thật.
REPO = {
    "Origin": "OpenCarPlay",
    "Label": "OpenCarPlay",
    "Suite": "stable",
    "Version": "1.0",
    "Codename": "opencarplay",
    "Architectures": "iphoneos-arm64",
    "Components": "main",
    "Description": "OpenCarPlay — dùng ứng dụng iOS trên màn hình CarPlay (rootless, iOS 18.6.x)",
}


def deb_control_fields(deb: Path) -> dict:
    """Đọc khối control từ .deb bằng dpkg-deb (có sẵn trên Ubuntu)."""
    out = subprocess.run(["dpkg-deb", "-f", str(deb)],
                         capture_output=True, text=True, check=True).stdout
    fields, key = {}, None
    for line in out.splitlines():
        if line.startswith((" ", "\t")) and key:
            fields[key] += "\n" + line
        elif ":" in line:
            key, _, value = line.partition(":")
            key = key.strip()
            fields[key] = value.strip()
    return fields


def hashes(data: bytes) -> dict:
    return {
        "MD5sum": hashlib.md5(data).hexdigest(),
        "SHA1": hashlib.sha1(data).hexdigest(),
        "SHA256": hashlib.sha256(data).hexdigest(),
    }


# Thứ tự trường theo quy ước Debian; Sileo đọc được mọi thứ tự nhưng đọc dễ hơn khi ổn định.
FIELD_ORDER = [
    "Package", "Version", "Architecture", "Name", "Section", "Depends", "Conflicts",
    "Replaces", "Provides", "Maintainer", "Author", "Depiction", "SileoDepiction",
    "Icon", "Tag", "Filename", "Size", "MD5sum", "SHA1", "SHA256", "Description",
]


def build_packages(repo_url: str) -> bytes:
    # Bỏ qua bản debug: Theos đặt tên chúng là <version>-N+debug, mà APT coi
    # "0.2.0-2+debug" MỚI HƠN "0.2.0" — Sileo sẽ chào bản debug cho người dùng.
    debs = sorted(p for p in PACKAGES_DIR.glob("*.deb") if "+debug" not in p.name)
    skipped = sorted(p for p in PACKAGES_DIR.glob("*.deb") if "+debug" in p.name)
    for p in skipped:
        print(f"  - bỏ qua bản debug: {p.name}")
    if not debs:
        sys.exit("Không tìm thấy .deb phát hành nào trong packages/ — "
                 "chạy `make package FINALPACKAGE=1` trước.")

    DEBS.mkdir(parents=True, exist_ok=True)
    for stale in DEBS.glob("*.deb"):
        stale.unlink()

    stanzas = []
    for deb in debs:
        shutil.copy2(deb, DEBS / deb.name)
        payload = deb.read_bytes()

        fields = deb_control_fields(deb)
        fields["Filename"] = f"debs/{deb.name}"
        fields["Size"] = str(len(payload))
        fields.update(hashes(payload))
        if repo_url:
            fields.setdefault("Depiction", f"{repo_url}/depiction/opencarplay.html")
            fields.setdefault("SileoDepiction", f"{repo_url}/depiction/opencarplay.json")
            fields.setdefault("Icon", f"{repo_url}/CydiaIcon.png")

        lines = []
        for key in FIELD_ORDER:
            if key in fields:
                lines.append(f"{key}: {fields.pop(key)}")
        for key, value in fields.items():          # trường lạ vẫn được giữ
            lines.append(f"{key}: {value}")
        stanzas.append("\n".join(lines))
        print(f"  + {deb.name}  ({len(payload)} bytes)")

    return ("\n\n".join(stanzas) + "\n").encode("utf-8")


def write_indexes(packages: bytes) -> list:
    written = [("Packages", packages)]
    (DOCS / "Packages").write_bytes(packages)

    gz = gzip.compress(packages, mtime=0)          # mtime=0 để build tái lập được
    (DOCS / "Packages.gz").write_bytes(gz)
    written.append(("Packages.gz", gz))

    bz = bz2.compress(packages)
    (DOCS / "Packages.bz2").write_bytes(bz)
    written.append(("Packages.bz2", bz))

    xz = lzma.compress(packages, format=lzma.FORMAT_XZ)
    (DOCS / "Packages.xz").write_bytes(xz)
    written.append(("Packages.xz", xz))

    # zstd: Sileo và bootstrap Procursus ưu tiên định dạng này.
    try:
        zst = subprocess.run(["zstd", "-19", "-q", "-c"], input=packages,
                             capture_output=True, check=True).stdout
        (DOCS / "Packages.zst").write_bytes(zst)
        written.append(("Packages.zst", zst))
    except (FileNotFoundError, subprocess.CalledProcessError):
        print("  (bỏ qua Packages.zst — không có lệnh zstd)")

    return written


def write_release(indexes: list) -> None:
    lines = [f"{k}: {v}" for k, v in REPO.items()]
    lines.append("Date: " + email.utils.formatdate(usegmt=True))

    for algo, field in (("MD5sum", "MD5Sum"), ("SHA1", "SHA1"), ("SHA256", "SHA256")):
        lines.append(f"{field}:")
        for name, data in indexes:
            digest = hashes(data)[algo]
            lines.append(f" {digest} {len(data)} {name}")

    (DOCS / "Release").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    repo_url = os.environ.get("OCP_REPO_URL", "").rstrip("/")
    if not repo_url:
        print("Cảnh báo: chưa đặt OCP_REPO_URL — Depiction/Icon sẽ bị bỏ trống.")
        print("  ví dụ: OCP_REPO_URL=https://<user>.github.io/OpenCarPlay python3 scripts/make_repo.py")

    print("Sinh APT repo trong docs/ ...")
    packages = build_packages(repo_url)
    indexes = write_indexes(packages)
    write_release(indexes)

    print("\nXong:")
    for path in ("Release", "Packages", "Packages.gz", "Packages.bz2", "Packages.xz",
                 "Packages.zst"):
        target = DOCS / path
        if target.exists():
            print(f"  docs/{path}  ({target.stat().st_size} bytes)")
    if repo_url:
        print(f"\nThêm vào Sileo:  {repo_url}")


if __name__ == "__main__":
    main()
