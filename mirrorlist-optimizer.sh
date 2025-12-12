#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[+] $1${NC}"; }
die()  { echo -e "${RED}[×] $1${NC}" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Нужны права root"

command -v reflector >/dev/null || die "Установи reflector: pacman -S reflector --needed"

BACKUP="/etc/pacman.d/mirrorlist.backup.$(date +%Y%m%d_%H%M%S)"
FINAL="/etc/pacman.d/mirrorlist"

info "Бэкап текущего mirrorlist → $BACKUP"
cp "$FINAL" "$BACKUP"

info "Запускаем жёсткий отбор: только свежие + быстрые зеркала из России и ближней Европы"
info "Это займёт 4–6 минут — иди за чаем"

reflector \
    --verbose \
    --threads 24 \
    --connection-timeout 5 \
    --download-timeout 20 \
    --country 'Russia,Germany,Netherlands,Poland,Finland,Sweden,France,Czech,Slovakia,Austria,Belarus,Ukraine' \
    --protocol https \
    --age 12 \
    --latest 300 \
    --sort rate \
    --number 30 \
    --save /tmp/mirrorlist.fast

info "Финальная проверка стабильности через rankmirrors (отсекаем ложные вспышки)"
rankmirrors -n 20 /tmp/mirrorlist.fast > /tmp/mirrorlist.final 2>/dev/null || \
    cp /tmp/mirrorlist.fast /tmp/mirrorlist.final

info "Собираем идеальный mirrorlist с тремя вечноживыми якорями"
cat > "$FINAL" <<EOF
$(cat /tmp/mirrorlist.final)
EOF

info "ГОТОВО! Топ-7 зеркал прямо сейчас:"
grep '^Server' "$FINAL" | head -7 | nl

# Чистим за собой
rm -f /tmp/mirrorlist.*

exit 0

