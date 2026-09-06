#!/bin/sh
# OpenCarPlay — dylib có được ElleKit nạp vào SpringBoard không?
#
# Chạy TRÊN MÁY TÍNH, iPhone cắm cáp USB và đã mở khoá:
#
#     sh scripts/check_injection.sh
#
# Script ghi log rồi bảo bạn respring. Constructor của tweak gọi syslog() ngay khi được
# nạp; syslog không cần quyền ghi file nào, nên đây là bằng chứng đáng tin hơn mọi file
# dấu. Không thấy dòng nào nghĩa là dylib KHÔNG được nạp — và các dòng dyld/amfid bắt
# được cùng lúc sẽ nói vì sao.

set -e
OUT="${1:-./ocp-inject}"
mkdir -p "$OUT"

command -v idevicesyslog >/dev/null 2>&1 || {
    echo "Thiếu idevicesyslog: sudo apt install libimobiledevice-utils"; exit 1; }

echo "Đang ghi log 75 giây."
echo
echo "  BÂY GIỜ HÃY RESPRING trên máy:"
echo "    • Dopamine  -> nút Respring"
echo "    • hoặc Sileo -> Respring"
echo "    • hoặc SSH   -> sbreload   (hoặc: killall -9 SpringBoard)"
echo
echo "Đợi tới khi máy hiện lại màn hình khoá rồi để script chạy hết."
echo

idevicesyslog > "$OUT/full.txt" 2>&1 &
PID=$!
i=0
while [ $i -lt 75 ]; do
    printf '\r  còn %2d giây ' $((75 - i)); i=$((i + 1)); sleep 1
done
printf '\r                    \r'
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

hr() { echo "------------------------------------------------------------"; }

hr
echo "1. CONSTRUCTOR CỦA OPENCARPLAY"
# Từ 0.46.0 constructor ghi dòng "nap vao progname=..." NGAY khi được nạp, trước mọi
# kiểm tra. Nên dòng đó có hay không là câu trả lời dứt khoát cho "dylib có được nạp
# không" — khác với các bản trước, khi log chỉ chạy sau khi tên process đã khớp.
if grep -q "OpenCarPlay\] ctor: nap vao" "$OUT/full.txt"; then
    echo "  => dylib ĐÃ ĐƯỢC NẠP. Các process nạp nó:"
    grep -o "OpenCarPlay\] ctor: nap vao.*" "$OUT/full.txt" | sort -u | sed 's/^/    /'
    echo
    grep -o "OpenCarPlay\] ctor: process=.*" "$OUT/full.txt" | sort -u | sed 's/^/    /'
else
    echo "  (không có dòng 'ctor: nap vao' nào)"
    echo "  => injector KHÔNG nạp dylib vào bất kỳ process nào trong 75 giây vừa rồi."
    echo "     (Chỉ kết luận được điều này từ bản 0.46.0 trở đi; các bản trước chỉ ghi"
    echo "      log SAU khi tên process đã khớp, nên im lặng không chứng minh được gì.)"
fi

hr
echo "2. SPRINGBOARD CÓ KHỞI ĐỘNG LẠI KHÔNG"
if grep -qE "SpringBoard.*(didFinishLaunching|Bootstrap|_handleSystemAppExit)" "$OUT/full.txt"; then
    echo "  có — bắt được sự kiện khởi động lại"
else
    echo "  KHÔNG thấy dấu hiệu SpringBoard khởi động lại."
    echo "  Nếu bạn chưa kịp respring thì chạy lại script và respring sớm hơn."
fi

hr
echo "3. LỖI NẠP THƯ VIỆN / CHỮ KÝ (dyld, amfid, trust cache)"
grep -iE "dyld|amfid|code ?sign|trust ?cache|library load|not valid|denied" "$OUT/full.txt" \
    | grep -viE "^$" | head -25 || echo "  (không có)"

hr
echo "4. ELLEKIT"
grep -i "ellekit\|TweakInject\|libinjector" "$OUT/full.txt" | head -15 || echo "  (không có)"

hr
echo "Log đầy đủ: $OUT/full.txt"
echo "Gửi lại nội dung in ở trên là đủ."
