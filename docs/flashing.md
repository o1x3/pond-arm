# Flashing and first boot

## Flash with `pond-pi flash` (macOS)

```sh
./pond-pi flash out/pond-pi5-*.img.xz -- \
    --hostname pond --user you --ssh-key ~/.ssh/id_ed25519.pub \
    --wifi-ssid "Home" --wifi-country GB --timezone Europe/London --keyboard gb
```

This writes the card, reads it back to check it against the build's checksum, then presets
it. You are prompted for your password and the Wi-Fi password, so neither lands in your
shell history. `flash` only lists external and removable disks, refuses internal ones, and
asks you to type the disk name again before it erases anything.

macOS mounts the card's boot partition (an EFI System partition, which the Pi 5 boots from)
only as root when it is on a physical card reader, so `flash` asks for your Mac password.

## Raspberry Pi Imager

Run `rpi-imager --repo out/pond-pi5.rpi-imager-manifest`, or double-click the manifest. Pick
*Raspberry Pi 5*, then *Pond*, and use *Edit settings* as usual (hostname, user, SSH keys,
Wi-Fi, locale). Imager writes the same cloud-init files that `pond-pi customize` does.

## Any other tool

Flash the `.img.xz` with dd, Etcher or similar. Then either preset it with
`./pond-pi customize disk4 --user you …` (macOS; the disk number from `diskutil list`), or
let the first boot ask.

## Customize options

```
./pond-pi customize TARGET [--hostname H] [--user U] [--password-hash HASH]
    [--ssh] [--ssh-key FILE]... [--ssh-password-auth]
    [--wifi-ssid SSID [--wifi-password P | --wifi-open] [--wifi-hidden] [--wifi-country CC]]
    [--timezone Area/City] [--locale ll_CC.UTF-8] [--keyboard xkb-layout]
```

`TARGET` is a raw `.img`, a mounted boot partition, or (macOS) a flashed card as `diskN`.
The tool writes `user-data`, `network-config` and `meta-data` to the FAT partition
(cloud-init NoCloud, the format Raspberry Pi Imager uses).

- The account password is stored only as a SHA-512 crypt hash.
- The Wi-Fi password is stored as given. On a real Pi 5 against a WPA2/WPA3 router, a
  profile holding the derived WPA2 key failed to connect while the same profile holding the
  passphrase connected. The NetworkManager copy on the Pi is readable by root only.
- The Pi deletes all three files after applying them on first boot.
- The seed is data only: `runcmd`, `bootcmd` and `write_files` are ignored, and every value
  is validated before it is applied.

## First boot

1. **The disk grows to fill the card.** The root partition and btrfs are resized and the
   backup GPT is moved to the end of the card.
2. **A fresh pacman keyring is generated.** The image ships without one, so no two Pis share
   keys. SSH host keys and the machine-id are also generated per device.
3. **Settings are applied** from the boot partition, if present: hostname, user (added to
   `wheel` for sudo and `i2c` for monitor brightness), SSH keys, Wi-Fi, country, timezone,
   locale and keyboard. When SSH is requested, sshd is enabled and port 22 is opened in
   Pond's firewall (ufw denies inbound by default). With keys, SSH password login is
   disabled. Root login is always disabled.
4. **No user was preset?** A setup screen on the TV asks for a username, password and
   computer name, and offers Wi-Fi setup through `nmtui`.
5. **The Pond login screen appears.**

The Pi announces itself as `<hostname>.local` (avahi), so `ssh you@pond.local` works from
macOS, Linux and Windows without looking up its IP address.
