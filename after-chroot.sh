#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+] $1${NC}"; }
ask()   { echo -e "${YELLOW}[?] $1${NC}"; }
die()   { echo -e "${RED}[✗] $1${NC}" >&2; exit 1; }

# 1. Часы — Москва навсегда
info "Настраиваем часовой пояс Europe/Moscow"
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
timedatectl set-ntp true

# 2. Локали
info "Генерируем локали: en_GB, en_US, ru_RU"
sed -i '/^#en_GB.UTF-8/s/^#//; /^#en_US.UTF-8/s/^#//; /^#ru_RU.UTF-8/s/^#//' /etc/locale.gen
locale-gen

cat > /etc/locale.conf <<EOF
LANG=en_US.UTF-8
LC_TIME=en_GB.UTF-8
EOF

# 3. Генератор имён хоста в стиле nano-wombat
info "Генерируем крутые имена хостов (RFC 1178 compatible)"

# Списки слов — лежат у меня на гитхабе, можно форкнуть и поменять под себя
NAME_URL="https://github.com/Cyber-Zhaba/handy-scripts/raw/refs/heads/master/names.txt"
SURNAME_URL="https://github.com/Cyber-Zhaba/handy-scripts/raw/refs/heads/master/surnames.txt"

# Скачиваем и выбираем по 6 случайных
mapfile -t NAME  < <(curl -s "$NAME_URL" | shuf -n 20)
mapfile -t SURNAME < <(curl -s "$SURNAME_URL" | shuf -n 20)

echo
echo "Выбери имя машины (или введи своё):"
for i in {0..5}; do
    NICKNAME="${NAME[$i]}-${SURNAME[$i]}"
    echo "   $((i+1))) $NICKNAME"
done
echo "   7) Ввести своё"

while true; do
    ask "Твой выбор [1-7]: "
    read -r choice
    case "$choice" in
        [1-6]) HOSTNAME="${NAME[$((choice-1))]}-${SURNAME[$((choice-1))]}"; break ;;
        7) ask "Введи имя хоста вручную: "; read -r HOSTNAME; break ;;
        *) echo "Введи число от 1 до 7" ;;
    esac
done

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

info "Хостнейм установлен: $HOSTNAME"

# 4. Создаём пользователя
ask "Логин нового пользователя (по умолчанию yovko): "
read -r username
username=${username:-yovko}

useradd -m -G wheel,audio,video,storage,optical "$username"
passwd "$username"

# 5. sudo без пароля для wheel (можно потом поменять)
info "Настраиваем sudo для %wheel"
sed -i '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' /etc/sudoers

# 6. Устанавливаем grub по умолчанию (если EFI)
if [[ -d /sys/firmware/efi ]]; then
    info "Обнаружен EFI — ставим grub + os-prober"
    pacman -S --noconfirm grub efibootmgr os-prober
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
else
    info "Обнаружен BIOS — ставим обычный grub"
    pacman -S --noconfirm grub os-prober
    grub-install --target=i386-pc /dev/$(lsblk -no PKNAME $(df /mnt | tail -1 | awk '{print $1}'))
    grub-mkconfig -o /boot/grub/grub.cfg
fi

info "Всё готово!"
echo
echo "   Хостнейм: $HOSTNAME"
echo "   Пользователь: $username (в группе wheel, sudo без пароля)"
echo "   Локаль: en_US + en_GB даты"
echo "   Часы: Europe/Moscow + NTP"
echo
echo "Можешь выходить из chroot и делать reboot:"
echo "   exit    # выйти из chroot"
echo "   umount -R /mnt"
echo "   reboot"

exit 0

