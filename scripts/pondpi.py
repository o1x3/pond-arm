#!/usr/bin/env python3
"""Customize a Pond Raspberry Pi image, or write a Raspberry Pi Imager manifest.

customize writes a cloud-init NoCloud seed (user-data, network-config,
meta-data) to the image's boot partition: the same files Raspberry Pi Imager
writes for init_format "cloudinit". The Pi applies them on first boot
(/usr/lib/pond-pi/firstboot.py) and then deletes them.
"""
import argparse
import getpass
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import uuid

USERNAME = re.compile(r"[a-z_][a-z0-9_-]{0,31}")
HOSTNAME = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?")
KEY_TYPES = ("ssh-", "ecdsa-", "sk-ssh-", "sk-ecdsa-")


def fail(message):
    sys.exit(f"pond-pi: {message}")


def hash_password(password):
    # Password goes over stdin, never argv. Needs OpenSSL 3 (not macOS LibreSSL).
    try:
        result = subprocess.run(["openssl", "passwd", "-6", "-stdin"], input=password + "\n",
                                capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        fail("`openssl passwd -6` failed; install OpenSSL 3 (brew install openssl) or pass --password-hash")
    hashed = result.stdout.strip()
    if not hashed.startswith("$6$"):
        fail("openssl did not return a SHA-512 crypt hash")
    return hashed


def prompt_secret(label):
    first = getpass.getpass(f"{label}: ")
    if getpass.getpass(f"Confirm {label.lower()}: ") != first:
        fail(f"{label.lower()} entries do not match")
    return first


def read_keys(paths):
    keys = []
    for path in paths:
        for line in Path(path).expanduser().read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                if not line.startswith(KEY_TYPES):
                    fail(f"{path}: not an SSH public key: {line[:40]}...")
                keys.append(line)
    return keys


def build_seed(args):
    user_data = {}
    if args.hostname:
        if not HOSTNAME.fullmatch(args.hostname):
            fail("hostname: up to 63 letters, numbers or dashes")
        user_data["hostname"] = args.hostname
    if args.timezone:
        user_data["timezone"] = args.timezone
    if args.locale:
        user_data["locale"] = args.locale
    if args.keyboard:
        user_data["keyboard"] = {"model": "pc105", "layout": args.keyboard}

    keys = read_keys(args.ssh_key)
    if args.user:
        if not USERNAME.fullmatch(args.user) or args.user == "root":
            fail("username: lowercase letters, numbers, _ or -, starting with a letter or _")
        if args.password_hash:
            hashed = args.password_hash
        else:
            password = prompt_secret("Password")
            if not password:
                fail("empty password")
            hashed = hash_password(password)
        user = {"name": args.user, "lock_passwd": False, "passwd": hashed}
        if keys:
            user["ssh_authorized_keys"] = keys
        user_data["user"] = user
    elif keys:
        fail("--ssh-key needs --user")
    if args.ssh or keys:
        # Keys present: key-only unless --ssh-password-auth. No keys: password login.
        user_data["ssh_pwauth"] = bool(args.ssh_password_auth or not keys)

    network = None
    if args.wifi_ssid:
        if not 0 < len(args.wifi_ssid.encode()) <= 32:
            fail("Wi-Fi SSID must be 1-32 bytes")
        point = {}
        if args.wifi_open:
            point["auth"] = {"key-management": "none"}
        else:
            password = args.wifi_password if args.wifi_password is not None else prompt_secret("Wi-Fi password")
            if not (8 <= len(password) <= 63 or re.fullmatch(r"[0-9a-fA-F]{64}", password)):
                fail("Wi-Fi password must be 8-63 characters (or a 64-hex PSK)")
            point["password"] = password
        if args.wifi_hidden:
            point["hidden"] = True
        wifi = {"dhcp4": True, "optional": True, "access-points": {args.wifi_ssid: point}}
        if args.wifi_country:
            if not re.fullmatch(r"[A-Za-z]{2}", args.wifi_country):
                fail("Wi-Fi country must be a 2-letter code, e.g. GB")
            wifi["regulatory-domain"] = args.wifi_country.upper()
        network = {"network": {"version": 2, "wifis": {"wlan0": wifi}}}
    elif args.wifi_country:
        fail("--wifi-country needs --wifi-ssid")

    if not user_data and network is None:
        fail("nothing to customize; see --help")
    files = {"meta-data": json.dumps({"instance-id": f"pond-{uuid.uuid4()}"}) + "\n",
             "user-data": "#cloud-config\n" + json.dumps(user_data, indent=2) + "\n"}
    if network is not None:
        files["network-config"] = json.dumps(network, indent=2) + "\n"
    return files


def boot_partition_offset(image):
    """Byte offset of GPT partition 1 (the FAT boot partition)."""
    with open(image, "rb") as disk:
        disk.seek(512)
        header = disk.read(92)
        if header[:8] != b"EFI PART":
            fail(f"{image}: no GPT header; is this a Pond image?")
        entries_lba = struct.unpack_from("<Q", header, 72)[0]
        disk.seek(entries_lba * 512 + 32)
        first_lba = struct.unpack("<Q", disk.read(8))[0]
    return first_lba * 512


def write_to_image(image, files):
    image = Path(image).resolve()
    offset = boot_partition_offset(image)
    with tempfile.TemporaryDirectory() as tmp:
        for name, content in files.items():
            path = Path(tmp) / name
            path.write_text(content)
            path.chmod(0o600)
        names = list(files)
        if shutil.which("mcopy"):
            subprocess.run(["mcopy", "-o", "-i", f"{image}@@{offset}", *(str(Path(tmp) / n) for n in names), "::/"],
                           check=True)
        else:
            # No local mtools (brew install mtools): use a throwaway container.
            copy = " ".join(f"/seed/{n}" for n in names)
            subprocess.run(["docker", "run", "--rm", "-v", f"{image.parent}:/img", "-v", f"{tmp}:/seed:ro",
                            "debian:trixie", "sh", "-c",
                            "apt-get -qq update >/dev/null && apt-get -qq install -y mtools >/dev/null && "
                            f"mcopy -o -i '/img/{image.name}@@{offset}' {copy} ::/"], check=True)


def customize(args):
    target = Path(args.target)
    if target.suffix in (".xz", ".zst", ".gz"):
        fail("decompress the image first (xz -dk FILE), or customize the card after flashing")
    files = build_seed(args)
    if target.is_dir():
        if not (target / "cmdline.txt").is_file() or not (target / "config.txt").is_file():
            fail(f"{target} does not look like a Pi boot partition")
        for name, content in files.items():
            (target / name).write_text(content)
    elif target.is_file():
        write_to_image(target, files)
    else:
        fail(f"{target}: no such image or directory")
    print(f"Wrote {', '.join(files)} to {target}. Settings apply on first boot.")


def manifest(args):
    image = Path(args.image).resolve()
    extract = image.with_name(image.name.removesuffix(".xz") + ".extract")
    if not extract.is_file():
        fail(f"missing {extract.name} (written by pond-pi build)")
    extract_size, extract_sha256 = extract.read_text().split()
    download_sha256 = (image.parent / (image.name + ".sha256")).read_text().split()[0]
    if not (image.parent / "pond-icon.png").is_file():
        fail("missing pond-icon.png next to the image (written by pond-pi build)")
    entry = {
        "name": "Pond (Raspberry Pi 5)",
        "description": "Pond desktop on Arch Linux ARM",
        "url": image.as_uri(),
        "extract_size": int(extract_size),
        "extract_sha256": extract_sha256,
        "image_download_size": image.stat().st_size,
        "image_download_sha256": download_sha256,
        "icon": (image.parent / "pond-icon.png").as_uri(),
        "release_date": re.search(r"(\d{4})\.(\d{2})\.(\d{2})", image.name).expand(r"\1-\2-\3"),
        "init_format": "cloudinit",
        "devices": ["pi5-64bit"],
    }
    data = {"imager": {"devices": [{"name": "Raspberry Pi 5",
                                    "description": "Raspberry Pi 5, Raspberry Pi 500 and Compute Module 5",
                                    "tags": ["pi5-64bit", "pi5-32bit"],
                                    "default": False, "matching_type": "exclusive"}]},
            "os_list": [entry]}
    out = image.parent / "pond-pi5.rpi-imager-manifest"
    out.write_text(json.dumps(data, indent=2) + "\n")
    print(out)


def main():
    parser = argparse.ArgumentParser(prog="pond-pi", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    c = commands.add_parser("customize", help="preset user, SSH, Wi-Fi and locale for first boot")
    c.add_argument("target", help="raw .img file, or the mounted boot partition (e.g. /Volumes/PONDBOOT)")
    c.add_argument("--hostname")
    c.add_argument("--user", help="create this account (added to wheel for sudo)")
    c.add_argument("--password-hash", help="crypt(3) hash instead of prompting (e.g. from openssl passwd -6)")
    c.add_argument("--ssh", action="store_true", help="enable SSH (implied by --ssh-key)")
    c.add_argument("--ssh-key", action="append", default=[], metavar="FILE",
                   help="authorized public key file; repeatable. Disables SSH password login")
    c.add_argument("--ssh-password-auth", action="store_true", help="allow SSH password login with keys too")
    c.add_argument("--wifi-ssid")
    c.add_argument("--wifi-password", help="avoid: visible in shell history; omit to be prompted")
    c.add_argument("--wifi-open", action="store_true", help="network has no password")
    c.add_argument("--wifi-hidden", action="store_true")
    c.add_argument("--wifi-country", help="2-letter regulatory domain, e.g. GB, US, IN")
    c.add_argument("--timezone", help="e.g. Europe/London")
    c.add_argument("--locale", help="e.g. en_GB.UTF-8")
    c.add_argument("--keyboard", help="XKB layout, e.g. gb, us, de")
    c.set_defaults(func=customize)

    m = commands.add_parser("manifest", help="write a Raspberry Pi Imager manifest for a built image")
    m.add_argument("image", help="the .img.xz produced by pond-pi build")
    m.set_defaults(func=manifest)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
