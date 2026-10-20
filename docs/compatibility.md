# Compatibility

## Hardware matrix (Raspberry Pi 5)

`build/check-rootfs.sh` runs on every build and fails it if any *required* row is missing
(the result is `out/pond-pi5-<date>.compat.txt`). The verified column says how far each row
has been confirmed:

- **build**: driver, firmware or files present in the image
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
| Monitor brightness | DDC/CI over HDMI | `ddcutil`, users in `i2c` | Pi 5 |
| Wi-Fi | CYW43455 802.11ac | `brcmfmac` + `firmware-raspberrypi` | Pi 5 (WPA2/WPA3 router, preset + manual) |
| Bluetooth | CYW43455 BT 5.0 | `hci_uart`/`btbcm` + BCM4345C0 | Pi 5 (scan) |
| Ethernet | Gigabit (RP1 / Cadence GEM) | `macb` | Pi 5 (`end0` up; no cable tested) |
| USB | 2× USB 3, 2× USB 2 (RP1 xHCI) | `xhci` | Pi 5 (keyboard, 2.4 GHz mouse receiver) |
| Storage | microSD (SDR104), NVMe via PCIe HAT | `sdhci-brcmstb`, `nvme`, `pcie-brcmstb` | Pi 5 (microSD, 85 MB/s) · NVMe hardware |
| Audio | HDMI audio; USB/Bluetooth audio | vc4 HDMI, PipeWire, WirePlumber | Pi 5 (HDMI playback) |
| Video decode | HEVC (hardware block); everything on CPU in practice | `rpi-hevc-dec` (V4L2 stateless) | Pi 5 (device present)* |
| Camera | CSI cameras (Camera Module 3, HQ…) | `rp1-cfe`, `pisp-be`, libcamera + PipeWire | Pi 5 (PiSP present) · camera hardware |
| Board | RTC, fan, thermal, watchdog, power button | `rtc-rpi`, `pwm-fan`, `bcm2835-wdt`, `gpio-keys` | Pi 5 |
| Tools | `vcgencmd`, `pinctrl`, `rpi-eeprom-update` | `raspberrypi-utils`, `rpi5-eeprom` | Pi 5 (EEPROM updated 2025-05 → 2026-09) |
| Memory | zram swap (zstd, size of RAM) | Pond's `pond-system-optimizations` | Pi 5 |
| Local network | `<hostname>.local` published; other `.local` names resolve | avahi, nss-mdns, ufw IGMP + mDNS | Pi 5 (`ssh you@pond.local` from macOS) |
| Firewall | ufw default-deny; SSH opened only when requested | `ufw` on nf_tables | Pi 5 |
| Updates | `pacman -Syu` against Arch Linux ARM; snapper pre/post snapshots | `archlinuxarm-keyring`, `snap-pac` | Pi 5 |
| Apps | Flathub (aarch64), AUR via paru, Nix | `flatpak`, `paru`, `nix` | Pi 5 (Flatseal, brave-bin, `nix run nixpkgs#hello`) |
| Diagnostics | power/USB limit, throttling, bootloader age, GPU, radios | `pond-pi-doctor` | Pi 5 |

\* Arch's ffmpeg and mpv do not use the Pi 5's stateless HEVC decoder, so video decodes on
the CPU. Measured on the Pi 5 with synthetic clips: 1080p H.264 277 fps, 1080p HEVC
159 fps, 4K H.264 72 fps, 4K HEVC 41 fps (30 fps is real time).

## Boards

| Board | Status |
|---|---|
| Pi 5 (all RAM sizes), Pi 500, CM5 | target; DTBs and Wi-Fi firmware included |
| Pi 5 1 GB | runs; the idle desktop uses ~750 MB, so expect zram swapping |
| Pi 4 / Pi 400 | the same kernel and firmware support them, but untested |
| Pi 3 and older | not supported (performance) |

**RAM:** the idle desktop after login uses about 750 MB in total. Pond's shell is about
200 MB of that and the launcher about 140 MB. With Firefox open, a 4 GB Pi 5 uses about
1.7 GB. zram adds compressed swap equal to RAM.

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
| power profiles in the shell | no effect | `power-profiles-daemon` has only its placeholder driver on the Pi |

## Which apps from Pond's catalogue install

Pond's launcher and `pm` offer 4,006 apps (3,165 Flathub, 807 pacman, 34 AUR). Checked
against Flathub's aarch64 list, Arch Linux ARM's repositories and each AUR package's
`arch=` (October 2026), **3,439 (86%) install on a Pi 5**. Popular ones that work: Firefox,
Google Chrome, Brave, VLC, Telegram, Prism Launcher, RetroArch, Claude Code.

The rest have no Linux ARM build, and the launcher only shows a red "!" when they fail:
Discord, Spotify, Steam, Bottles, Heroic, Sober, Minecraft, OBS Studio (Flathub), Obsidian,
Zed, 1Password, Bitwarden (desktop), Zoom, Microsoft Edge, Thunderbird (Flathub), Wine,
VirtualBox. Web versions (Discord, Spotify, Obsidian Sync, Zoom) work in Firefox or Chrome.
