#!/bin/bash
# First boot on a freshly flashed card: grow root to fill the device, then
# create this machine's own pacman keyring (the image ships without one).
set -euo pipefail

source=$(findmnt -no SOURCE / | sed 's/\[.*//')
name=$(basename "$source")
disk=/dev/$(lsblk -no PKNAME "$source")
number=$(cat "/sys/class/block/$name/partition")

# Move the backup GPT header to the real end of the device, then grow root.
sfdisk --no-reread --no-tell-kernel --relocate gpt-bak-std "$disk"
echo ', +' | sfdisk --no-reread --no-tell-kernel --force -N "$number" "$disk"
partx -u -n "$number" "$disk"
btrfs filesystem resize max /

if [[ ! -d /etc/pacman.d/gnupg ]]; then
    pacman-key --init
    pacman-key --populate        # every keyring in /usr/share/pacman/keyrings
fi
