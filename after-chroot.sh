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

info "Настраиваем mkinitcpio для LUKS + Btrfs + subvol=@"
sed -i '/^MODULES=/c\MODULES=(btrfs)' /etc/mkinitcpio.conf
sed -i '/^BINARIES=/c\BINARIES=(/usr/bin/btrfs)' /etc/mkinitcpio.conf
sed -i '/^HOOKS=/c\HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)' /etc/mkinitcpio.conf
cat > /etc/mkinitcpio.conf.d/hooks.conf <<'EOF'
EOF

info "Пересобираем initramfs (linux и linux-lts, если есть)"
mkinitcpio -P

info "Установка Limine — лучший загрузчик 2025 года"
# Собираем список всех дисков (без loop, ram, без партиций)
mapfile -t DISKS < <(lsblk -dno NAME | grep -E '^(sd|nvme|hd|vd)' | sort)

if [[ ${#DISKS[@]} -eq 0 ]]; then
    die "Не найдено ни одного диска! Что-то пошло не так."
fi

echo
echo "Выбери диск, на котором находится EFI-раздел:"
for i in "${!DISKS[@]}"; do
    SIZE=$(lsblk -dno SIZE "/dev/${DISKS[$i]}" | head -1)
    MODEL=$(lsblk -dno MODEL "/dev/${DISKS[$i]}" | head -1 | xargs)
    printf "   %d) %s  (%s  %s)\n" $((i+1)) "${DISKS[$i]}" "$SIZE" "$MODEL"
done
echo "   $(( ${#DISKS[@]} + 1 ))) Ввести вручную"

while true; do
    ask "Твой выбор [1-$((${#DISKS[@]} + 1))]: "
    read -r choice
    if [[ "$choice" -ge 1 && "$choice" -le ${#DISKS[@]} ]]; then
        DISK="/dev/${DISKS[$((choice-1))]}"
        break
    elif [[ "$choice" -eq $(( ${#DISKS[@]} + 1 )) ]]; then
        ask "Введи имя диска вручную (например nvme0n1 или sda): "
        read -r manual_disk
        DISK="/dev/$manual_disk"
        [[ -b "$DISK" ]] && break || echo "Такого диска нет, попробуй ещё"
    else
        echo "Введи корректный номер"
    fi
done

# Теперь партиции на выбранном диске (только существующие блок-устройства)
mapfile -t PARTS < <(lsblk -lno NAME,TYPE "$DISK" | grep part | awk '{print $1}' | sort)

if [[ ${#PARTS[@]} -eq 0 ]]; then
    die "На диске $DISK нет разделов!"
fi

echo
echo "Выбери EFI-раздел (обычно FAT32, ~100–512M):"
for i in "${!PARTS[@]}"; do
    FULL_PART="/dev/${PARTS[$i]}"
    SIZE=$(lsblk -no SIZE "$FULL_PART" | head -1)
    FSTYPE=$(lsblk -no FSTYPE "$FULL_PART" | head -1)
    printf "   %d) %s  (%s  %s)\n" $((i+1)) "${PARTS[$i]}" "$SIZE" "$FSTYPE"
done
echo "   $(( ${#PARTS[@]} + 1 ))) Ввести вручную"

while true; do
    ask "Твой выбор [1-$((${#PARTS[@]} + 1))]: "
    read -r choice
    if [[ "$choice" -ge 1 && "$choice" -le ${#PARTS[@]} ]]; then
        EFI_PART="/dev/${PARTS[$((choice-1))]}"
        break
    elif [[ "$choice" -eq $(( ${#PARTS[@]} + 1 )) ]]; then
        ask "Введи полный путь к EFI-разделу (например /dev/nvme0n1p1): "
        read -r manual_part
        [[ -b "$manual_part" ]] && EFI_PART="$manual_part" && break || echo "Такого раздела нет"
    else
        echo "Введи корректный номер"
    fi
done

info "Выбран EFI-раздел: $EFI_PART"

# Монтируем EFI, если ещё не примонтирован
mkdir -p /boot/EFI
if ! mountpoint -q /boot/EFI; then
    mount "$EFI_PART" /boot/EFI
    info "EFI-раздел примонтирован в /boot/EFI"
fi

# Копируем BOOTX64.EFI
mkdir -p /boot/EFI/limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/

# Определяем cryptdevice (если LUKS)
CRYPT_LINE=""
if [[ -b /dev/mapper/root ]] && cryptsetup status root >/dev/null 2>&1; then
    # Ищем устройство, на котором смонтирован /dev/mapper/root
    LUKS_DEV=$(lsblk -no PKNAME /dev/mapper/root | head -1)
    if [[ -n "$LUKS_DEV" ]] && [[ -b "/dev/$LUKS_DEV" ]]; then
        LUKS_UUID=$(blkid -s UUID -o value "/dev/$LUKS_DEV")
        if [[ -n "$LUKS_UUID" ]]; then
            CRYPT_LINE="cryptdevice=UUID=$LUKS_UUID:root"
            info "Обнаружен LUKS → добавлен параметр: $CRYPT_LINE"
        fi
    fi
fi

# Создаём limine.cfg
cat > /boot/limine/limine.cfg <<EOF
TIMEOUT=3

DEFAULT ENTRY=Arch Linux

:Arch Linux
    PROTOCOL=linux
    KERNEL_PATH=boot():/vmlinuz-linux
    CMDLINE=root=/dev/mapper/root rw rootflags=subvol=@ $CRYPT_LINE quiet splash
    MODULE_PATH=boot():/initramfs-linux.img
    MODULE_PATH=boot():/initramfs-linux-fallback.img
EOF

info "Создан /boot/limine/limine.cfg"

PART_NUMBER="${EFI_PART##*[^0-9]}"

# Добавляем загрузочную запись
efibootmgr --create \
    --disk "$DISK" \
    --part "$PART_NUMBER" \
    --label "Arch Linux (Limine)" \
    --loader '\\EFI\\limine\\BOOTX64.EFI' \
    --unicode 'quiet splash'

# Финальная деплоя
limine-deploy /boot || true

info "Limine успешно установлен и добавлен в UEFI!"

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

