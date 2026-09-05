#!/bin/sh
# Build + cài lên thiết bị. Chạy từ máy build.
set -e
DIR=$(dirname "$0"); . "$DIR/_common.sh"

echo "==> build"
make clean package "$@"

DEB=$(ls -t packages/*.deb | head -1)
[ -n "$DEB" ] || { echo "không tìm thấy .deb"; exit 1; }
echo "==> deb: $DEB"

echo "==> copy"
scp_dev "$DEB" "$DEVICE_USER@$DEVICE_HOST:/tmp/"

echo "==> install (cần quyền root trên thiết bị)"
ssh_dev "sudo dpkg -i /tmp/$(basename "$DEB") && sudo rm -f /tmp/$(basename "$DEB")"

echo "==> restart process liên quan"
ssh_dev "sudo killall -9 CarPlay 2>/dev/null; true"
echo "Nếu thay đổi ảnh hưởng SpringBoard, chạy: ssh -p $DEVICE_PORT $DEVICE_USER@$DEVICE_HOST sudo sbreload"
