# Development

## How the build works

`./pond-pi build` does all of its work inside an arm64 Docker container called
`pond-builder`, with its scratch files in a Docker volume called `pond-work`. On Apple
Silicon the container runs natively. The volume is needed because macOS file systems are
case-insensitive by default, and some packages contain files whose names differ only in
case.

The build goes through these steps:

1. Download the Arch Linux ARM base system, check its signature, and import it into Docker
   as `alarm:base`.
2. Clone [pond-pkgbuilds](https://github.com/amarsbar/pond-pkgbuilds) into `.src/`.
3. `build/setup-builder.sh` installs the build tools in the container. It's safe to run
   again, and it retries when an Arch Linux ARM mirror stalls.
4. `build/build-packages.sh` builds Pond's 16 packages for aarch64 with makepkg and puts
   them in a local package repository. Two fish plugins are architecture-independent, so
   they're downloaded from Pond's own repository instead, after checking their signatures
   against Pond's key. Packages that are already built are skipped.
5. `build/build-image.sh` installs everything in `build/packages.txt`, copies `overlay/` on
   top, configures the system, and runs `build/check-rootfs.sh`. It then removes anything
   that has to be unique per device, such as SSH host keys, and writes the image: a FAT boot
   partition and a btrfs partition holding Pond's subvolumes. No loop devices are needed,
   because `mkfs.btrfs --rootdir` builds the filesystem straight from a directory.
6. `tools/pondpi.py manifest` writes the Raspberry Pi Imager manifest.

Don't edit `build/build-image.sh` while a build is running. Bash reads a script as it runs
it, so the running build will pick up the edit partway through and usually fail.

## Build options

These are read from the environment.

* `VERSION` (default: today's date in UTC, such as `2026.10.21`)

  Appended to the image name.

* `QEMU_TEST` (default: `0`)

  Set to `1` to also build a copy of the image for QEMU in `out/qemu/`. It has the same root
  filesystem with Arch Linux ARM's generic kernel, since QEMU can't emulate a Pi 5.

* `POND_BUILDER`, `POND_VOLUME` (defaults: `pond-builder`, `pond-work`)

  The names of the build container and its volume.

* `POND_SRC` (default: `.src`)

  Where pond-pkgbuilds is cloned.

To rebuild only the image files from the last finished root filesystem, which takes a few
minutes instead of fifteen:

```sh
docker exec pond-builder env FROM=fs OUT=/p/out bash /p/build/build-image.sh
```

## Tests

`tests/selftest.sh` takes about a minute and needs Docker. It presets a fake boot partition
with `pond-pi customize`, applies it with the real first-boot script in an Arch Linux ARM
container, and checks the result. It also feeds the first-boot script hostile input to make
sure nothing in it gets executed, and validates the Imager manifest against Imager's
schema.

`tests/test-qemu.sh` boots the QEMU build. It needs `QEMU_TEST=1 ./pond-pi build` first.

```sh
tests/test-qemu.sh seeded    # preset user tester / pond-test-pw, SSH on 127.0.0.1:2222
tests/test-qemu.sh blank     # no preset, so the setup screen appears
```

It uses HVF on macOS and KVM on Linux. QEMU's default GPU only offers software rendering,
which niri won't start on. To see the desktop, run it on a Linux host with an X display and
`GPU=gl`, which gives the VM a virgl GPU. `tests/qmp.py` can take screenshots of the VM and
type into it.

## Adding another board

Pond's packages are built for aarch64 in general, so most of this repository would carry
over to another ARM board. These are the parts specific to the Raspberry Pi:

* the kernel, firmware and bootloader packages in `build/packages.txt` (`linux-rpi`,
  `firmware-raspberrypi`, `raspberrypi-bootloader`, `rpi5-eeprom`, `vulkan-broadcom`)
* the boot partition and `cmdline.txt` set up in `build/build-image.sh`
* the Pi rows in `build/check-rootfs.sh`
* `overlay/usr/bin/pond-pi-doctor`
