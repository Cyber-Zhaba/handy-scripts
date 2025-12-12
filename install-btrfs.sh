#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

die() {
    echo -e "${RED}ERROR: $*${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}[INFO] $*${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $*${NC}"
}

usage() {
    cat <<EOF
Usage:
    curl -fsSL https://raw.githubusercontent.com/.../install-btrfs.sh | bash -s -- [options]

Options:
    -d, --device DEV        Btrfs device (required, e.g. /dev/sda2 or /dev/mapper/root)
    -m, --mountpoint DIR    Temporary mount point (default: /mnt)
    -b, --boot PART         EFI/boot partition to mount to \${mountpoint}/boot (optional)
    -f, --force             Wipe device without confirmation (DANGEROUS!)
    -h, --help              Show this help

Example:
    curl -fsSL https://raw.githubusercontent.com/user/btrfs-installer/main/install-btrfs.sh \\
        | bash -s -- -d /dev/mapper/root -b /dev/nvme0n1p1 -f
EOF
    exit 1
}

# ===============
# Parse arguments
# ===============
DEVICE=""
MOUNTPOINT="/mnt"
BOOT_PART=""
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--device)     DEVICE="$2";      shift 2 ;;
        -m|--mountpoint) MOUNTPOINT="$2"; shift 2 ;;
        -b|--boot)       BOOT_PART="$2";  shift 2 ;;
        -f|--force)      FORCE=1;         shift ;;
        -h|--help)       usage ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ -z "$DEVICE" ]] && die "Device is required (-d / --device)"

[[ -b "$DEVICE" ]] || die "Device $DEVICE does not exist or is not a block device"

if [[ $FORCE -eq 0 ]]; then
    echo "======================================================="
    echo "WARNING! This will COMPLETELY ERASE all data on $DEVICE"
    echo "======================================================="
    read -rp "Type 'YES' to continue: " confirm
    [[ "$confirm" == "YES" ]] || die "Aborted by user"
fi

# ====
# Main
# ====

info "Creating Btrfs filesystem on $DEVICE ..."
mkfs.btrfs -f "$DEVICE" >/dev/null

info "Mounting root subvolume to $MOUNTPOINT ..."
mount -t btrfs "$DEVICE" "$MOUNTPOINT"

info "Creating standard subvolumes ..."
btrfs subvolume create "$MOUNTPOINT/@"
btrfs subvolume create "$MOUNTPOINT/@home"
btrfs subvolume create "$MOUNTPOINT/@var_log"
btrfs subvolume create "$MOUNTPOINT/@var_cache"
btrfs subvolume create "$MOUNTPOINT/@snapshots"

info "Umounting temporary mount ..."
umount "$MOUNTPOINT"

# Root subvolume
info "Mounting @ as root filesystem ..."
mount -o compress=zstd:1,noatime,subvol=@ "$DEVICE" "$MOUNTPOINT"

# Standard directories
mkdir -p "$MOUNTPOINT"/{home,var/log,var/cache,.snapshots,boot}

info "Mounting subvolumes ..."
mount -o compress=zstd:1,noatime,subvol=@home        "$DEVICE" "$MOUNTPOINT/home"
mount -o compress=zstd:1,noatime,subvol=@var_log     "$DEVICE" "$MOUNTPOINT/var/log"
mount -o compress=zstd:1,noatime,subvol=@var_cache   "$DEVICE" "$MOUNTPOINT/var/cache"
mount -o compress=zstd:1,noatime,subvol=@snapshots   "$DEVICE" "$MOUNTPOINT/.snapshots"

# Optional boot/EFI partition
if [[ -n "$BOOT_PART" ]]; then
    [[ -b "$BOOT_PART" ]] || die "Boot partition $BOOT_PART is not a block device"
    info "Mounting boot partition $BOOT_PART to $MOUNTPOINT/boot ..."
    mkdir -p "$MOUNTPOINT/boot"
    mount "$BOOT_PART" "$MOUNTPOINT/boot"
fi

info "Btrfs installation completed successfully!"
echo
echo "Root filesystem is mounted at: $MOUNTPOINT"
echo "Subvolumes:"
btrfs subvolume list -a "$MOUNTPOINT" | sed 's/^/  /'
echo
echo "You can now chroot or continue installation."

