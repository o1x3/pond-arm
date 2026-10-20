# Troubleshooting

Start with `pond-pi-doctor` on the Pi. It reports the board, bootloader age, power supply
and USB current limit, under-voltage and throttling, temperature, GPU drivers, root device,
Wi-Fi country and Bluetooth state.

- **Under-voltage warnings.** The Pi 5 wants 5 V at 5 A (the official 27 W supply). Laptop
  and phone USB-C chargers, including Apple's, offer at most 5 V 3 A, which runs the Pi but
  caps USB at 600 mA in total; weaker supplies (the doctor shows e.g. "900 mA") cause
  throttling and risk SD-card corruption.
- **Black screen after the firmware screen.** Plug the monitor into HDMI 0, the port next to
  the USB-C power. If the login screen still doesn't appear, press Ctrl+Alt+F2, log in on
  the text console and run `pond-pi-doctor`. If niri picks the wrong GPU, add this to
  `~/.config/niri/cfg/debug.kdl` (and to the greeter's config):
  `debug { render-drm-device "/dev/dri/renderD128"; }`
- **Preset Wi-Fi did not connect.** Run `nmtui` on the Pi to join the network, then check
  `journalctl -b -u NetworkManager` for the reason. Preset networks connect with WPA2, which
  WPA2/WPA3 mixed routers accept; a WPA3-only router needs setup after boot.
- **`pond.local` does not resolve.** Some routers drop multicast between Wi-Fi bands. Use
  the IP address from `ip -br a` on the Pi or your router's device list.
- **A kernel update broke boot.** Put the card in another Linux machine, mount the root
  (`-o subvol=@`) and boot (`/boot`) partitions, `arch-chroot` in, and reinstall the
  previous kernel: `pacman -U /var/cache/pacman/pkg/linux-rpi-<previous>.pkg.tar.xz`.
  `config.txt` and `cmdline.txt` survive updates (pacman backup files).
- **Debugging boot without a screen.** Add `console=ttyAMA10,115200` to `cmdline.txt` and
  connect a Raspberry Pi Debug Probe to the Pi 5's 3-pin UART header.

## Bootloader EEPROM

Kernel 6.18 has stalled at boot on some older Pi 5 bootloaders
([ALARM forum](https://archlinuxarm.org/forum/viewtopic.php?p=73885)); a Pi 5 with a
2025-05-08 bootloader booted this image fine. `pond-pi-doctor` reports yours. To update from
Pond (it is applied on the next reboot; never automatic):

```sh
sudo rpi-eeprom-update        # show installed vs available
sudo rpi-eeprom-update -a && sudo reboot
```

If the Pi will not boot far enough for that, use Raspberry Pi Imager: *Misc utility images →
Bootloader (Pi 5 family) → SD card boot*, written to a spare card and booted once (the
screen turns green when done).

## Booting from NVMe

Flash the image to the NVMe drive through a USB adapter (or `dd` from a running Pi). Then
set `BOOT_ORDER=0xf416` with `sudo rpi-eeprom-config --edit`.
