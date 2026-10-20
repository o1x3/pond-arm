#!/usr/bin/env bash
# Raspberry Pi 5 compatibility matrix, checked statically against a built rootfs.
# Each feature needs its kernel driver (module or built-in), firmware, userspace
# and service. REQUIRED misses fail the build; OPTIONAL misses are reported.
# Usage: check-rootfs.sh ROOT [BOOTDIR]
set -uo pipefail

ROOT=${1:?usage: check-rootfs.sh ROOT [BOOTDIR]}
BOOT=${2:-$ROOT/boot}
kver=$(ls "$ROOT/usr/lib/modules" | grep -- '-rpi' | head -1)
MODS=$ROOT/usr/lib/modules/$kver
failures=0 warnings=0

has_mod() {  # any of the given modules, built-in or loadable
    local m
    for m in "$@"; do
        m=${m//-/_}
        grep -qE "/${m}\.ko$" <(sed 's/-/_/g' "$MODS/modules.builtin") && return 0
        [[ -n $(find "$MODS/kernel" -name "${m}.ko*" -o -name "${m//_/-}.ko*" 2>/dev/null | head -1) ]] && return 0
    done
    return 1
}
has_file() { local f; for f in "$@"; do compgen -G "$ROOT$f" >/dev/null && return 0; done; return 1; }
has_boot() { compgen -G "$BOOT/$1" >/dev/null; }
enabled() { [[ -L $ROOT/etc/systemd/system/$1 ]] || compgen -G "$ROOT/etc/systemd/system/*.wants/$1" >/dev/null || compgen -G "$ROOT/etc/systemd/user/*.wants/$1" >/dev/null; }

row() {  # level feature check-description command...
    local level=$1 feature=$2 what=$3; shift 3
    if "$@"; then
        printf '  ok    %-22s %s\n' "$feature" "$what"
    elif [[ $level == required ]]; then
        printf '  FAIL  %-22s %s\n' "$feature" "$what"; ((failures++))
    else
        printf '  warn  %-22s %s\n' "$feature" "$what"; ((warnings++))
    fi
}

echo "Pi 5 compatibility matrix (kernel $kver)"
# Boot chain
row required "boot firmware"      "start4.elf + fixup4.dat (Pi 4/5 firmware)"       has_boot start4.elf
row required "kernel"             "kernel8.img (4k pages; Pi 5 falls back to it)"   has_boot kernel8.img
row required "device tree"        "Pi 5 B, Pi 5 D0, Pi 500, CM5 DTBs"               bash -c "ls '$BOOT'/bcm2712-rpi-5-b.dtb '$BOOT'/bcm2712d0-rpi-5-b.dtb '$BOOT'/bcm2712-rpi-500.dtb '$BOOT'/bcm2712-rpi-cm5-cm5io.dtb >/dev/null"
row required "initramfs"          "initramfs-linux.img"                             has_boot initramfs-linux.img
row required "display overlay"    "vc4-kms-v3d-pi5 overlay"                         has_boot overlays/vc4-kms-v3d-pi5.dtbo
row required "root filesystem"    "btrfs"                                           has_mod btrfs
# Storage and buses
row required "SD card"            "sdhci-brcmstb"                                   has_mod sdhci_brcmstb
nvme_ok() { has_mod pcie_brcmstb && has_mod nvme; }
row required "NVMe (PCIe/HAT)"    "pcie-brcmstb + nvme"                             nvme_ok
row required "USB 3"              "xhci (RP1)"                                      has_mod xhci_plat_hcd xhci_hcd
row required "RP1 southbridge"    "rp1 MFD/PCI driver"                              has_mod rp1 rp1_pci
# Networking
row required "Ethernet"           "macb (Cadence GEM on RP1)"                       has_mod macb
row required "Wi-Fi driver"       "brcmfmac"                                        has_mod brcmfmac
row required "Wi-Fi firmware"     "CYW43455 for Pi 5 / Pi 500 / CM5"                has_file "/usr/lib/firmware/updates/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.bin"
row required "Wi-Fi regdb"        "wireless-regdb"                                  has_file /usr/lib/firmware/regulatory.db
row required "Bluetooth driver"   "hci_uart + btbcm"                                has_mod hci_uart
row required "Bluetooth firmware" "BCM4345C0 patch"                                 has_file "/usr/lib/firmware/updates/brcm/BCM4345C0.hcd"
row required "Bluetooth service"  "bluetooth.service enabled"                       enabled bluetooth.service
row required "NetworkManager"     "enabled"                                         enabled NetworkManager.service
# Graphics
row required "display driver"     "vc4 (HDMI x2, DSI)"                              has_mod vc4
row required "3D driver"          "v3d"                                             has_mod v3d
row required "OpenGL ES (mesa)"   "v3d gallium driver"                              has_file /usr/lib/dri/v3d_dri.so /usr/lib/libgallium*.so
row required "Vulkan (v3dv)"      "broadcom ICD"                                    has_file "/usr/share/vulkan/icd.d/broadcom_icd*.json"
row required "compositor"         "niri + Quickshell + SDDM"                        has_file /usr/bin/niri /usr/bin/quickshell /usr/bin/sddm
row required "display manager"    "sddm enabled"                                    enabled display-manager.service
# Audio and media
row required "HDMI audio"         "vc4 HDMI audio + PipeWire"                       has_file /usr/bin/pipewire /usr/bin/wireplumber
row optional "HEVC decoder"       "rpi-hevc-dec (stateless V4L2)"                   has_mod rpi_hevc_dec hevc_rpi
camera_ok() { has_mod rp1_cfe && has_mod pisp_be && has_file "/usr/lib/libcamera.so*"; }
row optional "camera (CSI)"       "rp1-cfe + pisp-be + libcamera"                   camera_ok
# Board management
row required "RTC"                "rtc-rpi"                                         has_mod rtc_rpi
row required "fan"                "pwm-fan + RP1 PWM"                               has_mod pwm_fan
row required "thermal"            "brcmstb/bcm2835 thermal"                         has_mod brcmstb_thermal bcm2835_thermal
row required "watchdog"           "bcm2835-wdt"                                     has_mod bcm2835_wdt
row required "power button"       "gpio-keys / pwrkey -> logind"                    has_mod gpio_keys
row required "vcgencmd/pinctrl"   "raspberrypi-utils"                               has_file /usr/bin/vcgencmd /usr/bin/pinctrl
row required "pond-pi-doctor"     "on-device health report"                         test -x "$ROOT/usr/bin/pond-pi-doctor"
# Updates
row required "pacman keyring"     "archlinuxarm-keyring (ALARM package signatures)" has_file /usr/share/pacman/keyrings/archlinuxarm.gpg
# Local network
mdns_ok() { enabled avahi-daemon.service && has_file /usr/lib/libnss_mdns_minimal.so.2 && grep -q '^hosts:.*mdns_minimal' "$ROOT/etc/nsswitch.conf" && grep -q '^MulticastDNS=no' "$ROOT/etc/systemd/resolved.conf.d/50-pond-pi.conf"; }
row required "hostname.local"     "avahi publishes it; nss-mdns; resolved mDNS off"   mdns_ok
# Memory
zram_ok() { has_mod zram && has_file /usr/lib/systemd/system-generators/zram-generator; }
row required "zram swap"          "zram + zram-generator"                           zram_ok
firewall_ok() { has_mod nf_tables && has_mod nft_compat && has_mod xt_conntrack && enabled ufw.service; }
row required "firewall"           "ufw on nf_tables (nft_compat, conntrack)"        firewall_ok
containers_ok() { has_mod overlay && has_mod fuse; }
row required "containers"         "overlayfs + fuse (Flatpak, Nix)"                 containers_ok
# First boot
row required "first boot"         "grow + seed + setup units enabled"               bash -c "ls '$ROOT'/etc/systemd/system/*.wants/pond-firstboot-system.service '$ROOT'/etc/systemd/system/*.wants/pond-firstboot.service '$ROOT'/etc/systemd/system/*.wants/pond-setup.service >/dev/null"
row required "SSH (on demand)"    "openssh present, not enabled by default"        bash -c "test -x '$ROOT/usr/bin/sshd' && ! ls '$ROOT'/etc/systemd/system/*.wants/sshd.service >/dev/null 2>&1"
row required "root locked"        "no root password"                                bash -c "grep -qE '^root:!' '$ROOT/etc/shadow'"
row required "no baked secrets"   "no host keys, keyring or machine-id"             bash -c "! ls '$ROOT'/etc/ssh/ssh_host_* >/dev/null 2>&1 && ! test -d '$ROOT/etc/pacman.d/gnupg' && ! test -s '$ROOT/etc/machine-id'"

echo "  -- $failures required failure(s), $warnings warning(s)"
exit $(( failures > 0 ))
