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
NAME_URL="https://raw.githubusercontent.com/Cyber-Zhaba/handy-scripts/refs/heads/master/names.txt"
SURNAME_URL="https://raw.githubusercontent.com/Cyber-Zhaba/handy-scripts/refs/heads/master/surnames.txt"

# Скачиваем и выбираем по 6 случайных
mapfile -t NAME  < <(curl -s "$NAME_URL" | shuf -n 20)
mapfile -t SURNAME < <(curl -s "$SURNAME_URL" | shuf -n 20)

echo
echo "Выбери имя машины (или введи своё):"
for i in {0..2}; do
    NICKNAME="${NAME[$i]}-${SURNAME[$i]}"
    echo "   $((i+1))) $NICKNAME"
done
echo "   4) Ввести своё"

while true; do
    ask "Твой выбор [1-4]: "
    read -r choice
    case "$choice" in
        [1-3]) HOSTNAME="${NAME[$((choice-1))]}-${SURNAME[$((choice-1))]}"; break ;;
        4) ask "Введи имя хоста вручную: "; read -r HOSTNAME; break ;;
        *) echo "Введи число от 1 до 4" ;;
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
ask "Логин нового пользователя (по умолчанию arseny): "
read -r username
username=${username:-arseny}

if id "$username" >/dev/null 2>&1; then
    info "Пользователь '$username' уже существует — пропускаем создание."
else
    info "Создаём пользователя '$username'"
    useradd -m -G wheel,audio,video,storage,optical "$username"
    passwd
fi

# 5. sudo без пароля для wheel (можно потом поменять)
info "Настраиваем sudo для %wheel"
sed -i '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' /etc/sudoers

info "Включаем инет"
systemctl enable dhcpcd
systemctl enable iwd

if [[ ! -d /sys/firmware/efi ]]; then
    die "Limine только для UEFI! У тебя BIOS — используй GRUB."
fi

info "Установка Limine — самый красивый загрузчик 2025 года"

info "Доступные диски и разделы:"
lsblk -dno NAME,SIZE,MODEL | grep -v loop
echo
ask "На каком диске находится EFI-раздел? (например nvme0n1 или sda): "
read -r disk
disk="/dev/$disk"

ask "Номер EFI-раздела на этом диске? (обычно 1): "
read -r part_num

EFI_PART="${disk}${part_num}"

[[ -b "$EFI_PART" ]] || die "Раздел $EFI_PART не существует!"

# Монтируем EFI, если ещё не примонтирован
[[ -d /boot/EFI ]] || mkdir -p /boot/EFI
mount "$EFI_PART" /boot/EFI

# Копируем файлы Limine
mkdir -p /boot/EFI/limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/

# Получаем UUID LUKS-устройства (если есть) и root-маппера
if cryptsetup status root >/dev/null 2>&1; then
    LUKS_UUID=$(blkid -s UUID -o value /dev/mapper/root | head -1)
    CRYPT_LINE="cryptdevice=UUID=$LUKS_UUID:root"
else
    CRYPT_LINE=""
fi

# Генерируем limine.cfg
cat > /boot/limine.cfg <<EOF
TIMEOUT=3

DEFAULT ENTRY=Arch Linux

:Arch Linux
    PROTOCOL=linux
    KERNEL_PATH=boot():/vmlinuz-linux
    CMDLINE=root=/dev/mapper/root rw rootflags=subvol=@ $CRYPT_LINE quiet splash
    MODULE_PATH=boot():/initramfs-linux.img
    MODULE_PATH=boot():/initramfs-linux-fallback.img
EOF

info "limine.cfg создан:"
cat /boot/limine.cfg

# Устанавливаем загрузчик через efibootmgr
info "Добавляем запись в UEFI"
efibootmgr --create \
    --disk "$disk" \
    --part "$part_num" \
    --label "Arch Linux (Limine)" \
    --loader '\\EFI\\limine\\BOOTX64.EFI' \
    --unicode

# Переразмещаем файлы Limine на EFI-раздел (на случай обновления)
limine-deploy /boot || true

info "Limine успешно установлен!"

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

