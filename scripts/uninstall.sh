#!/bin/sh
set -e
DIR=$(dirname "$0"); . "$DIR/_common.sh"
ssh_dev "sudo dpkg -r $PACKAGE_ID; sudo killall -9 CarPlay 2>/dev/null; true"
echo "Đã gỡ. Respring nếu cần: sudo sbreload"
