#!/bin/sh
# Cấu hình dùng chung cho các script chạy từ máy build.
# Ghi đè bằng biến môi trường, ví dụ:  DEVICE_PORT=2222 ./scripts/install.sh

DEVICE_HOST="${DEVICE_HOST:-127.0.0.1}"
DEVICE_PORT="${DEVICE_PORT:-2222}"
DEVICE_USER="${DEVICE_USER:-mobile}"
PACKAGE_ID="com.opencarplay.tweak"

ssh_dev() { ssh -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_HOST" "$@"; }
scp_dev() { scp -P "$DEVICE_PORT" "$@"; }

# Nhắc: mở đường hầm USB trước khi dùng —  iproxy $DEVICE_PORT 22 &
