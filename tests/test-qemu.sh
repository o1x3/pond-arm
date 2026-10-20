#!/usr/bin/env bash
# Boot the QEMU test image (QEMU_TEST=1 build) on an Apple Silicon or aarch64
# Linux host. The rootfs, first-boot units and Pond desktop are exactly the
# release image's; only the kernel differs (ALARM linux-aarch64 instead of
# linux-rpi, because QEMU cannot emulate a Pi 5).
#   test-qemu.sh seeded   customize with a user + SSH key, then SSH in and check
#   test-qemu.sh blank    no seed: the tty1 setup wizard should appear
# GPU=gl adds a virgl 3D GPU (Linux host with an X display, e.g. Xvfb + llvmpipe)
# so niri, the SDDM greeter and Pond's shell can render; the default 2D GPU only
# offers software EGL, which niri refuses.
set -euo pipefail

MODE=${1:-seeded}
HERE=$(cd "$(dirname "$0")/.." && pwd)
Q=$HERE/out/qemu
RUN=$Q/run-$MODE${GPU:+-$GPU}
image=$(ls -t "$Q"/pond-pi5-*-qemutest.qcow2 | head -1)
partuuid=$(cat "$Q/root-partuuid")

rm -rf "$RUN"; mkdir -p "$RUN"
qemu-img convert -f qcow2 -O raw "$image" "$RUN/disk.img"    # sparse on APFS/ext4
qemu-img resize -q -f raw "$RUN/disk.img" 32G     # first boot must grow root to fill this

if [[ $MODE == seeded ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "$RUN/key" -C pond-qemu-test
    "$HERE/pond-pi" customize "$RUN/disk.img" --hostname pond-qemu --user tester \
        --password-hash "$(printf 'pond-test-pw' | openssl passwd -6 -stdin)" \
        --ssh-key "$RUN/key.pub" --timezone Europe/London --locale en_GB.UTF-8 --keyboard gb
fi

if [[ $(uname) == Darwin ]]; then
    accel=(-accel hvf -cpu host)
elif [[ -e /dev/kvm ]]; then
    accel=(-accel kvm -cpu host)
else
    accel=(-accel tcg,thread=multi -cpu max,pauth-impdef=on)
fi
if [[ ${GPU:-} == gl ]]; then
    gpu=(-device virtio-gpu-gl-pci,xres=1920,yres=1080 -display sdl,gl=on)
else
    gpu=(-device virtio-gpu-pci,xres=1920,yres=1080 -display none)
fi
qemu-system-aarch64 -M virt "${accel[@]}" -smp "${SMP:-4}" -m 4096 \
    -kernel "$Q/Image" -initrd "$Q/initramfs.img" \
    -append "root=PARTUUID=$partuuid rootfstype=btrfs rootflags=subvol=@ rw rootwait console=ttyAMA0 console=tty1 quiet splash" \
    -drive if=virtio,format=raw,file="$RUN/disk.img" \
    "${gpu[@]}" -device qemu-xhci -device usb-kbd -device usb-tablet \
    -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${SSH_PORT:-2222}-:22 \
    -serial file:"$RUN/serial.log" \
    -qmp unix:"$RUN/qmp.sock",server,nowait -pidfile "$RUN/qemu.pid" -daemonize
echo "booting; serial log: $RUN/serial.log"
