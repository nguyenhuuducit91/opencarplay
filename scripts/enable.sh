#!/bin/sh
# OpenCarPlay — bật tweak và kiểm chứng, trong một lần chạy.
#
#     sh scripts/enable.sh [giai đoạn]      (mặc định 5 = đầy đủ, có hook dashboard)
#
# Chạy TRÊN MÁY TÍNH, iPhone cắm cáp USB.
#
# Script đặt giai đoạn qua vùng AFC, bảo bạn respring, ghi log, rồi nói thẳng tweak đã
# chạy tới đâu. Gộp ba bước rời rạc trước đây làm một.
#
# CỨU HỘ: nếu máy treo ở màn hình khởi động, chạy trên máy tính:
#     sh scripts/set_stage.sh off
# rồi khởi động lại máy. Lệnh đó ghi qua cáp USB, không cần vào được giao diện.

set -e
STAGE="${1:-5}"
OUT="${2:-./ocp-enable}"
mkdir -p "$OUT"

for tool in afcclient idevicesyslog; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Thiếu $tool: sudo apt install libimobiledevice-utils ifuse"; exit 1; }
done

TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$STAGE" > "$TMP"
afcclient put "$TMP" /OpenCarPlay/STAGE
echo "Đã đặt giai đoạn $STAGE."
echo

echo "Đang ghi log 90 giây."
echo
echo "  BÂY GIỜ HÃY RESPRING (Dopamine -> Respring, hoặc Sileo -> Respring)."
echo "  Đợi máy hiện lại màn hình khoá rồi để script chạy hết."
echo

idevicesyslog > "$OUT/full.txt" 2>&1 &
PID=$!
i=0
while [ $i -lt 90 ]; do printf '\r  còn %2d giây ' $((90 - i)); i=$((i + 1)); sleep 1; done
printf '\r                    \r'
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

hr() { echo "------------------------------------------------------------"; }

hr
echo "1. DYLIB CÓ ĐƯỢC NẠP KHÔNG"
if grep -q "OpenCarPlay\] ctor: nap vao" "$OUT/full.txt"; then
    grep -o "OpenCarPlay\] ctor: nap vao.*" "$OUT/full.txt" | sort -u | sed 's/^/   /'
else
    echo "   KHÔNG — injector không nạp dylib vào process nào."
fi

hr
echo "2. KHỞI TẠO CHẠY TỚI ĐÂU"
grep -o "OpenCarPlay\].*giai đoạn.*" "$OUT/full.txt" | sort -u | head -10 | sed 's/^/   /' \
    || echo "   (không có dòng nào)"
grep -oE "\[OpenCarPlay\](\[[A-Za-z]+\])? (cấu hình|khởi tạo xong|dừng ở|vô hiệu hoá|đã hook).*" \
    "$OUT/full.txt" | sort -u | head -15 | sed 's/^/   /' || true

hr
echo "3. LỖI"
grep -iE "OpenCarPlay.*(thất bại|lỗi|exception|KHÔNG)" "$OUT/full.txt" | head -10 | sed 's/^/   /' \
    || echo "   (không có)"
grep -c "Terminating app due to uncaught exception" "$OUT/full.txt" \
    | sed 's/^/   exception chưa bắt: /'

hr
echo "4. DẤU NẠP"
afcclient get /OpenCarPlay/loaded-SpringBoard.txt "$TMP" >/dev/null 2>&1 \
    && sed 's/^/   /' "$TMP" || echo "   chưa có (vùng AFC có thể bị sandbox chặn ghi)"

hr
echo "Log đầy đủ: $OUT/full.txt"
echo
echo "Nếu máy treo hoặc SpringBoard chết lặp:  sh scripts/set_stage.sh off"
