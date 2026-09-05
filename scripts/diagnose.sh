#!/bin/sh
# OpenCarPlay — chẩn đoán môi trường. CHẠY TRÊN THIẾT BỊ (qua SSH).
#   scp -P 2222 scripts/diagnose.sh mobile@127.0.0.1:/tmp/ && ssh -p 2222 mobile@127.0.0.1 sh /tmp/diagnose.sh

PACKAGE_ID="com.opencarplay.tweak"
JBROOT=""
for candidate in /var/jb /var/containers/Bundle/Application/.jbroot-* ""; do
    [ -n "$candidate" ] && [ -d "$candidate/usr/lib" ] && JBROOT="$candidate" && break
done

hr() { echo "------------------------------------------------------------"; }
ok() { echo "  [ OK ] $1"; }
no() { echo "  [FAIL] $1"; }
info() { echo "  [INFO] $1"; }

echo "OpenCarPlay diagnose — $(date)"
hr
echo "1. HỆ ĐIỀU HÀNH"
if [ -f /System/Library/CoreServices/SystemVersion.plist ]; then
    VER=$(plutil -p /System/Library/CoreServices/SystemVersion.plist 2>/dev/null | grep -i ProductVersion | sed 's/.*=> *//;s/"//g')
    BUILD=$(plutil -p /System/Library/CoreServices/SystemVersion.plist 2>/dev/null | grep -i ProductBuildVersion | sed 's/.*=> *//;s/"//g')
    info "iOS $VER (build $BUILD)"
    case "$VER" in
        18.6*) ok "phiên bản nằm trong phạm vi hỗ trợ (18.6.x)";;
        18.*)  info "iOS 18.x nhưng không phải 18.6 — tweak sẽ tự vô hiệu hoá nếu ngoài phạm vi";;
        *)     no "ngoài phạm vi hỗ trợ hiện tại";;
    esac
else
    no "không đọc được SystemVersion.plist"
fi

hr
echo "2. KIẾN TRÚC"
ARCH=$(uname -m)
info "uname -m = $ARCH"
[ "$ARCH" = "arm64e" ] && ok "arm64e (A12+)" || info "không phải arm64e — kiểm tra lại thiết bị mục tiêu"

hr
echo "3. MÔI TRƯỜNG JAILBREAK"
if [ -n "$JBROOT" ]; then
    ok "rootless, JBROOT = $JBROOT"
else
    no "không tìm thấy jbroot (/var/jb) — có phải rootful không?"
    JBROOT=""
fi
for lib in libellekit.dylib libsubstrate.dylib libhooker.dylib libsubstitute.dylib; do
    [ -f "$JBROOT/usr/lib/$lib" ] && ok "hooking runtime: $lib"
done

hr
echo "4. GÓI ĐÃ CÀI"
if dpkg-query -W -f='${Package} ${Version} ${Status}\n' "$PACKAGE_ID" 2>/dev/null | grep -q "install ok installed"; then
    ok "$(dpkg-query -W -f='${Package} ${Version}' $PACKAGE_ID 2>/dev/null)"
    DYLIB="$JBROOT/Library/MobileSubstrate/DynamicLibraries/OpenCarPlay.dylib"
    PLIST="$JBROOT/Library/MobileSubstrate/DynamicLibraries/OpenCarPlay.plist"
    [ -f "$DYLIB" ] && ok "dylib: $DYLIB" || no "thiếu dylib tại $DYLIB"
    [ -f "$PLIST" ] && ok "filter: $PLIST" || no "thiếu filter plist"
    [ -f "$PLIST" ] && info "filter bundles: $(plutil -p "$PLIST" 2>/dev/null | grep -o 'com\.apple\.[A-Za-z]*' | tr '\n' ' ')"
else
    no "$PACKAGE_ID chưa được cài"
fi

hr
echo "5. PROCESS LIÊN QUAN CARPLAY"
ps -Ao pid,comm 2>/dev/null | grep -iE 'springboard|carplay|InCallService|MusicUIService' | grep -v grep | while read -r line; do
    info "$line"
done
pgrep -x SpringBoard >/dev/null 2>&1 && ok "SpringBoard đang chạy" || no "SpringBoard không chạy (?)"
pgrep -f CarPlay >/dev/null 2>&1 && ok "có process CarPlay" || info "không có process CarPlay (bình thường khi chưa kết nối)"

hr
echo "6. TRẠNG THÁI KẾT NỐI CARPLAY"
if [ -d /System/Library/CoreServices/CarPlay.app ]; then
    ok "CarPlay.app tồn tại"
else
    no "không tìm thấy /System/Library/CoreServices/CarPlay.app"
fi
info "cắm/rút CarPlay rồi chạy lại script để so sánh danh sách process ở mục 5"

hr
echo "7. DYLIB ĐÃ ĐƯỢC INJECT?"
for proc in SpringBoard CarPlay; do
    PID=$(pgrep -x "$proc" 2>/dev/null | head -1)
    if [ -n "$PID" ]; then
        if command -v vmmap >/dev/null 2>&1 && vmmap "$PID" 2>/dev/null | grep -q OpenCarPlay; then
            ok "$proc (pid $PID): OpenCarPlay.dylib đã nạp"
        else
            info "$proc (pid $PID): không kiểm tra được bằng vmmap — dùng log ở mục 8"
        fi
    else
        info "$proc không chạy"
    fi
done

hr
echo "8. LOG"
info "trên máy build:  idevicesyslog | grep -i opencarplay"
info "trên thiết bị :  $JBROOT/usr/bin/log stream --predicate 'subsystem == \"com.opencarplay.tweak\"'"

hr
echo "9. KHẢO SÁT RUNTIME"
PREFS="$JBROOT/var/mobile/Library/Preferences/com.opencarplay.plist"
if [ -f "$PREFS" ]; then
    ok "preferences: $PREFS"
    for k in Enabled DebugLogging RuntimeSurvey SignalDiscovery; do
        V=$(plutil -p "$PREFS" 2>/dev/null | grep -i "\"$k\"" | sed 's/.*=> *//')
        info "  $k = ${V:-(chưa đặt)}"
    done
else
    info "chưa có preferences — mọi tuỳ chọn dùng giá trị mặc định (tắt)"
    info "bật khảo sát: tạo $PREFS với RuntimeSurvey = true rồi respring"
fi
SURVEYDIR=/var/mobile/Media/OpenCarPlay
if [ -d "$SURVEYDIR" ]; then
    N=$(ls "$SURVEYDIR"/survey-*.txt 2>/dev/null | wc -l)
    ok "$N file khảo sát trong $SURVEYDIR"
    info "lấy về máy build: ./scripts/fetch_survey.sh"
else
    info "chưa có file khảo sát nào"
fi

hr
echo "10. CÔNG TẮC AN TOÀN"
KILL="$JBROOT/var/mobile/Library/Preferences/com.opencarplay.disabled"
if [ -f "$KILL" ]; then
    no "KILL SWITCH ĐANG BẬT — tweak sẽ không nạp. Xoá: rm $KILL"
else
    ok "kill switch tắt (bình thường)"
    info "nếu bootloop: tạo file $KILL rồi respring"
fi
hr
echo "Xong."
