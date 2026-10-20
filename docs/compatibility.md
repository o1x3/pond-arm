# Compatibility

## Raspberry Pi 5

Every build runs `build/check-rootfs.sh`, which checks that the drivers, firmware and
services for each part of the Pi 5 are in the image. The build fails if a required one is
missing, and the results are saved next to the image as `.compat.txt`.

Passing that check only means the files are present. The last column says how each item has
actually been tested. "Pi 5" means it was seen working on a Pi 5 Model B (4 GB, rev 1.0)
running this image. "Untested" means it still needs the hardware to confirm.

| Component | Provided by | Tested |
|---|---|---|
| Boot firmware, kernel 6.18, device trees for Pi 5, Pi 500 and CM5 | `raspberrypi-bootloader`, `linux-rpi` | Pi 5 |
| btrfs root with Pond's 11 subvolumes | `linux-rpi`, initramfs | Pi 5 |
| First boot (resize, keyring, presets) | `pond-firstboot`, `pond-setup` | Pi 5; setup screen in QEMU |
| HDMI output (2 × 4K60) and DSI displays | `vc4` | Pi 5, HDMI 0 at 2560×1440 |
| GPU with OpenGL ES 3.1 and Vulkan 1.3 | Mesa `v3d`, `vulkan-broadcom` | Pi 5 |
| Pond's desktop (niri, shell, login screen, launcher) | Pond packages rebuilt for aarch64 | Pi 5 |
| Monitor brightness over HDMI (DDC/CI) | `ddcutil` | Pi 5 |
| Wi-Fi (CYW43455, 802.11ac) | `brcmfmac`, `firmware-raspberrypi` | Pi 5, WPA2/WPA3 router |
| Bluetooth 5.0 | `hci_uart`, `btbcm` | Pi 5, scanning only |
| Gigabit Ethernet | `macb` | Pi 5, link not tested |
| USB 3 and USB 2 ports | `xhci` | Pi 5, keyboard and mouse |
| microSD | `sdhci-brcmstb` | Pi 5, 85 MB/s at SDR104 |
| NVMe through a PCIe HAT | `nvme`, `pcie-brcmstb` | untested |
| HDMI audio | `vc4`, PipeWire | Pi 5 |
| Hardware HEVC decoder | `rpi-hevc-dec` | present but unused, see below |
| CSI cameras | `rp1-cfe`, `pisp-be`, libcamera | untested |
| Real-time clock, fan, watchdog, power button | `rtc-rpi`, `pwm-fan`, `bcm2835-wdt`, `gpio-keys` | Pi 5 |
| Bootloader updates | `rpi5-eeprom` | Pi 5 |
| `.local` hostname | avahi, nss-mdns | Pi 5, from macOS |
| Firewall | ufw | Pi 5 |
| Updates and snapshots | pacman, snapper, `snap-pac` | Pi 5 |
| Flathub, AUR, Nix | flatpak, paru, nix | Pi 5 |
| Health report | `pond-pi-doctor` | Pi 5 |

Arch's ffmpeg and mpv don't support the Pi 5's HEVC decoder, so all video is decoded on the
CPU. That's fast enough for most files. Decoding 1080p H.264 runs at 277 frames per second,
1080p HEVC at 159, 4K H.264 at 72 and 4K HEVC at 41. These were measured on the Pi 5 with
ffmpeg's synthetic test pattern, which is easier to decode than real video, so 4K HEVC
films may stutter.

## Other boards

The image includes device trees and Wi-Fi firmware for the Pi 500 and the Compute Module 5,
but neither has been tried. The Pi 4 and Pi 400 use the same kernel and firmware packages,
so they will probably boot, but the image isn't built or tested for them. Older Pis are too
slow for the desktop.

On a 4 GB Pi 5, the desktop uses about 750 MB of RAM after login, and about 1.7 GB with
Firefox open. A 1 GB Pi 5 will run it, but expect it to swap. Swap is compressed in RAM
(zram) and is the same size as the RAM.

## Differences from Pond on a PC

* Pond on a PC uses the CachyOS kernel. The Pi uses the Raspberry Pi kernel, because that's
  where the Pi 5's hardware support is. CachyOS's scheduler profiles aren't available.
* There's no GRUB, so there's no menu for booting into an older snapshot. The Pi's firmware
  starts the kernel directly. Snapshots are still taken on every update.
* Pond's hardware detection (`chwd`) isn't installed, because the Pi's drivers are all
  included in the image.
* Firmware for PC graphics cards and Intel Wi-Fi is left out, which saves about 650 MB. To
  add it back, run `pacman -S linux-firmware-intel`.
* Butterfly doesn't publish ARM packages. Pond's own packages update when you rebuild the
  image with `./pond-pi build`, and everything else updates from Arch Linux ARM.
* The optional apps in Pond's own repository (Brave, Claude Desktop and others) are x86_64
  builds. Many of them have ARM versions on Flathub or in the AUR.
* Sleep in the power menu locks the screen and does nothing else. The Pi 5 can't suspend.
* The power profile switch in the shell has no effect, because the Pi has no power profile
  driver.

## Apps

Pond's launcher and its `pm` tool offer 4,006 apps: 3,165 from Flathub, 807 from Arch
repositories and 34 from the AUR. Each was checked against Flathub's aarch64 list, the
Arch Linux ARM repositories and the `arch` field of its AUR package in October 2026, and
3,439 of them (86%) can be installed on a Pi 5. Firefox, Chrome, Brave, VLC, Telegram,
Prism Launcher, RetroArch and Claude Code are among them.

The rest have no Linux ARM build. They include Discord, Spotify, Steam, Bottles, Heroic,
Sober, Minecraft, OBS Studio, Obsidian, Zed, 1Password, Bitwarden, Zoom, Microsoft Edge,
Thunderbird from Flathub, Wine and VirtualBox. When you try to install one, the launcher
shows a red mark and doesn't say why. Discord, Spotify and Zoom work in a browser.
