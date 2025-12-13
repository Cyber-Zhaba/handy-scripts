#!/bin/bash

pacman -Syy

pacstrap -K /mnt base base-devel linux linux-firmware fish git vim cryptsetup dhcpcd iwd reflector openssh man sudo rsync \
  btrfs-progs \
  efibootmgr \
  limine \
  intel-ucode

genfstab -U /mnt >> /mnt/etc/fstab

