#!/bin/bash

pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring

rm -rf /mnt/var/cache/pacman/pkg/*

pacman -Syy

pacstrap -K /mnt base base-devel linux linux-firmware fish git vim cryptsetup dhcpcd iwd reflector openssh man sudo rsync \
  btrfs-progs \
  efibootmgr \
  limine \
  intel-ucode

genfstab -U /mnt >>/mnt/etc/fstab
