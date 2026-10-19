#!/usr/bin/env python3
"""Apply cloud-init NoCloud settings from the boot partition, once per instance.

Reads the subset that Raspberry Pi Imager (init_format "cloudinit") and
`pond-pi customize` write: hostname, timezone, locale, keyboard, one user with
a crypt hash and SSH keys, SSH password auth, and Wi-Fi from network-config.
Nothing is executed from user-data: runcmd, packages, write_files and bootcmd
are ignored. The files hold secrets, so they are deleted once applied.
"""
import logging
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys
import uuid

import yaml

BOOT = Path("/boot")
STATE = Path("/var/lib/pond/firstboot-instance")
USERNAME = re.compile(r"[a-z_][a-z0-9_-]{0,31}")
HOSTNAME = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?")
CRYPT_HASH = re.compile(r"\$(?:y|gy|7|2[abxy]|5|6)\$[./A-Za-z0-9$,=]+")
GROUPS = "wheel,audio,video,input"

log = logging.getLogger("pond-firstboot")


def run(*argv, **kwargs):
    return subprocess.run(argv, check=True, **kwargs)


def load(name):
    path = BOOT / name
    if not path.is_file():
        return None
    data = yaml.safe_load(path.read_text(errors="replace"))
    return data if isinstance(data, dict) else {}


def set_hostname(name):
    if not isinstance(name, str) or not HOSTNAME.fullmatch(name):
        raise ValueError("invalid hostname")
    Path("/etc/hostname").write_text(name + "\n")
    # systemd read /etc/hostname earlier in boot; update the running name too.
    try:
        Path("/proc/sys/kernel/hostname").write_text(name)
    except OSError as error:
        log.warning("hostname applies from next boot: %s", error)


def set_timezone(zone):
    if not isinstance(zone, str) or ".." in zone.split("/") or not (Path("/usr/share/zoneinfo") / zone).is_file():
        raise ValueError("unknown timezone")
    Path("/etc/localtime").unlink(missing_ok=True)
    Path("/etc/localtime").symlink_to(f"/usr/share/zoneinfo/{zone}")


def set_locale(locale):
    # Same steps as Pond's installer (system.configure_locale), but glibc lists
    # UTF-8-default locales without a codeset ("en_IN UTF-8"), so match both forms
    # and use glibc's spelling.
    supported = {line.split()[0] for line in Path("/usr/share/i18n/SUPPORTED").read_text().splitlines()
                 if line.endswith(" UTF-8")}
    if not isinstance(locale, str):
        raise ValueError("unsupported locale")
    base = re.sub(r"\.(?i:utf-?8)", "", locale)
    name = next((n for n in (locale, base, f"{base}.UTF-8") if n in supported), None)
    if name is None:
        raise ValueError("unsupported locale")
    Path("/etc/locale.gen").write_text(f"{name} UTF-8\n")
    run("locale-gen", stdout=subprocess.DEVNULL)
    Path("/etc/locale.conf").write_text(f"LANG={name}\nLC_MESSAGES={name}\n")


def set_keyboard(layout):
    # Same files as Pond's installer (system.configure_keyboard).
    if not isinstance(layout, str) or not re.fullmatch(r"[a-z0-9_-]+", layout):
        raise ValueError("invalid keyboard layout")
    directory = Path("/etc/X11/xorg.conf.d")
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "00-keyboard.conf").write_text(
        'Section "InputClass"\n    Identifier "system-keyboard"\n    MatchIsKeyboard "on"\n'
        f'    Option "XkbLayout" "{layout}"\n    Option "XkbVariant" ""\nEndSection\n')
    for line in Path("/usr/share/systemd/kbd-model-map").read_text().splitlines():
        fields = line.split()
        if len(fields) >= 4 and fields[1] == layout and fields[3] == "-":
            Path("/etc/vconsole.conf").write_text(f"KEYMAP={fields[0]}\n")
            break


def users_of(user_data):
    # Imager writes a single `user:`; standard cloud-init uses a `users:` list.
    found = []
    if isinstance(user_data.get("user"), dict):
        found.append(user_data["user"])
    for entry in user_data.get("users") or []:
        if isinstance(entry, dict):
            found.append(entry)
    return found


def create_user(spec):
    name = spec.get("name")
    if not isinstance(name, str) or not USERNAME.fullmatch(name) or name == "root":
        raise ValueError("invalid username")
    try:
        pwd.getpwnam(name)
    except KeyError:
        # Shell comes from /etc/default/useradd (fish, as on Pond); sudo comes
        # from wheel with a password, so Imager's NOPASSWD request is not honoured.
        run("useradd", "-m", "-G", GROUPS, name)
    hashed = spec.get("passwd") or spec.get("hashed_passwd")
    plain = spec.get("plain_text_passwd")
    if isinstance(hashed, str) and CRYPT_HASH.fullmatch(hashed):
        run("chpasswd", "-e", input=f"{name}:{hashed}\n", text=True)
    elif isinstance(plain, str) and plain and not any(c in plain for c in "\n\r:\0"):
        run("chpasswd", input=f"{name}:{plain}\n", text=True)
    elif hashed or plain:
        raise ValueError(f"unusable password for {name}")
    if spec.get("lock_passwd") is True:
        run("passwd", "-l", name)
    keys = [k.strip() for k in spec.get("ssh_authorized_keys") or [] if isinstance(k, str) and k.strip()]
    if keys:
        entry = pwd.getpwnam(name)
        ssh_dir = Path(entry.pw_dir) / ".ssh"
        ssh_dir.mkdir(mode=0o700, exist_ok=True)
        authorized = ssh_dir / "authorized_keys"
        authorized.write_text("".join(key.replace("\n", " ") + "\n" for key in keys))
        authorized.chmod(0o600)
        for path in (ssh_dir, authorized):
            os.chown(path, entry.pw_uid, entry.pw_gid)
    return bool(keys)


def ssh_requested(user_data, have_keys):
    # Imager enables SSH through runcmd; read that intent without executing it.
    runcmd = str(user_data.get("runcmd") or "")
    return have_keys or user_data.get("ssh_pwauth") is True or bool(re.search(r"enable.*\bsshd?\b", runcmd))


def enable_ssh(password_auth):
    conf = Path("/etc/ssh/sshd_config.d/50-pond-firstboot.conf")
    conf.parent.mkdir(parents=True, exist_ok=True)
    conf.write_text(f"PasswordAuthentication {'yes' if password_auth else 'no'}\n"
                    "KbdInteractiveAuthentication no\nPermitRootLogin no\n")
    # --no-block: sshd waits for network.target, which waits for this unit.
    run("systemctl", "enable", "sshd.service")
    if subprocess.run(["systemctl", "start", "--no-block", "sshd.service"]).returncode:
        log.warning("sshd starts from next boot")
    # Pond's ufw default drops inbound traffic.
    run("ufw", "allow", "22/tcp", stdout=subprocess.DEVNULL)


def keyfile_escape(value):
    # GKeyFile string escaping, enough for a PSK that has no control characters.
    value = value.replace("\\", "\\\\")
    return "\\s" + value[1:] if value.startswith(" ") else value


def add_wifi(ssid, settings):
    if not isinstance(ssid, str) or not 0 < len(ssid.encode()) <= 32:
        raise ValueError("invalid SSID")
    settings = settings if isinstance(settings, dict) else {}
    password = settings.get("password")
    auth = settings.get("auth") if isinstance(settings.get("auth"), dict) else {}
    if auth.get("key-management") == "none":
        password = None
    if password is not None:
        password = str(password)
        if any(c in password for c in "\n\r\0") or not (8 <= len(password) <= 63 or re.fullmatch(r"[0-9a-fA-F]{64}", password)):
            raise ValueError("invalid Wi-Fi password")
    connection_id = str(uuid.uuid4())
    # The byte-list form avoids escaping problems for any SSID.
    lines = ["[connection]", f"id=pond-wifi-{connection_id[:8]}", f"uuid={connection_id}", "type=wifi",
             "autoconnect=true", "", "[wifi]", "mode=infrastructure",
             "ssid=" + ";".join(str(b) for b in ssid.encode()) + ";"]
    if settings.get("hidden") is True:
        lines.append("hidden=true")
    if password is not None:
        lines += ["", "[wifi-security]", "key-mgmt=wpa-psk", f"psk={keyfile_escape(password)}"]
    lines += ["", "[ipv4]", "method=auto", "", "[ipv6]", "method=auto", ""]
    directory = Path("/etc/NetworkManager/system-connections")
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = directory / f"pond-wifi-{connection_id[:8]}.nmconnection"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write("\n".join(lines))


def set_country(country):
    if not isinstance(country, str) or not re.fullmatch(r"[A-Z]{2}", country):
        raise ValueError("invalid Wi-Fi country")
    # Read by Pond's /usr/lib/iw-set-regdomain.
    Path("/etc/iw-regdomain").write_text(f"COUNTRY={country}\n")
    subprocess.run(["iw", "reg", "set", country], check=False)


def apply_network(network):
    config = network.get("network", network)
    for interface in (config.get("wifis") or {}).values():
        if not isinstance(interface, dict):
            continue
        country = interface.get("regulatory-domain")
        if country:
            step("Wi-Fi country", set_country, str(country).upper())
        for ssid, settings in (interface.get("access-points") or {}).items():
            step("Wi-Fi network", add_wifi, ssid, settings)


failures = 0


def step(label, function, *args):
    global failures
    try:
        return function(*args)
    except Exception as error:
        failures += 1
        log.error("%s failed: %s", label, error)


def cleanup():
    for name in ("user-data", "network-config", "meta-data"):
        (BOOT / name).unlink(missing_ok=True)
    cmdline = BOOT / "cmdline.txt"
    if cmdline.is_file():
        text = cmdline.read_text()
        cleaned = re.sub(r"\s+ds=nocloud\S*", "", text)
        if cleaned != text:
            cmdline.write_text(cleaned)


def main():
    logging.basicConfig(level=logging.INFO, format="%(name)s: %(message)s")
    meta = load("meta-data") or {}
    user_data = load("user-data")
    network = load("network-config")
    if user_data is None and network is None:
        log.info("no cloud-init seed on %s", BOOT)
        return 0
    instance = str(meta.get("instance-id") or "")
    if instance and STATE.is_file() and STATE.read_text().strip() == instance:
        log.info("instance %s already applied", instance)
        cleanup()
        return 0
    user_data = user_data or {}
    if user_data.get("hostname"):
        step("hostname", set_hostname, user_data["hostname"])
    if user_data.get("timezone"):
        step("timezone", set_timezone, user_data["timezone"])
    if user_data.get("locale"):
        step("locale", set_locale, user_data["locale"])
    keyboard = user_data.get("keyboard")
    if isinstance(keyboard, dict) and keyboard.get("layout"):
        step("keyboard", set_keyboard, keyboard["layout"])
    have_keys = False
    for spec in users_of(user_data):
        have_keys |= bool(step(f"user {spec.get('name')!r}", create_user, spec))
    if network:
        apply_network(network)
    if ssh_requested(user_data, have_keys):
        step("ssh", enable_ssh, user_data.get("ssh_pwauth") is True)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(instance + "\n")
    cleanup()
    log.info("applied boot partition settings with %d failure(s)", failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
