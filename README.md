# pond-arm

[Pond](https://butterfly.so/) (Butterfly's Arch-based niri desktop) for ARM boards, as a
flashable image, plus the tooling to build it, preset it the way Raspberry Pi Imager does,
and write it to a card. **Supported today: Raspberry Pi 5.**

This is an unofficial port. Butterfly ships Pond for x86_64 PCs only, as an installer ISO.
This project rebuilds Pond's own packages for aarch64 from
[pond-pkgbuilds](https://github.com/amarsbar/pond-pkgbuilds) and reconstructs the rest of
Pond's root filesystem (package set, configuration, services, btrfs layout) on top of
Arch Linux ARM, from Pond's published rootfs (`pond-rootfs.tar.zst`, sha256 `1feff559…`).

> **Status:** runs on a physical Raspberry Pi 5 (4 GB): 22 s to the login screen, Pond's
> desktop on the V3D GPU, Wi-Fi, Bluetooth, HDMI audio, updates with snapshots, Flathub and
> Nix. See [compatibility](docs/compatibility.md) for what has been verified and how.

## Quick start

Requirements: macOS on Apple Silicon or aarch64 Linux, Docker (OrbStack works), about 20 GB free.

```sh
./pond-pi build        # ~25 min the first time: packages, rootfs, image -> out/
./pond-pi flash out/pond-pi5-*.img.xz -- \
    --user you --ssh-key ~/.ssh/id_ed25519.pub \
    --wifi-ssid "Home" --wifi-country GB --timezone Europe/London
```

`flash` (macOS) writes the card, verifies it against the build's checksum and presets your
account, SSH key and Wi-Fi. It prompts for passwords, so they never reach your shell history.
Then boot the Pi with the card and run `ssh you@pond.local`.

Raspberry Pi Imager works too: `rpi-imager --repo out/pond-pi5.rpi-imager-manifest`.
[Flashing and first boot](docs/flashing.md) covers every option.

| Output in `out/` | What |
|---|---|
| `pond-pi5-<date>.img.xz` (+ `.sha256`) | the image, about 2 GB (4.4 GB written) |
| `pond-pi5-<date>.compat.txt` | the compatibility check for this build |
| `pond-pi5.rpi-imager-manifest` | opens the image in Raspberry Pi Imager with customisation |

## Docs

- [Flashing and first boot](docs/flashing.md): `flash`, Imager, `customize` options, what first boot does
- [Compatibility](docs/compatibility.md): hardware matrix, boards, differences from PC Pond, which apps install
- [Troubleshooting](docs/troubleshooting.md): `pond-pi-doctor`, power, bootloader EEPROM, NVMe, recovery
- [Development](docs/development.md): how the build works, tests, repository layout

## Repository layout

```
pond-pi        CLI: build, flash (macOS), customize, manifest
build/         builder container setup, package build, image build, compatibility check
overlay/       files laid over Pond's root filesystem (configs, first-boot services, doctor)
tools/         pondpi.py: cloud-init seed writer and Imager manifest
tests/         self-tests and the QEMU boot harness
docs/          documentation
```

## Licence

This repository's own code is under the [BSD-3-Clause licence](LICENSE).

Pond's packages and configuration are © Butterfly Interaction Inc. and their authors, under
their own licences: BSD-3-Clause for pond-interface and the installer, OFL for the bundled
third-party fonts. The Pond Gramercy fonts in `overlay/usr/share/fonts/` are copied from
Pond's published rootfs, where they ship without a licence; they are not covered by this
repository's licence. Check with Butterfly before redistributing the fonts or the image.
