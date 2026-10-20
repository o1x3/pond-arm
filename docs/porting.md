# Porting to other ARM hardware

Most of pond-arm has nothing to do with the Raspberry Pi. Pond's packages are compiled for
aarch64, not for a particular board, and the configuration, first-boot setup and btrfs
layout would be the same on any machine. What changes from board to board is the kernel, the
firmware, and how the machine finds and starts the system.

## What a board needs

* A 64-bit ARM CPU. Pond's packages are built for aarch64 only.
* A GPU with an open source driver in Mesa, and a kernel driver for its display. niri won't
  start on software rendering, which was confirmed while testing in QEMU, so a board whose
  GPU only works with vendor libraries can't run the desktop.
* A way to boot the image. PCs, servers and virtual machines use UEFI, most single-board
  computers use U-Boot, and the Raspberry Pi uses its own firmware.
* Enough memory. The desktop uses about 750 MB after login on the Pi 5, so 4 GB is a
  sensible minimum for daily use.

## What's already covered

Arch Linux ARM's generic kernel (`linux-aarch64`, version 7.2) and its Mesa package (26.2)
already include drivers for most current ARM GPUs:

| GPU | Found in | Kernel driver | Mesa drivers |
|---|---|---|---|
| Arm Mali (Valhall, such as the G610) | Rockchip RK3588 | `panthor` | `panfrost` (OpenGL), `panvk` (Vulkan) |
| Arm Mali (Midgard, Bifrost) | older Rockchip, Amlogic, Allwinner, MediaTek | `panfrost` | `panfrost`, `panvk` |
| Qualcomm Adreno | Snapdragon | `msm` | `freedreno` (OpenGL), `turnip` (Vulkan) |
| Apple GPU | M-series Macs | Asahi kernel | `asahi`, `honeykrisp` (Vulkan) |
| Broadcom VideoCore | Raspberry Pi 4 and 5 | `v3d`, `vc4` | `v3d`, `v3dv` (Vulkan) |
| Virtual GPU | QEMU, UTM | `virtio-gpu` | `virgl` |

The generic kernel also ships device trees for Rockchip (59 for the RK3588 alone), Apple,
Qualcomm, Allwinner, Amlogic, MediaTek and NVIDIA boards. For many machines, then, the
driver work is already done upstream, and the remaining work is in booting.

## Shared and board-specific parts

These parts of the repository work on any aarch64 board as they are:

* building Pond's packages (`build/build-packages.sh`)
* the package set in `build/packages.txt`, apart from the Pi lines
* `overlay/`, apart from `pond-pi-doctor`
* first boot: growing the root partition, the keyring, presets, the setup screen
* building the btrfs filesystem and its subvolumes
* `tools/pondpi.py`, which writes the same cloud-init presets any board can read

These are specific to the Raspberry Pi 5 and would be replaced or added per board:

* the kernel, firmware and bootloader packages
* the contents of the boot partition (the Pi's firmware files, `config.txt`, `cmdline.txt`)
* the hardware rows in `build/check-rootfs.sh`
* `pond-pi-doctor`
* the flashing defaults, such as the Imager manifest

## Candidates

### Virtual machines on Apple Silicon

UTM, Parallels, VMware Fusion and plain QEMU all run aarch64 Linux on a Mac at close to full
speed. The QEMU test build already does most of this: it's the same root filesystem with
Arch Linux ARM's generic kernel, and the desktop rendered in QEMU with a virgl GPU.

What's missing is a normal UEFI disk image, with an EFI system partition and a bootloader in
place of the Pi's firmware files. If that bootloader were GRUB, Pond's snapshot boot menu
would come back, since that's how Pond does it on PCs. Whether the desktop runs in Parallels
and VMware depends on their virtual GPUs, which haven't been tried.

A generic UEFI image is also the starting point for ARM machines that boot like PCs, such
as Ampere workstations with a PCIe graphics card.

### Raspberry Pi 4 and Pi 400

They use the same kernel, firmware packages and GPU driver family as the Pi 5. The firmware
files they need (`start4.elf`) are already in the image. The work is mostly in `config.txt`,
the display overlay, and testing on the hardware. The GPU and CPU are slower than the Pi 5's,
and how the desktop feels on them hasn't been measured.

### RK3588 boards

The Orange Pi 5, Radxa Rock 5B and similar boards have eight CPU cores, up to 32 GB of RAM,
and a Mali-G610 GPU that Mesa supports through `panthor`.

They boot through U-Boot, which lives on the board's SPI flash or at the start of the
storage, and Arch Linux ARM doesn't package U-Boot for these boards. An image would have to
include a U-Boot build for each board, plus a boot configuration (usually `extlinux.conf`).
Mainline kernel support for the RK3588 has been arriving over several releases, so features
like HDMI audio and video decoding should be checked per board before promising them. The
U-Boot and testing work repeats for every board.

### Apple Silicon Macs

The Asahi Linux project wrote open source drivers for Apple's GPUs, and Arch Linux ARM's
Mesa already includes them. The hard part is installation. Asahi installs next to macOS
with its own installer and boot chain (m1n1 and U-Boot), uses its own kernel with 16 KB
memory pages, and handles Apple's firmware itself. So a Pond image can't simply be flashed.
The practical routes are to install Pond's packages on an existing Asahi system that's based
on Arch Linux ARM, or to package Pond as a root filesystem for Asahi's installer. Asahi
supports the M1 and M2 families. Check its support pages for later chips.

### Snapdragon X laptops

The Adreno GPU is covered by `msm` and Mesa. The laptops themselves are the problem. Each one
needs its own device tree, firmware has to be copied from the Windows install, and support
for things like audio, cameras and suspend varies by model. Arch Linux ARM doesn't target
these laptops. They're worth revisiting once kernel support settles.

### Hardware that doesn't fit

Boards whose GPU only works with vendor libraries can't run the desktop. NVIDIA's Jetson
boards use NVIDIA's own kernel and graphics stack, which Mesa doesn't cover. Boards with
older Mali GPUs (`lima`, early `panfrost`) would work, but their GPUs are probably too slow
for Pond's shell.

## Suggested order

1. Publish Pond's aarch64 packages as a signed pacman repository. Every board benefits:
   Pond updates would arrive with `pacman -Syu` instead of an image rebuild, and each board
   image would install from the repository. GitHub Actions has arm64 Linux runners that
   could build the packages. Each package's licence needs checking before it's published.
   The Pond Gramercy fonts have no licence, so they would stay out of the repository until
   Butterfly says otherwise.
2. A generic UEFI image, for virtual machines first.
3. Raspberry Pi 4 and Pi 400.
4. One RK3588 board, probably the Orange Pi 5, as the pattern for the others.
5. Apple Silicon through Asahi.
6. Snapdragon X laptops, once support is steadier.

## How the code would change

For now the Pi-specific parts sit inside the shared scripts. When a second board is added,
they should move into a directory per board, such as `boards/rpi5/`, holding that board's
package list, its overlay, a script that lays out the boot partition and installs the
bootloader, its hardware checks, and its doctor. `./pond-pi build` would become something
like `./pond-arm build --board rpi5`.

It's better to wait for the second board before doing this. Which parts really differ
between boards is much easier to see with two of them side by side.
