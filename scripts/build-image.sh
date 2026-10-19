#!/usr/bin/env bash
# Build a flashable Pond image for Raspberry Pi 5 (run as root in the builder).
#   p1  FAT32 "PONDBOOT"  firmware, kernel, initramfs, config.txt, cmdline.txt
#   p2  btrfs "POND_ROOT" Pond's subvolume layout; grows to fill the card on first boot
# The filesystems are built from directories (mkfs --rootdir, mtools), so no
# loop devices or mounts are needed.
#   QEMU_TEST=1  also write out/qemu/: the same rootfs plus ALARM's generic kernel
#   FROM=fs      reuse the last finished rootfs; only reassemble the images
set -euo pipefail

P=/p                       # project checkout
W=/w/image                 # scratch space (case-sensitive volume)
REPO=/w/repo               # local pond-pi repo from build-packages.sh
OUT=${OUT:-/p/out}
VERSION=${VERSION:-$(date -u +%Y.%m.%d)}
NAME=pond-pi5-$VERSION
BOOT_MIB=512
SLACK_MIB=256              # unallocated room after root for new btrfs chunks

# Pond's btrfs layout (iso-installer src/backend/model.py SUBVOLUMES).
SUBVOLUMES=("@:/" "@home:/home" "@root:/root" "@srv:/srv" "@log:/var/log" "@cache:/var/cache"
            "@tmp:/var/tmp" "@nix:/nix" "@flatpak:/var/lib/flatpak" "@usr-local:/usr/local"
            "@snapshots:/.snapshots")
ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
ROOT_ARM64_TYPE=b921b045-1df0-41c3-af44-4c6f280d3fae

ROOT=$W/stage/@
mkdir -p "$OUT"

# FROM=fs reuses a finished rootfs from the previous run (after its checks) and
# only rebuilds the filesystems and disk image.
if [[ ${FROM:-} == fs ]]; then
    [[ -f $W/rootfs.env ]] || { echo 'no finished rootfs to resume from'; exit 1; }
    source "$W/rootfs.env"
else
rm -rf "${W:?}"
mkdir -p "$W/stage/@"

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
echo 'KEYMAP=us' > "$ROOT/etc/vconsole.conf"
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
        printf 'UUID=%s  %s  btrfs  rw,noatime,compress=zstd:1,subvol=%s  0 0\n' "$ROOT_UUID" "${entry#*:}" "${entry%%:*}"
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
rm -rf "${ROOT:?}/etc/pacman.d/gnupg" "${ROOT:?}"/var/cache/pacman/pkg/* "${ROOT:?}"/etc/ssh/ssh_host_*
: > "$ROOT/etc/machine-id"
rm -f "$ROOT/var/lib/dbus/machine-id" "$ROOT/var/lib/systemd/random-seed" "$ROOT/var/lib/systemd/credential.secret"
find "$ROOT/var/log" -type f -delete

bash "$P/scripts/check-rootfs.sh" "$ROOT" | tee "$OUT/$NAME.compat.txt"
[[ ${PIPESTATUS[0]} == 0 ]] || { echo '!!! compatibility check failed'; exit 1; }
declare -p ROOT_UUID ROOT_PARTUUID BOOT_PARTUUID DISK_UUID BOOT_VOLID > "$W/rootfs.env"
fi

# --- image assembly --------------------------------------------------------
# QEMU has no Pi 5 machine and linux-rpi does not boot on `virt`, so the test
# variant adds ALARM's generic kernel modules (and writes that kernel plus an
# initramfs to out/qemu). Everything after the kernel is the release rootfs.
add_qemu_kernel() {
    local root=$1 kpkg kver
    mkdir -p "$W/pkg" "$OUT/qemu"
    pacman -Sw --noconfirm --cachedir "$W/pkg" linux-aarch64 >/dev/null
    kpkg=$(ls "$W"/pkg/linux-aarch64-[0-9]*.pkg.tar.* | grep -v '\.sig$')
    bsdtar -xf "$kpkg" -C "$root" usr/lib/modules
    kver=$(bsdtar -tf "$kpkg" | sed -n 's#^usr/lib/modules/\([0-9][^/]*\)/modules\.order$#\1#p' | head -1)
    [[ -n $kver ]] || { echo 'cannot find linux-aarch64 module version'; exit 1; }
    arch-chroot "$root" depmod "$kver"
    arch-chroot "$root" mkinitcpio -k "$kver" -g /var/tmp/initramfs-qemu.img >/dev/null
    mv "$root/var/tmp/initramfs-qemu.img" "$OUT/qemu/initramfs.img"
    bsdtar -xOf "$kpkg" boot/Image > "$OUT/qemu/Image"
    echo "$ROOT_PARTUUID" > "$OUT/qemu/root-partuuid"
}

clean_scratch() { rm -rf "${W:?}/fs" "${W:?}/boot" "${W:?}/boot.img" "${W:?}/root.img"; }

assemble() {  # assemble NAME [qemu]
    local name=$1 variant=${2:-} FS=${W:?}/fs
    # Work on a copy so the finished rootfs stays intact for FROM=fs reruns.
    clean_scratch
    mkdir -p "$FS" "$W/boot"
    cp -a "$ROOT" "$FS/@"
    [[ $variant == qemu ]] && add_qemu_kernel "$FS/@"
    cp -a "$FS/@/boot/." "$W/boot/"
    find "$FS/@/boot" -mindepth 1 -delete

    local subvol_args=() entry sub mount
    for entry in "${SUBVOLUMES[@]}"; do
        sub=${entry%%:*} mount=${entry#*:}
        if [[ $sub != @ ]]; then
            mkdir -p "$FS/@$mount" "$FS/$sub"
            cp -a "$FS/@$mount/." "$FS/$sub/"
            find "$FS/@$mount" -mindepth 1 -delete
            subvol_args+=(--subvol "$sub")
        fi
    done
    chmod 750 "$FS/@/.snapshots" "$FS/@snapshots"

    # --shrink sizes the filesystem to its (zstd-compressed) contents; the
    # allocated chunks keep ~1 GiB free for first boot until it grows to the card.
    truncate -s 1G "$W/root.img"
    mkfs.btrfs -q -f -L POND_ROOT -U "$ROOT_UUID" -O ^block-group-tree --compress zstd:1 \
        --rootdir "$FS" --subvol default:@ "${subvol_args[@]}" --shrink "$W/root.img"
    local root_bytes; root_bytes=$(stat -c %s "$W/root.img")
    local root_mib=$(( (root_bytes + 1048575) / 1048576 + SLACK_MIB ))

    truncate -s "${BOOT_MIB}M" "$W/boot.img"
    mkfs.fat -F 32 -n PONDBOOT -i "$BOOT_VOLID" "$W/boot.img" >/dev/null
    mcopy -s -i "$W/boot.img" "$W/boot/"* ::/

    local img=$W/$name.img
    rm -f "$img"
    truncate -s "$(( 1 + BOOT_MIB + root_mib + 1 ))M" "$img"
    sfdisk -q "$img" <<EOF
label: gpt
label-id: $DISK_UUID
unit: sectors
start=2048, size=$(( BOOT_MIB * 2048 )), type=$ESP_TYPE, uuid=$BOOT_PARTUUID, name="PONDBOOT"
start=$(( (1 + BOOT_MIB) * 2048 )), size=$(( root_mib * 2048 )), type=$ROOT_ARM64_TYPE, uuid=$ROOT_PARTUUID, name="POND_ROOT"
EOF
    dd if="$W/boot.img" of="$img" bs=1M seek=1 conv=notrunc,sparse status=none
    dd if="$W/root.img" of="$img" bs=1M seek=$(( 1 + BOOT_MIB )) conv=notrunc,sparse status=none
    clean_scratch

    if [[ $variant == qemu ]]; then
        # The macOS bind mount cannot hold sparse files; qcow2 stays compact.
        qemu-img convert -f raw -O qcow2 "$img" "$OUT/qemu/$name.qcow2"
        rm -f "$img"
        echo ">>> $OUT/qemu/$name.qcow2"
    else
        printf '%s %s\n' "$(stat -c %s "$img")" "$(sha256sum "$img" | cut -d' ' -f1)" > "$OUT/$name.img.extract"
        xz -T0 -6 -c "$img" > "$OUT/$name.img.xz"
        (cd "$OUT" && sha256sum "$name.img.xz" > "$name.img.xz.sha256")
        echo ">>> $OUT/$name.img.xz ($(du -h "$OUT/$name.img.xz" | cut -f1)); raw image kept at $img"
    fi
}

assemble "$NAME"
[[ ${QEMU_TEST:-0} == 1 ]] && assemble "$NAME-qemutest" qemu
echo '>>> done'
