# pond-arm

pond-arm builds [Pond](https://butterfly.so/), Butterfly's Arch-based desktop, for 64-bit
ARM computers. Butterfly only ships Pond for x86_64 PCs, so this is an unofficial port.

The work splits into two layers. The shared layer is Pond itself: its packages rebuilt for
aarch64 from [pond-pkgbuilds](https://github.com/amarsbar/pond-pkgbuilds), installed on
Arch Linux ARM, with the rest of Pond's system (package set, configuration, services and
btrfs layout) recreated from the root filesystem that Pond's installer downloads. Each board
then adds a kernel, firmware, and a way to boot.

The Raspberry Pi 5 is the first board, and the only one supported today.

## Other ARM hardware

Pond's desktop needs an aarch64 machine with a Mesa GPU driver and a kernel with display
support. Arch Linux ARM's generic kernel and Mesa already cover most current ARM
GPUs, so for many boards the remaining work is booting: building the image in the layout
the board's firmware expects. The likely next targets are virtual machines on Apple Silicon,
the Raspberry Pi 4, and RK3588 boards such as the Orange Pi 5. Apple Silicon Macs and
Snapdragon laptops are possible but harder. [docs/porting.md](docs/porting.md) covers each
of them and suggests an order.

## Status on the Raspberry Pi 5

The image runs on a Raspberry Pi 5 with 4 GB of RAM. The login screen comes up 13 seconds
after the kernel starts, and the desktop renders on the Pi's GPU. Wi-Fi, Bluetooth, HDMI
audio, updates, Flathub and Nix all work. The [compatibility notes](docs/compatibility.md)
say what was tested and how.

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

The build tool is called `pond-pi` because the Pi is the only board so far. The first build
takes about 30 minutes, including a 2.5 GB download of Pond's root filesystem for its fonts
and logo. Later builds reuse the compiled packages and take about 15. The
image is written to `out/pond-pi5-<date>.img.xz`, along with its checksum, a report of the
hardware checks (`.compat.txt`), and a manifest for Raspberry Pi Imager.

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

* [Porting to other ARM hardware](docs/porting.md)
* [Development](docs/development.md)

Raspberry Pi 5:

* [Flashing and first boot](docs/flashing.md)
* [Compatibility](docs/compatibility.md)
* [Troubleshooting](docs/troubleshooting.md)

## Licence

The code in this repository is released under the [BSD 3-Clause licence](LICENSE).

Pond's packages and configuration belong to Butterfly Interaction Inc. and the other
authors, under their own licences. Pond's Gramercy fonts and logo have no licence that
allows redistribution, so they aren't in this repository. The build downloads them from
Butterfly, from the same root filesystem and checksum that Pond's installer uses. Built
images contain them, so ask Butterfly before you share an image.
