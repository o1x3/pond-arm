# Development

## How `./pond-pi build` works

Everything runs in an arm64 Docker container (`pond-builder`, scratch volume `pond-work`),
so the host only needs Docker. Apple Silicon runs it natively.

1. Download the Arch Linux ARM base tarball, verify its signature, import it as `alarm:base`.
2. Clone [pond-pkgbuilds](https://github.com/amarsbar/pond-pkgbuilds) into `.src/`.
3. `build/setup-builder.sh`: idempotent toolchain setup in the container (retries stalled
   ALARM mirrors).
4. `build/build-packages.sh`: build Pond's 16 own packages for aarch64 with makepkg into a
   local repo; fetch the two `any`-arch fish packages from Pond's x86_64 repo and verify
   them against Pond's signing key.
5. `build/build-image.sh`: pacstrap `build/packages.txt`, lay `overlay/` over it, configure
   (locale, users, presets, initramfs, Pi boot files), make it generic (no keys, no
   machine-id), run `build/check-rootfs.sh`, then assemble a GPT image: a FAT boot partition
   and a btrfs root with Pond's 11 subvolumes, built with `mkfs.btrfs --rootdir` (no loop
   devices needed).
6. `tools/pondpi.py manifest`: write the Raspberry Pi Imager manifest.

Options (environment variables):

| Variable | Effect |
|---|---|
| `VERSION=2026.10.21` | image name suffix (default: today, UTC) |
| `QEMU_TEST=1` | also write `out/qemu/`: the same rootfs with ALARM's generic kernel, for QEMU |
| `POND_BUILDER`, `POND_VOLUME` | container and volume names (default `pond-builder`, `pond-work`) |
| `POND_SRC` | where pond-pkgbuilds is cloned (default `.src/`) |

To reassemble images from the last finished rootfs without rebuilding it:
`docker exec pond-builder env FROM=fs OUT=/p/out bash /p/build/build-image.sh`.

Don't edit `build/build-image.sh` while a build is running: bash reads scripts as it runs
them, so the running build would pick up the edit mid-way.

## Tests

```sh
tests/selftest.sh                 # ~1 min: customize -> first boot round trip, hostile seeds, manifest schema
QEMU_TEST=1 ./pond-pi build       # build the QEMU variant
tests/test-qemu.sh seeded         # boot with a seeded user (tester / pond-test-pw), SSH on 127.0.0.1:2222
tests/test-qemu.sh blank          # boot without a seed: the tty1 setup screen appears
```

`test-qemu.sh` uses HVF on macOS and KVM on Linux. QEMU's 2D GPU only offers software EGL,
which niri refuses, so the desktop needs `GPU=gl` (virgl) on a Linux host with an X display
(for example Xvfb with llvmpipe). `tests/qmp.py` takes screenshots and types into the VM.

## What is Raspberry Pi specific

Pond's packages build for any aarch64 machine. The Pi-specific parts, which another board
would replace:

- kernel, firmware and bootloader packages in `build/packages.txt` (`linux-rpi`,
  `firmware-raspberrypi`, `raspberrypi-bootloader`, `rpi5-eeprom`, `vulkan-broadcom`)
- the FAT boot partition contents and `cmdline.txt` written by `build/build-image.sh`
- the Pi rows in `build/check-rootfs.sh`
- `overlay/usr/bin/pond-pi-doctor`
