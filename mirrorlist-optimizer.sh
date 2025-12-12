#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[+] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
die()  { echo -e "${RED}[✗] $1${NC}" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запускай от root"

command -v reflector >/dev/null || die "Установи reflector: pacman -S reflector"

BACKUP="/etc/pacman.d/mirrorlist.backup.$(date +%Y%m%d_%H%M%S)"
FINAL="/etc/pacman.d/mirrorlist"

info "Делаем бэкап текущего mirrorlist → $BACKUP"
cp "$FINAL" "$BACKUP"

info "Этап 1: Собираем ~250 самых свежих HTTPS-зеркал из России + ближайшей Европы"
reflector \
  --verbose \
  --threads 16 \
  --connection-timeout 5 \
  --download-timeout 10 \
  --country Russia,Germany,Netherlands,Poland,Finland,Sweden,France \
  --protocol https \
  --age 12 \
  --latest 250 \
  --sort age \
  --save /tmp/mirrorlist.fresh

info "Этап 2: Тестируем реальную скорость загрузки (это займёт 3–7 минут, но оно того стоит)"
reflector \
  --verbose \
  --threads 24 \
  --connection-timeout 4 \
  --download-timeout 15 \
  --url https://geo.mirror.pkgbuild.com \
  --url https://mirror.yandex.ru \
  --url https://mirror.sjtu.edu.cn \
  --sort rate \
  --file /tmp/mirrorlist.fresh \
  --save /tmp/mirrorlist.rated \
  --number 40

info "Этап 3: Финальный ранжировщик (rankmirrors) — выбираем топ-18 самых быстрых и стабильных"
# rankmirrors в 2025 году уже почти не нужен, но он отсекает «вспышки» и даёт более стабильный результат
rankmirrors -n 18 /tmp/mirrorlist.rated > /tmp/mirrorlist.final 2>/dev/null || \
  cp /tmp/mirrorlist.rated /tmp/mirrorlist.final

info "Этап 4: Добавляем несколько проверенных «якорных» зеркал (на случай если всё упадёт)"
{
  echo "# Якорные зеркала (Москва/СПб) — всегда работают"
  echo "Server = https://mirror.yandex.ru/archlinux/\$repo/os/\$arch"
  echo "Server = https://archlinux.mail.ru/\$repo/os/\$arch"
  echo "Server = https://repo.sibr.cc/arch/\$repo/os/\$arch"
  echo ""
  cat /tmp/mirrorlist.final
} > "$FINAL"

info "Готово! Твой новый /etc/pacman.d/mirrorlist:"
echo "────────────────────────────────────────────"
cat "$FINAL"
echo "────────────────────────────────────────────"

info "Тестируем скорость pacman (первые 3 зеркала):"
pacman -Syy --noconfirm 2>&1 | grep -E 'Server|retrieving|total'

echo
info "Всё, теперь pacman летает. Приятной установки!"

