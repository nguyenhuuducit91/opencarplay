#!/bin/sh
# Tải kết quả khảo sát runtime từ iPhone về máy build, qua USB (AFC).
# Không cần SSH — chỉ cần thiết bị đã tin cậy máy này.
#
#   ./scripts/fetch_survey.sh [thư_mục_đích]
#
# Bật khảo sát trước bằng cách đặt RuntimeSurvey = YES trong
#   /var/jb/var/mobile/Library/Preferences/com.opencarplay.plist
# rồi respring (hoặc killall -9 CarPlay để khảo sát process dashboard).

set -e
DEST="${1:-./survey}"
REMOTE_DIR="/OpenCarPlay"      # tương ứng /var/mobile/Media/OpenCarPlay trên thiết bị

command -v afcclient >/dev/null 2>&1 || {
    echo "Thiếu afcclient — cài libimobiledevice-utils"; exit 1;
}

echo "==> thiết bị"
ideviceinfo -k DeviceName 2>/dev/null || { echo "Không thấy thiết bị"; exit 1; }

echo "==> tìm file khảo sát trong /var/mobile/Media$REMOTE_DIR"
FILES=$(afcclient ls "$REMOTE_DIR" 2>/dev/null | grep -i '^survey-.*\.txt$' || true)
if [ -z "$FILES" ]; then
    echo "Chưa có file nào."
    echo "Kiểm tra: RuntimeSurvey = YES trong com.opencarplay.plist, và đã respring chưa?"
    exit 2
fi

mkdir -p "$DEST"
echo "$FILES" | while read -r f; do
    [ -n "$f" ] || continue
    echo "  <- $f"
    afcclient get "$REMOTE_DIR/$f" "$DEST/$f" >/dev/null 2>&1 || echo "     (tải thất bại)"
done

echo
echo "==> đã lưu vào $DEST"
ls -la "$DEST"
echo
echo "Tóm tắt nhanh:"
for f in "$DEST"/survey-*.txt; do
    [ -f "$f" ] || continue
    echo "--- $(basename "$f")"
    sed -n '1,12p' "$f" | sed 's/^/    /'
    echo "    ... ($(wc -l < "$f") dòng)"
done
