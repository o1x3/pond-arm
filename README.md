# Pond for Raspberry Pi 5

A flashable SD-card image of [Pond](https://butterfly.so/) (Butterfly's Arch-based
niri desktop) for the Raspberry Pi 5, plus the tooling to build it, preset it like
Raspberry Pi Imager does, and write it to a card.

Butterfly ships Pond for x86_64 PCs only, as an installer ISO. This project rebuilds
Pond's own packages for aarch64 from
[pond-pkgbuilds](https://github.com/amarsbar/pond-pkgbuilds) and reconstructs the rest of
Pond's root filesystem: its package set, configuration, services and btrfs layout. The
reconstruction comes from Pond's published rootfs (`pond-rootfs.tar.zst`, sha256
`1feff559…`) on top of Arch Linux ARM.

> **Status:** the release image is assembled from the same root filesystem that passed
> the QEMU boot tests below, and every hardware driver and firmware file is checked at
> build time. It has **not yet been booted on a physical Pi 5**. The items marked
> *hardware* in the matrix can only be confirmed there.

## Quick start

Requirements: macOS on Apple Silicon or aarch64 Linux, Docker (OrbStack works), about 20 GB free.

```sh
./pond-pi build                     # ~25 min the first time: packages, rootfs, image
```

The output in `out/`:

| File | What |
|---|---|
| `pond-pi5-<date>.img.xz` (+ `.sha256`) | the image to flash, about 2 GB (4.4 GB written) |
| `pond-pi5-<date>.compat.txt` | the compatibility check for this build |
| `pond-pi5.rpi-imager-manifest` | opens the image in Raspberry Pi Imager with customisation enabled |

### Flash it

**macOS, one step:** this writes, verifies and presets the card.

```sh
./pond-pi flash out/pond-pi5-*.img.xz -- \
    --hostname pond --user you --ssh-key ~/.ssh/id_ed25519.pub \
    --wifi-ssid "Home" --wifi-country GB --timezone Europe/London --keyboard gb
```

You are prompted for your password and the Wi-Fi password, so neither lands in your
shell history. `flash` only lists external disks, refuses internal ones, and asks you
to type the disk name again before it erases anything.

**Raspberry Pi Imager:** run `rpi-imager --repo out/pond-pi5.rpi-imager-manifest`, or
double-click the manifest. Pick *Raspberry Pi 5*, then *Pond*, and use
*Edit settings* as usual (hostname, user, SSH keys, Wi-Fi, locale). Imager writes the same
cloud-init files that `pond-pi customize` does.

**Any other tool** (dd, Etcher): flash the `.img.xz`. Then either preset it with
`./pond-pi customize disk4 --user you …` (macOS; the disk number from `diskutil list`), or
let the first boot ask. macOS mounts the card's boot partition (an EFI System partition,
which the Pi 5 boots from) only as root, so this asks for your Mac password.

### Customize options

```
./pond-pi customize TARGET [--hostname H] [--user U] [--password-hash HASH]
    [--ssh] [--ssh-key FILE]... [--ssh-password-auth]
    [--wifi-ssid SSID [--wifi-password P | --wifi-open] [--wifi-hidden] [--wifi-country CC]]
    [--timezone Area/City] [--locale ll_CC.UTF-8] [--keyboard xkb-layout]
```

`TARGET` is a raw `.img` or the mounted boot partition. The tool writes `user-data`,
`network-config` and `meta-data` to the FAT partition (cloud-init NoCloud). The password
is stored only as a SHA-512 crypt hash. The Wi-Fi password is stored as given: on a real Pi 5
against a WPA2/WPA3 router, a profile holding the derived WPA2 key failed to connect while
the same profile holding the passphrase connected. The NetworkManager copy is root-only. The Pi deletes all three files
after applying them on first boot.

## First boot

1. **The disk grows to fill the card.** The root partition and btrfs are resized and the
   backup GPT is moved to the end of the card.
2. **A fresh pacman keyring is generated.** The image ships without one, so no two Pis
   share keys. SSH host keys and the machine-id are also generated per device.
3. **Settings are applied** from the boot partition, if present: hostname, user (added
   to `wheel` for sudo), SSH keys, Wi-Fi, country, timezone, locale and keyboard. When SSH is
   requested, sshd is enabled and port 22 is opened in Pond's firewall (ufw denies inbound
   by default). With keys, SSH password login is disabled. Root login is always disabled.
   The Pi announces itself as `<hostname>.local` (avahi), so `ssh you@pond.local` works
   from macOS, Linux and Windows without looking up its IP address.
4. **No user was preset?** A setup screen on the TV asks for a username, password and
   computer name, and offers Wi-Fi setup through `nmtui`.
5. **The Pond login screen appears.**

## Compatibility matrix

`scripts/check-rootfs.sh` runs on every build and fails it if any *required* row is
missing. The verified-by column says how far each row has been confirmed:

- **build**: driver, firmware or files present in the image (`compat.txt`)
- **QEMU**: observed working in a booted VM running the same root filesystem
- **Pi 5**: observed working on a physical Pi 5 Model B (4 GB, rev 1.0) with this image
- **hardware**: not yet observed on a physical Pi 5

| Area | Pi 5 component | Provided by | Verified |
|---|---|---|---|
| Boot | VC7 firmware, `kernel8.img`, DTBs for Pi 5 rev C1 / D0, Pi 500, CM5 | `raspberrypi-bootloader`, `linux-rpi` 6.18 | Pi 5 (22 s to desktop login) |
| Root fs | btrfs, Pond's 11-subvolume layout, zstd | `linux-rpi` btrfs + initramfs | Pi 5 |
| First boot | grow root, keyring, settings seed, setup screen | `pond-firstboot*`, `pond-setup` | Pi 5 (seeded) · QEMU (both paths) |
| Display | 2× HDMI 4Kp60, DSI | `vc4` + `vc4-kms-v3d-pi5` overlay | Pi 5 (HDMI 0, 2560×1440@60) |
| 3D GPU | VideoCore VII: OpenGL ES 3.1 / GL 3.1, Vulkan 1.3 | mesa `v3d` / `vulkan-broadcom` | Pi 5 (V3D 7.1, V3DV Vulkan 1.3) |
| Desktop | niri, Pond shell (Quickshell), SDDM greeter, launcher | Pond packages rebuilt for aarch64 | Pi 5 |
| Wi-Fi | CYW43455 802.11ac | `brcmfmac` + `firmware-raspberrypi` | Pi 5 (WPA2/WPA3 router, preset + manual) |
| Bluetooth | CYW43455 BT 5.0 | `hci_uart`/`btbcm` + BCM4345C0 | Pi 5 (scan) |
| Ethernet | Gigabit (RP1 / Cadence GEM) | `macb` | Pi 5 (`end0` up; no cable tested) |
| USB | 2× USB 3, 2× USB 2 (RP1 xHCI) | `xhci` | Pi 5 (keyboard, 2.4 GHz mouse receiver) |
| Storage | microSD (SDR104), NVMe via PCIe HAT | `sdhci-brcmstb`, `nvme`, `pcie-brcmstb` | Pi 5 (microSD) · NVMe hardware |
| Audio | HDMI audio; USB/Bluetooth audio | vc4 HDMI, PipeWire, WirePlumber | Pi 5 (HDMI sink present) |
| Video decode | HEVC (hardware block); H.264 on CPU | `rpi-hevc-dec` (V4L2 stateless) | Pi 5 (device present)* |
| Camera | CSI cameras (Camera Module 3, HQ…) | `rp1-cfe`, `pisp-be`, libcamera + PipeWire | Pi 5 (PiSP present) · camera hardware |
| Board | RTC, fan, thermal, watchdog, power button | `rtc-rpi`, `pwm-fan`, `bcm2835-wdt`, `gpio-keys` | Pi 5 |
| Tools | `vcgencmd`, `pinctrl`, `rpi-eeprom-update` | `raspberrypi-utils`, `rpi5-eeprom` | Pi 5 (EEPROM updated 2025-05 → 2026-09) |
| Memory | zram swap (zstd, size of RAM) | Pond's `pond-system-optimizations` | Pi 5 |
| Local network | `<hostname>.local` published; other `.local` names resolve | avahi, nss-mdns, ufw IGMP + mDNS | Pi 5 (`ssh karthik@pond.local` from macOS) |
| Firewall | ufw default-deny; SSH opened only when requested | `ufw` on nf_tables | Pi 5 |
| Updates | `pacman -Syu` against Arch Linux ARM; snapper pre/post snapshots | `archlinuxarm-keyring`, `snap-pac` | Pi 5 |
| Diagnostics | power/USB limit, throttling, bootloader age, GPU, radios | `pond-pi-doctor` | Pi 5 |

\* The HEVC decoder needs player support for V4L2 requests. mpv and browsers fall back
to the CPU, which handles 1080p H.264 and VP9 comfortably.

**Boards:**

| Board | Status |
|---|---|
| Pi 5 (all RAM sizes), Pi 500, CM5 | target; DTBs and Wi-Fi firmware included |
| Pi 5 1 GB | runs; the idle desktop uses ~750 MB, so expect zram swapping |
| Pi 4 / Pi 400 | the same kernel and firmware support them, but untested |
| Pi 3 and older | not supported (performance) |

**RAM:** the idle desktop after login uses 753 MB in total, measured in QEMU. Pond's
shell is about 207 MB of that and the launcher about 144 MB. zram adds compressed swap
equal to RAM.

## Differences from Pond on a PC

| Pond on PC | Pond on Pi 5 | Why |
|---|---|---|
| `linux-pond` (CachyOS) kernel | `linux-rpi` (Raspberry Pi kernel) | Pi 5 hardware support is in the Pi kernel |
| GRUB with a btrfs snapshot boot menu | Pi firmware boots the kernel directly | no GRUB/UEFI on the Pi. Snapper snapshots still happen on every pacman transaction, but you roll back from a running system, not the boot menu |
| `chwd` hardware detection | none | the Pi's drivers are fixed and all included |
| full `linux-firmware` | Broadcom, Realtek, MediaTek, Atheros, TI and misc only | −650 MB of PC GPU and Intel Wi-Fi firmware. `pacman -S linux-firmware-intel` restores it |
| `pond` repo updates | Arch Linux ARM updates; Pond's own packages update by rebuilding | Butterfly publishes no aarch64 repo. Run `./pond-pi build` again for new Pond releases |
| optional apps in Pond's repo (Brave, Claude Desktop, Nvidia…) | not from Pond's repo | x86_64-only binaries. Many have ARM builds via Flatpak or the AUR; see below |
| CachyOS scx scheduler profiles | stock kernel scheduler | sched_ext is not enabled in `linux-rpi` |
| Sleep (suspend) in the power menu | locks the screen only | the Pi 5 has no suspend-to-RAM; logind reports `CanSuspend=na` |

### Which apps from Pond's catalogue install

Pond's launcher and `pm` offer 4,006 apps (3,165 Flathub, 807 pacman, 34 AUR). Checked
against Flathub's aarch64 list, Arch Linux ARM's repositories and each AUR package's
`arch=` (October 2026), **3,439 (86%) install on a Pi 5**. Popular ones that work: Firefox,
Google Chrome, Brave, VLC, Telegram, Prism Launcher, RetroArch, Claude Code.

The rest have no Linux ARM build, and the launcher only shows a red "!" when they fail:
Discord, Spotify, Steam, Bottles, Heroic, Sober, Minecraft, OBS Studio (Flathub), Obsidian,
Zed, 1Password, Bitwarden (desktop), Zoom, Microsoft Edge, Thunderbird (Flathub), Wine,
VirtualBox. Web versions (Discord, Spotify, Obsidian Sync, Zoom) work in Firefox or Chrome.

## Bootloader EEPROM

Kernel 6.18 has stalled at boot on some older Pi 5 bootloaders
([ALARM forum](https://archlinuxarm.org/forum/viewtopic.php?p=73885)); a Pi 5 with a
2025-05-08 bootloader booted this image fine. `pond-pi-doctor` reports yours. To update
from Pond (it is applied on the next reboot; never automatic):

```sh
sudo rpi-eeprom-update        # show installed vs available
sudo rpi-eeprom-update -a && sudo reboot
```

If the Pi will not boot far enough for that, use Raspberry Pi Imager: *Misc utility
images → Bootloader (Pi 5 family) → SD card boot*, written to a spare card and booted
once (the screen turns green when done).

**Booting from NVMe:** flash the image to the NVMe drive through a USB adapter (or
`dd` from a running Pi). Then set `BOOT_ORDER=0xf416` with `rpi-eeprom-config`, from
Raspberry Pi OS or the bootloader utility image.

## Troubleshooting

Start with `pond-pi-doctor` on the Pi. It reports the board, bootloader age, power
supply and USB current limit, under-voltage and throttling, temperature, GPU drivers,
root device, Wi-Fi country and Bluetooth state.

- **Under-voltage warnings.** The Pi 5 wants 5 V at 5 A (the official 27 W supply).
  Laptop and phone USB-C chargers, including Apple's, offer at most 5 V 3 A, which runs the
  Pi but caps USB at 600 mA in total; weaker supplies (the doctor shows e.g. "900 mA")
  cause throttling and risk SD-card corruption.
- **Black screen after the firmware screen.** Plug the monitor into HDMI 0, the port
  next to the USB-C power. If the login screen still doesn't appear, press
  Ctrl+Alt+F2, log in on the text console and run `pond-pi-doctor`. If niri picks the wrong GPU, add this to
  `~/.config/niri/cfg/debug.kdl` (and to the greeter's config):
  `debug { render-drm-device "/dev/dri/renderD128"; }`
- **A kernel update broke boot.** Put the card in another Linux machine, mount the root
  (`-o subvol=@`) and boot (`/boot`) partitions, `arch-chroot` in, and reinstall the
  previous kernel: `pacman -U /var/cache/pacman/pkg/linux-rpi-<previous>.pkg.tar.xz`.
  `config.txt` and `cmdline.txt` survive updates (pacman backup files).
- **Debugging boot without a screen.** Add `console=ttyAMA10,115200` to `cmdline.txt`
  and connect a Raspberry Pi Debug Probe to the Pi 5's 3-pin UART header.

## Repository layout

```
pond-pi                      CLI: build, flash (macOS), customize, manifest
packages.txt                 Pond's explicit package set, ported to the Pi
overlay/                     Pond's rootfs configuration + Pi first-boot services
  usr/lib/pond-pi/firstboot.py         applies cloud-init seeds (no code execution)
  usr/lib/pond-pi/firstboot-system.sh  grows root, creates pacman keyring
  usr/lib/pond-pi/setup.sh             tty1 account setup when no seed was given
  usr/bin/pond-pi-doctor               on-device health report
scripts/build-packages.sh    builds Pond's packages for aarch64 (makepkg)
scripts/build-image.sh       pacstrap → configure → check → btrfs/FAT → GPT image
scripts/check-rootfs.sh      compatibility matrix (fails the build on misses)
scripts/pondpi.py            customize + Imager manifest
scripts/test-qemu.sh         boots the test image (seeded or blank; GPU=gl for the desktop)
scripts/selftest.sh          fast checks: customize/first-boot round trip, hostile seeds, manifest schema
```

## Licences

Pond's packages and configuration are © Butterfly / their authors under their own
licences: BSD-3-Clause for pond-interface and the installer, OFL for the bundled fonts.
The Pond Gramercy fonts are copied from Pond's published rootfs, where they ship
without a package licence file. Check with Butterfly before redistributing the image.
