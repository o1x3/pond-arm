#!/usr/bin/env bash
# Build a flashable Pond image for Raspberry Pi 5 (run as root in the builder).
#   p1  FAT32 "PONDBOOT"  firmware, kernel, initramfs, config.txt, cmdline.txt
#   p2  btrfs "POND_ROOT" Pond's subvolume layout; grows to fill the card on first boot
# The filesystems are built from directories (mkfs --rootdir, mtools), so no
# loop devices or mounts are needed.
set -euo pipefail

P=/p                       # project checkout
W=/w/image                 # scratch space (case-sensitive volume)
REPO=/w/repo               # local pond-pi repo from build-packages.sh
OUT=${OUT:-/p/out}
VERSION=${VERSION:-$(date -u +%Y.%m.%d)}
NAME=pond-pi5-$VERSION
BOOT_MIB=512
SLACK_MIB=1536             # free space on root before first-boot growth

# Pond's btrfs layout (iso-installer src/backend/model.py SUBVOLUMES).
SUBVOLUMES=("@:/" "@home:/home" "@root:/root" "@srv:/srv" "@log:/var/log" "@cache:/var/cache"
            "@tmp:/var/tmp" "@nix:/nix" "@flatpak:/var/lib/flatpak" "@usr-local:/usr/local"
            "@snapshots:/.snapshots")
ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
ROOT_ARM64_TYPE=b921b045-1df0-41c3-af44-4c6f280d3fae

rm -rf "$W"
mkdir -p "$W/stage/@" "$OUT"
ROOT=$W/stage/@

# --- packages --------------------------------------------------------------
sed '/^\[pond-pi\]/,$d' /etc/pacman.conf > "$W/pacman.conf"
printf '\n[pond-pi]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$REPO" >> "$W/pacman.conf"
mapfile -t packages < <(grep -vE '^\s*(#|$)' "$P/packages.txt")
pacstrap -C "$W/pacman.conf" -G -M "$ROOT" "${packages[@]}" python-yaml

# --- Pond configuration ----------------------------------------------------
# Files land root-owned; existing directories keep their packaged owner and mode.
tar -C "$P/overlay" --owner=0 --group=0 --exclude=__pycache__ -cf - . | tar -C "$ROOT" --no-overwrite-dir -xf -
chmod 750 "$ROOT/etc/sudoers.d"
chmod 440 "$ROOT"/etc/sudoers.d/10-*
# Pond's useradd defaults name the users group by its GID on Pond (982).
users_gid=$(awk -F: '$1 == "users" { print $3 }' "$ROOT/etc/group")
sed -i "s/^GROUP=.*/GROUP=$users_gid/" "$ROOT/etc/default/useradd"
echo 'VARIANT="Raspberry Pi 5"' >> "$ROOT/etc/os-release"
echo 'VARIANT_ID=rpi5' >> "$ROOT/etc/os-release"
echo pond > "$ROOT/etc/hostname"
echo 'en_US.UTF-8 UTF-8' > "$ROOT/etc/locale.gen"
printf 'LANG=en_US.UTF-8\n' > "$ROOT/etc/locale.conf"
ln -sf /usr/share/zoneinfo/UTC "$ROOT/etc/localtime"

# pacman.conf: ALARM repos with Pond's options; Pond's own x86_64 repo has no
# aarch64 builds, so Pond packages update only by rebuilding this image.
sed -i -e 's/^#Color/Color/' -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' \
    -e '/^\[options\]/a DisableDownloadTimeout' "$ROOT/etc/pacman.conf"

# --- boot ------------------------------------------------------------------
ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)
ROOT_PARTUUID=$(cat /proc/sys/kernel/random/uuid)
BOOT_PARTUUID=$(cat /proc/sys/kernel/random/uuid)
DISK_UUID=$(cat /proc/sys/kernel/random/uuid)
BOOT_VOLID=$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')

echo "root=PARTUUID=$ROOT_PARTUUID rootfstype=btrfs rootflags=subvol=@ rw rootwait console=tty1 quiet splash loglevel=3 plymouth.ignore-serial-consoles" \
    > "$ROOT/boot/cmdline.txt"
{
    for entry in "${SUBVOLUMES[@]}"; do
        printf 'UUID=%s  %s  btrfs  rw,relatime,compress=zstd:1,subvol=%s  0 0\n' "$ROOT_UUID" "${entry#*:}" "${entry%%:*}"
    done
    echo 'tmpfs  /tmp  tmpfs  defaults,noatime,mode=1777  0 0'
    echo "PARTUUID=$BOOT_PARTUUID  /boot  vfat  umask=0077  0 2"
} > "$ROOT/etc/fstab"

arch-chroot "$ROOT" bash -euo pipefail -c '
    locale-gen >/dev/null
    passwd -l root >/dev/null
    systemctl preset-all >/dev/null 2>&1
    systemctl --global preset-all >/dev/null 2>&1
    systemctl set-default graphical.target >/dev/null 2>&1
    mkinitcpio -P
'

# --- make the image generic -------------------------------------------------
rm -rf "$ROOT/etc/pacman.d/gnupg" "$ROOT/var/cache/pacman/pkg/"* "$ROOT"/etc/ssh/ssh_host_*
: > "$ROOT/etc/machine-id"
rm -f "$ROOT/var/lib/dbus/machine-id" "$ROOT/var/lib/systemd/random-seed" "$ROOT/var/lib/systemd/credential.secret"
find "$ROOT/var/log" -type f -delete

# --- filesystems -----------------------------------------------------------
mkdir "$W/boot"
cp -a "$ROOT/boot/." "$W/boot/"
find "$ROOT/boot" -mindepth 1 -delete

subvol_args=()
for entry in "${SUBVOLUMES[@]}"; do
    sub=${entry%%:*} mount=${entry#*:}
    if [[ $sub != @ ]]; then
        mkdir -p "$ROOT$mount" "$W/stage/$sub"
        cp -a "$ROOT$mount/." "$W/stage/$sub/"
        find "$ROOT$mount" -mindepth 1 -delete
        subvol_args+=(--subvol "$sub")
    fi
done
chmod 750 "$ROOT/.snapshots" "$W/stage/@snapshots"

used_mib=$(du -sm --apparent-size "$W/stage" | cut -f1)
root_mib=$(( used_mib + used_mib / 10 + SLACK_MIB ))
truncate -s "${root_mib}M" "$W/root.img"
mkfs.btrfs -q -f -L POND_ROOT -U "$ROOT_UUID" -O ^block-group-tree --compress zstd:1 \
    --rootdir "$W/stage" --subvol default:@ "${subvol_args[@]}" "$W/root.img"

truncate -s "${BOOT_MIB}M" "$W/boot.img"
mkfs.fat -F 32 -n PONDBOOT -i "$BOOT_VOLID" "$W/boot.img" >/dev/null
mcopy -s -i "$W/boot.img" "$W/boot/"* ::/

# --- disk image ------------------------------------------------------------
IMG=$W/$NAME.img
truncate -s "$(( 1 + BOOT_MIB + root_mib + 1 ))M" "$IMG"
sfdisk -q "$IMG" <<EOF
label: gpt
label-id: $DISK_UUID
unit: sectors
start=2048, size=$(( BOOT_MIB * 2048 )), type=$ESP_TYPE, uuid=$BOOT_PARTUUID, name="PONDBOOT"
start=$(( (1 + BOOT_MIB) * 2048 )), size=$(( root_mib * 2048 )), type=$ROOT_ARM64_TYPE, uuid=$ROOT_PARTUUID, name="POND_ROOT"
EOF
dd if="$W/boot.img" of="$IMG" bs=1M seek=1 conv=notrunc,sparse status=none
dd if="$W/root.img" of="$IMG" bs=1M seek=$(( 1 + BOOT_MIB )) conv=notrunc,sparse status=none

xz -T0 -6 -k -f "$IMG"
mv -f "$IMG.xz" "$OUT/"
(cd "$OUT" && sha256sum "$NAME.img.xz" > "$NAME.img.xz.sha256")
printf '%s %s\n' "$(stat -c %s "$IMG")" "$(sha256sum "$IMG" | cut -d' ' -f1)" > "$OUT/$NAME.img.extract"
rm -rf "$W/stage" "$W/boot" "$W/boot.img" "$W/root.img"
echo ">>> $OUT/$NAME.img.xz (raw image kept at $IMG)"
