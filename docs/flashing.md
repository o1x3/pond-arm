# Flashing and first boot

There are three ways to get the image onto a card. All of them can preset the card with
your account, SSH key and Wi-Fi, so the Pi is usable without a keyboard or screen.

## Using `pond-pi flash` (macOS)

```sh
./pond-pi flash out/pond-pi5-*.img.xz -- \
    --hostname pond --user you --ssh-key ~/.ssh/id_ed25519.pub \
    --wifi-ssid "Home" --wifi-country GB --timezone Europe/London --keyboard gb
```

`flash` lists the external and removable disks it found and refuses anything else. Before
it erases a card, it asks you to type the disk name again. After writing, it reads the card
back and compares it against the checksum from the build.

Everything after `--` is passed to `pond-pi customize`, described below. You'll be asked for
your Mac password, because macOS only lets root mount the card's boot partition.

## Using Raspberry Pi Imager

```sh
rpi-imager --repo out/pond-pi5.rpi-imager-manifest
```

Choose Raspberry Pi 5, then Pond, and fill in Imager's settings as you would for Raspberry
Pi OS. Imager writes the same files that `pond-pi customize` does, and the Pi applies them
the same way.

## Using another tool

Write the `.img.xz` with dd, balenaEtcher or anything else that handles compressed images.
To preset the card afterwards on macOS, run `./pond-pi customize diskN` with the disk
number from `diskutil list`. If you skip this, the Pi asks for an account on its first
boot.

## Preset options

`pond-pi customize TARGET [options]` writes the settings to the card's boot partition.
`TARGET` can be a disk on macOS (`disk4`), a mounted boot partition, or an uncompressed
`.img` file. Give at least one of the options below.

* `--hostname NAME` (default: `pond`)

  The computer's name. The Pi announces itself on the local network as `NAME.local`.

* `--user NAME` and `--password-hash HASH`

  Creates an account with sudo rights. You're prompted for the password unless you pass a
  crypt hash, such as one from `openssl passwd -6`. Only the hash is written to the card.

* `--ssh`, `--ssh-key FILE`, `--ssh-password-auth`

  `--ssh` turns on the SSH server and opens port 22 in the firewall. `--ssh-key` implies
  `--ssh` and can be repeated. With a key, password logins over SSH are disabled unless you
  also pass `--ssh-password-auth`. Root can never log in over SSH.

* `--wifi-ssid NAME`, `--wifi-password PASS`, `--wifi-open`, `--wifi-hidden`

  The Wi-Fi network to join. You're prompted for the password if you leave it out, which
  keeps it out of your shell history. Use `--wifi-open` for networks without a password.

* `--wifi-country CODE`

  The two-letter country code, for example `GB`, `US` or `IN`. The Pi only uses the
  channels allowed in its country, and without a country it may not find some 5 GHz
  networks.

* `--timezone ZONE`, `--locale LOCALE`, `--keyboard LAYOUT` (defaults: `UTC`,
  `en_US.UTF-8`, `us`)

  For example `Europe/London`, `en_GB.UTF-8` and `gb`.

The settings are written as cloud-init files (`user-data`, `network-config` and
`meta-data`), the same format Raspberry Pi Imager uses. The Pi reads them as data only.
Commands in them (`runcmd`, `bootcmd`, `write_files`) are ignored, and a value that fails
validation is logged and skipped.

The Wi-Fi password is stored on the card in plain text. On a Pi 5 with a WPA2/WPA3 router,
a profile holding the derived WPA2 key failed to connect, and the same profile holding the
password connected. The card copy is deleted on first boot, and the copy on the Pi can only
be read by root.

## What happens on first boot

1. The root partition grows to fill the card.
2. A new pacman keyring, new SSH host keys and a new machine ID are generated, so no two
   Pis share them.
3. The preset settings are applied, and then deleted from the card. The account is added to
   the `wheel` group for sudo and to `i2c`, which lets the desktop control monitor
   brightness.
4. If no account was preset, a setup screen asks for a username, a password and a computer
   name, and offers to connect to Wi-Fi.
5. The login screen appears.

The first boot takes about 20 seconds longer than later ones, most of it spent generating
the pacman keyring.
