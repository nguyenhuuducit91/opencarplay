#!/bin/sh
# OpenCarPlay — gom bằng chứng khi Settings crash lúc mở bảng cài đặt.
#
# Chạy TRÊN MÁY TÍNH, iPhone cắm cáp USB, đã mở khoá và bấm "Tin cậy".
#
#     sh scripts/collect_crash.sh
#
# Cần libimobiledevice:
#     Debian/Ubuntu : sudo apt install libimobiledevice-utils ifuse
#     macOS         : brew install libimobiledevice
#
# Script chỉ ĐỌC từ thiết bị, không ghi gì, không cần SSH và không cần jailbreak
# còn sống.

set -e

OUT="${1:-./ocp-crash}"
mkdir -p "$OUT"

say() { printf '\n=== %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

if ! have idevice_id; then
    echo "Thiếu libimobiledevice. Xem hướng dẫn cài ở đầu file này."
    exit 1
fi

say "1. Thiết bị"
idevice_id -l | tee "$OUT/devices.txt"
if have ideviceinfo; then
    ideviceinfo -k ProductType    2>/dev/null | sed 's/^/  máy    : /'
    ideviceinfo -k ProductVersion 2>/dev/null | sed 's/^/  iOS    : /'
    ideviceinfo -k CPUArchitecture 2>/dev/null | sed 's/^/  kiến trúc: /'
fi

say "2. Crash report của Settings"
# LƯU Ý: idevicecrashreport nhận DUY NHẤT một tham số vị trí — thư mục đích. Bản trước
# viết `idevicecrashreport -e -k Preferences "$OUT/crash"`, và vì -k không nhận tham số
# nên "Preferences" bị hiểu là THƯ MỤC ĐÍCH: toàn bộ crash report của máy đổ vào thư mục
# source Preferences/. Lọc bằng find ở đây, không dùng -f (không có ở bản libimobiledevice cũ).
if have idevicecrashreport; then
    mkdir -p "$OUT/crash"
    idevicecrashreport -e -k "$OUT/crash" 2>&1 | tail -3 || true
    echo "  --- crash của Settings / CarPlay / SpringBoard:"
    find "$OUT/crash" -type f \( -name 'Preferences-*' -o -name 'CarPlay*' \
         -o -name 'SpringBoard-*' -o -name '*OpenCarPlay*' \) 2>/dev/null \
        | sort | tail -8 | sed 's/^/    /'
    LATEST=$(find "$OUT/crash" -type f \( -name 'CarPlay*' -o -name 'Preferences-*' \) \
             2>/dev/null | sort | tail -1)
    if [ -n "$LATEST" ]; then
        echo "  --- lý do của bản mới nhất:"
        grep -m3 -iE '"reason"|"exception"|Termination|"name"' "$LATEST" 2>/dev/null \
            | cut -c1-200 | sed 's/^/    /'
    fi
else
    echo "  thiếu idevicecrashreport"
fi

say "3. Dấu vết OpenCarPlay trong vùng AFC"
if have afcclient; then
    for f in loaded-SpringBoard.txt loaded-CarPlay.txt prefs-trace.txt STAGE DISABLED; do
        if afcclient get "/OpenCarPlay/$f" "$OUT/$f" >/dev/null 2>&1; then
            echo "  --- $f"
            sed 's/^/      /' "$OUT/$f" 2>/dev/null || true
        fi
    done
else
    echo "  thiếu afcclient (gói ifuse/libimobiledevice-utils)"
fi

say "4. Bây giờ mở Cài đặt → OpenCarPlay"
echo "  Đang ghi log 40 giây. HÃY BẤM VÀO OpenCarPlay NGAY BÂY GIỜ."
echo
if have idevicesyslog; then
    ( idevicesyslog > "$OUT/syslog-full.txt" 2>&1 & echo $! > "$OUT/.pid" )
    sleep 40
    kill "$(cat "$OUT/.pid")" 2>/dev/null || true
    rm -f "$OUT/.pid"
    grep -iE "opencarplay|preferenceloader|PSListController|Preferences\[|Settings\[" \
        "$OUT/syslog-full.txt" > "$OUT/syslog-loc.txt" 2>/dev/null || true
    echo "  --- dòng liên quan"
    sed 's/^/      /' "$OUT/syslog-loc.txt" 2>/dev/null | head -60
else
    echo "  thiếu idevicesyslog"
fi

say "Xong"
echo "  Tất cả nằm trong: $OUT"
echo "  Gửi lại 3 file này là đủ:"
echo "    $OUT/crash/*Preferences*"
echo "    $OUT/syslog-loc.txt"
echo "    $OUT/prefs-trace.txt   (nếu có)"
