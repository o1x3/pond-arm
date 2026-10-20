#!/usr/bin/env bash
# Setup of the ALARM aarch64 builder container (run as root inside it).
set -euo pipefail

# Idempotent: pond-pi runs it before every build.
# Containers have no seccomp/landlock support for pacman's download sandbox.
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
# ALARM mirrors stall now and then; don't let pacman's 10 s timeout abort a build.
grep -q '^DisableDownloadTimeout' /etc/pacman.conf || sed -i '/^\[options\]/a DisableDownloadTimeout' /etc/pacman.conf
[[ -d /etc/pacman.d/gnupg ]] || { pacman-key --init && pacman-key --populate archlinuxarm; }
retry() { local i; for i in 1 2 3; do "$@" && return 0; echo "retrying ($i/3): $*" >&2; sleep 10; done; return 1; }
retry pacman -Syu --noconfirm --needed \
  base-devel git arch-install-scripts rust nodejs npm cmake ninja \
  qt6-shadertools qt6-tools wayland-protocols pkgconf catch2 \
  dosfstools mtools btrfs-progs zstd xz libarchive python-yaml qemu-img librsvg
id builder >/dev/null 2>&1 || useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
