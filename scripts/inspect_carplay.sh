#!/bin/sh
# Khảo sát CarPlay trên thiết bị. CHẠY TRÊN THIẾT BỊ.
# Kết quả dùng để điền RESEARCH-DEVICE.md (xem RESEARCH.md §7).

echo "=== process ==="
ps -Ao pid,ppid,comm | grep -iE 'carplay|springboard|InCall|MusicUI' | grep -v grep

echo
echo "=== bundle CarPlay trên hệ thống ==="
for p in /System/Library/CoreServices/CarPlay*.app \
         /System/Library/CoreServices/CarPlayTemplateUIHost.app \
         /System/Library/CoreServices/CarPlaySettings.app; do
    [ -d "$p" ] || continue
    ID=$(plutil -p "$p/Info.plist" 2>/dev/null | grep CFBundleIdentifier | sed 's/.*=> *//;s/"//g')
    echo "  $p  ->  $ID"
done

echo
echo "=== framework CarPlay ==="
for f in CarKit CarPlayServices CarPlayUIServices CarPlaySupport CarPlayUI; do
    p="/System/Library/PrivateFrameworks/$f.framework"
    [ -d "$p" ] && echo "  có: $f" || echo "  THIẾU: $f"
done

echo
echo "=== preference domain liên quan ==="
ls -la /var/mobile/Library/Preferences/com.apple.carplay* 2>/dev/null
ls -la /var/mobile/Library/Preferences/com.apple.CarPlayApp* 2>/dev/null

echo
echo "=== danh sách app đã cài (bundle id) — nguồn cho AllowedApplications ==="
if command -v uicache >/dev/null 2>&1; then
    uicache -l 2>/dev/null | head -50
else
    ls -d /var/containers/Bundle/Application/*/*.app 2>/dev/null | head -30
fi
