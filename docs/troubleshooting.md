# Troubleshooting

Start by running `pond-pi-doctor` on the Pi, over SSH or in a terminal. It reports the
power supply, throttling, temperature, bootloader version, GPU drivers, storage, Wi-Fi and
Bluetooth, and warns about anything that looks wrong.

## The doctor reports under-voltage or a low supply current

The Pi 5 needs 5 V at 5 A, which in practice means the official 27 W supply. Most USB-C
laptop and phone chargers, Apple's included, provide at most 3 A at 5 V. The Pi runs on
them but limits its USB ports to 600 mA in total. Weaker chargers cause throttling, and a
Pi that keeps losing power can corrupt its SD card.

## The screen stays black after the boot screen

Make sure the monitor is on HDMI 0, the micro-HDMI port next to the USB-C power port. If
the login screen still doesn't appear, press Ctrl+Alt+F2, log in on the text console, and
run `pond-pi-doctor`.

If the doctor shows both GPU drivers but the desktop won't start, niri may have picked the
wrong one. Add this line to `~/.config/niri/cfg/debug.kdl`, and to the login screen's
config at `/usr/share/pond-interface/lockscreen/greeter/niri.kdl`:

```
debug { render-drm-device "/dev/dri/renderD128"; }
```

## The preset Wi-Fi didn't connect

Run `nmtui` on the Pi and join the network by hand. To find out why the preset failed, look
at `journalctl -b -u NetworkManager`. Preset networks connect with WPA2, so a router set to
WPA3 only won't accept them. Routers in mixed WPA2/WPA3 mode work.

## `pond.local` doesn't resolve

Some routers don't pass multicast traffic between their 2.4 GHz and 5 GHz networks, or
between Wi-Fi and Ethernet. Connect using the Pi's IP address instead. Run `ip -br a` on the
Pi to find it, or look in your router's list of connected devices.

## Updating the bootloader

Kernel 6.18 has been reported to hang at boot with some older Pi 5 bootloaders
([forum thread](https://archlinuxarm.org/forum/viewtopic.php?p=73885)). A Pi 5 with a
bootloader from May 2025 booted this image without problems. `pond-pi-doctor` shows the
date of yours.

To update it from Pond:

```sh
sudo rpi-eeprom-update            # shows the installed and latest versions
sudo rpi-eeprom-update -a
sudo reboot
```

The update is applied during the reboot. Pond never updates the bootloader on its own.

If the Pi won't boot far enough to run that, use Raspberry Pi Imager instead. Under Misc
utility images, choose Bootloader (Pi 5 family), then SD card boot. Write that to a spare
card and boot the Pi from it once. The screen turns green when it's done.

## Booting from NVMe

Write the image to the NVMe drive, either through a USB adapter or with `dd` from a Pi
that's already running. Then run `sudo rpi-eeprom-config --edit` and set
`BOOT_ORDER=0xf416` so the Pi tries NVMe first.

## A kernel update stopped the Pi from booting

Put the card in another Linux computer and mount the root partition with
`-o subvol=@` and the boot partition on its `/boot`. Then `arch-chroot` into it and
reinstall the previous kernel from the package cache:

```sh
pacman -U /var/cache/pacman/pkg/linux-rpi-<previous version>.pkg.tar.xz
```

Your `config.txt` and `cmdline.txt` aren't overwritten by kernel updates.

## Debugging without a screen

Add `console=ttyAMA10,115200` to `cmdline.txt` on the boot partition, and connect a serial
adapter such as the Raspberry Pi Debug Probe to the 3-pin UART header between the HDMI
ports. Kernel and systemd messages will show up on it from early boot.
