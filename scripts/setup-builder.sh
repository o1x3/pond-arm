#!/usr/bin/env bash
# One-time setup of the ALARM aarch64 builder container (run as root inside it).
set -euo pipefail

# Containers have no seccomp/landlock support for pacman's download sandbox.
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --noconfirm --needed \
  base-devel git arch-install-scripts rust nodejs npm cmake ninja \
  qt6-shadertools qt6-tools wayland-protocols pkgconf catch2 \
  dosfstools mtools btrfs-progs zstd xz libarchive python-yaml qemu-img
id builder >/dev/null 2>&1 || useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
