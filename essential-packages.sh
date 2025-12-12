#!/bin/bash

pacstrap -K /mnt base base-devel linux linux-firmware fish git vim cryptsetup dhcpcd iwd openssh man sudo rsync \
  btrfs-progs \
  efibootmgr \
  limine \
  intel-ucode

