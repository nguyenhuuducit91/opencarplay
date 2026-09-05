#!/bin/sh
# Thu log OpenCarPlay. Ưu tiên idevicesyslog (chạy trên máy build, không cần SSH).
DIR=$(dirname "$0"); . "$DIR/_common.sh"
OUT="${1:-opencarplay-$(date +%Y%m%d-%H%M%S).log}"

if command -v idevicesyslog >/dev/null 2>&1; then
    echo "==> idevicesyslog -> $OUT   (Ctrl-C để dừng)"
    idevicesyslog | grep --line-buffered -iE 'opencarplay|carplay' | tee "$OUT"
else
    echo "idevicesyslog không có; thử qua SSH"
    ssh_dev "log stream --predicate 'subsystem == \"com.opencarplay.tweak\"' --style compact" | tee "$OUT"
fi
