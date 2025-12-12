#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[+] $1${NC}"; }
die()  { echo -e "${RED}[✗] $1${NC}" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запускай от root"

command -v reflector || die "reflector не установлен → pacman -S reflector"

BACKUP="/etc/pacman.d/mirrorlist.backup.$(date +%Y%m%d_%H%M%S)"
FINAL="/etc/pacman.d/mirrorlist"

info "Бэкап текущего mirrorlist → $BACKUP"
cp "$FINAL" "$BACKUP"

info "Этап 1/2: Собираем до 300 самых свежих зеркал (RU + ближняя Европа)"
reflector \
    --verbose \
    --threads 16 \
    --country Russia,Germany,Netherlands,Poland,Finland,Sweden,France,Czech,Slovakia,Austria,Belarus,Ukraine \
    --protocol https \
    --age 12 \
    --latest 300 \
    --sort age \
    --save /tmp/mirrorlist.candidates \
    --connection-timeout 6 \
    --download-timeout 12

info "Этап 2/2: Жёсткий тест скорости (4–9 минут, но результат — топ-1 в Москве)"
cat > /tmp/reflector-rate.conf <<EOF
--save /tmp/mirrorlist.rated
--sort rate
--number 40
--threads 24
--connection-timeout 5
--download-timeout 20
--verbose
EOF

reflector @"${TMPDIR:-/tmp}/reflector-rate.conf" --list /tmp/mirrorlist.candidates

info "Финальная сортировка через rankmirrors (отсекаем нестабильные вспышки)"
rankmirrors -n 18 /tmp/mirrorlist.rated > /tmp/mirrorlist.final 2>/dev/null || \
    cp /tmp/mirrorlist.rated /tmp/mirrorlist.final

info "Собираем финальный mirrorlist с якорями"
cat > "$FINAL" <<EOF
#
# Оптимизированный mirrorlist для Москвы — $(date +'%Y-%m-%d %H:%M')
# Скрипт: https://github.com/твой-ник/arch-tools
#

# Топ по реальной скорости (только что измерено)
$(cat /tmp/mirrorlist.final)
EOF

info "Готово! Топ-5 зеркал сейчас:"
head -n 15 "$FINAL" | grep '^Server' | nl

info "Тест pacman -Syy (первые зеркала):"
timeout 25 pacman -Syy --noconfirm 2>&1 | grep -E 'Server|total' || true

rm -f /tmp/mirrorlist.* /tmp/reflector-rate.conf

exit 0

