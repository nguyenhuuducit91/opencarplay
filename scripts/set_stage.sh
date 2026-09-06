#!/bin/sh
# OpenCarPlay — đặt giai đoạn khởi tạo qua cáp USB.
#
#     sh scripts/set_stage.sh 0        chỉ nạp dylib, không chạm gì (an toàn)
#     sh scripts/set_stage.sh 1..5     nâng dần; 5 là đầy đủ, có hook dashboard
#     sh scripts/set_stage.sh auto     bỏ ghi đè, dùng cấu hình trong máy
#     sh scripts/set_stage.sh off      TẮT HẲN tweak (kill switch cứu hộ)
#     sh scripts/set_stage.sh on       gỡ kill switch
#     sh scripts/set_stage.sh status   xem đang ở đâu
#
# Ghi vào /var/mobile/Media/OpenCarPlay/ — vùng AFC, nên KHÔNG cần SSH và không cần
# jailbreak còn sống. Đây cũng là đường cứu hộ khi máy treo ở màn hình khởi động: file
# này được constructor đọc trước mọi thứ khác.
#
# Sau khi đổi phải RESPRING thì mới có hiệu lực.

set -e
command -v afcclient >/dev/null 2>&1 || {
    echo "Thiếu afcclient: sudo apt install libimobiledevice-utils ifuse"; exit 1; }

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

case "${1:-status}" in
    0|1|2|3|4|5)
        printf '%s\n' "$1" > "$TMP"
        afcclient put "$TMP" /OpenCarPlay/STAGE
        echo "Đã đặt giai đoạn $1. RESPRING để có hiệu lực."
        [ "$1" -ge 1 ] 2>/dev/null && {
            echo
            echo "  Giai đoạn >= 1 chạy mã chưa được kiểm chứng trên iOS 18.6."
            echo "  Nếu máy treo ở màn hình khởi động, tắt hẳn bằng:"
            echo "      sh scripts/set_stage.sh off"
            echo "  Lần khởi động sau tweak cũng tự hạ về 0 nếu phát hiện lần trước treo."
        }
        ;;
    auto)
        afcclient rm /OpenCarPlay/STAGE 2>/dev/null || true
        echo "Đã bỏ ghi đè qua USB. Giai đoạn lấy từ"
        echo "  /var/mobile/Library/Preferences/com.opencarplay.stage (mặc định 0)."
        echo "RESPRING để có hiệu lực."
        ;;
    off)
        : > "$TMP"
        afcclient put "$TMP" /OpenCarPlay/DISABLED
        echo "KILL SWITCH đã bật — tweak sẽ không nạp gì. RESPRING (hoặc khởi động lại)."
        ;;
    on)
        afcclient rm /OpenCarPlay/DISABLED 2>/dev/null || true
        echo "Đã gỡ kill switch. RESPRING để có hiệu lực."
        ;;
    status)
        # Dùng `ls` chứ không phải `get` để biết file có tồn tại: afcclient get trả về
        # mã thoát 0 kể cả khi file không có, nên dựa vào nó thì status báo sai —
        # từng báo "kill switch ĐANG BẬT" trong khi thư mục không hề có file DISABLED.
        LISTING=$(afcclient ls /OpenCarPlay 2>/dev/null || true)
        echo "Nội dung /OpenCarPlay trên máy:"
        if [ -n "$LISTING" ]; then
            printf '%s\n' "$LISTING" | sed 's/^/  /'
        else
            echo "  (trống hoặc chưa tồn tại)"
        fi
        echo

        has() { printf '%s\n' "$LISTING" | grep -qx "$1"; }

        if has STAGE; then
            afcclient get /OpenCarPlay/STAGE "$TMP" >/dev/null 2>&1
            echo "  giai đoạn (ghi đè qua USB): $(tr -d '\n' < "$TMP")"
        else
            echo "  giai đoạn: không ghi đè qua USB — lấy từ cấu hình trong máy (mặc định 0)"
        fi

        if has DISABLED; then
            echo "  kill switch: ĐANG BẬT — tweak không nạp gì"
        else
            echo "  kill switch: tắt"
        fi

        if has loaded-SpringBoard.txt; then
            afcclient get /OpenCarPlay/loaded-SpringBoard.txt "$TMP" >/dev/null 2>&1
            echo "  dấu nạp SpringBoard:"
            sed 's/^/    /' "$TMP"
        else
            echo "  dấu nạp SpringBoard: CHƯA CÓ"
            echo "    Chưa kết luận được điều gì: có thể dylib chưa nạp, cũng có thể nạp"
            echo "    rồi mà sandbox chặn ghi vào vùng AFC. Phân biệt bằng:"
            echo "        sh scripts/check_injection.sh"
        fi
        ;;
    *)
        sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
