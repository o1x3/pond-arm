# pond-arm

pond-arm builds [Pond](https://butterfly.so/), Butterfly's Arch-based desktop, for ARM
computers. The result is an SD card image that you flash and boot. Right now the only
supported board is the Raspberry Pi 5.

This is an unofficial port. Butterfly only ships Pond for x86_64 PCs, so pond-arm rebuilds
Pond's own packages for aarch64 from
[pond-pkgbuilds](https://github.com/amarsbar/pond-pkgbuilds) and installs them on Arch
Linux ARM. Everything else in Pond's system, from the package list to the btrfs layout, is
recreated from the root filesystem that Pond's installer downloads.

## Status

The image runs on a Raspberry Pi 5 with 4 GB of RAM. The login screen comes up 13 seconds
after the kernel starts, and the desktop renders on the Pi's GPU. Wi-Fi, Bluetooth, HDMI audio,
updates, Flathub and Nix all work. The [compatibility notes](docs/compatibility.md) say
what was tested and how.

Some things don't work, or work differently than they do on a PC:

* Apps without a Linux ARM build can't be installed, which rules out Discord, Spotify,
  Steam, OBS and Zoom among others. About 86% of the apps in Pond's catalogue do install.
* Butterfly doesn't publish ARM packages, so Pond's own packages only change when you
  rebuild the image. Everything from Arch Linux ARM updates normally with `pacman -Syu`.
* There's no snapshot boot menu. Snapshots are still taken before and after every update,
  but you roll back from a running system.
* Sleep locks the screen and nothing more, because the Pi 5 can't suspend.

## Requirements

You'll need Docker and about 30 GB of free disk space. The build runs in an arm64 container,
so it's fastest on a Mac with Apple Silicon or an aarch64 Linux machine. On an x86_64
machine, Docker has to emulate arm64. Docker Desktop does this out of the box, and on Linux
you can enable it once with `docker run --privileged --rm tonistiigi/binfmt --install arm64`.
An emulated build is much slower and hasn't been tested. [OrbStack](https://orbstack.dev/)
works as the Docker engine on macOS.

The Pi needs a 5 V, 5 A USB-C power supply and a microSD card of at least 16 GB. A laptop
or phone charger will boot it, but the Pi throttles itself and limits its USB ports.

## Building

```sh
git clone https://github.com/o1x3/pond-arm
cd pond-arm
./pond-pi build
```

The first build takes about 25 minutes. Later builds reuse the compiled packages and take
about 15. The image is written to `out/pond-pi5-<date>.img.xz`, along with its checksum, a
report of the hardware checks (`.compat.txt`), and a manifest for Raspberry Pi Imager.

## Flashing

On macOS, `pond-pi flash` writes the card, reads it back to verify it, and presets your
account, SSH key and Wi-Fi:

```sh
./pond-pi flash out/pond-pi5-*.img.xz -- \
    --user you --ssh-key ~/.ssh/id_ed25519.pub \
    --wifi-ssid "Home" --wifi-country GB --timezone Europe/London
```

It asks for passwords at a prompt, which keeps them out of your shell history. After the Pi
boots, connect with `ssh you@pond.local`.

Raspberry Pi Imager works too, and so does any other tool that writes disk images.
[Flashing and first boot](docs/flashing.md) covers both, and every preset option.

## Documentation

* [Flashing and first boot](docs/flashing.md)
* [Compatibility](docs/compatibility.md)
* [Troubleshooting](docs/troubleshooting.md)
* [Development](docs/development.md)

## Licence

The code in this repository is released under the [BSD 3-Clause licence](LICENSE).

Pond's packages and configuration belong to Butterfly Interaction Inc. and the other
authors, under their own licences. The Pond Gramercy fonts in `overlay/usr/share/fonts/`
are copied from Pond's root filesystem, which ships them without a licence, so this
repository's licence doesn't cover them. Ask Butterfly before you redistribute the fonts or
a built image.
