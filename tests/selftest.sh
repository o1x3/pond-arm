#!/usr/bin/env bash
# Fast checks that need no Pi and no VM (about a minute, Docker required):
#   1. pond-pi customize -> firstboot.py round trip, asserting the applied system state
#   2. firstboot.py on hostile input: rejects it and never executes user-data
#   3. the Imager manifest (if built) against Raspberry Pi Imager's JSON schema
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
check() { if eval "$2"; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi; }

# Runs firstboot.py as root in a throwaway Arch Linux ARM container against BOOT
# and prints the resulting state as KEY=VALUE lines.
apply_seed() {
    docker run --rm --platform linux/arm64 -v "$1:/boot" -v "$HERE/overlay/usr/lib/pond-pi:/t:ro" alarm:base bash -c '
        sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
        pacman-key --init >/dev/null 2>&1; pacman-key --populate archlinuxarm >/dev/null 2>&1
        for try in 1 2 3; do
            pacman -Sy --noconfirm --needed python-yaml openssh ufw iw i2c-tools >/dev/null 2>&1 && break
            [[ $try == 3 ]] && { echo "setup=failed"; exit; }
            sleep 5
        done
        echo "setup=ok"
        python3 /t/firstboot.py >/tmp/log 2>&1; echo "exit=$?"
        echo "user=$(getent passwd karthik | cut -d: -f1)"
        echo "groups=$(id -nG karthik 2>/dev/null | tr " " ",")"
        echo "hash=$(getent shadow karthik | cut -d: -f2 | cut -c1-3)"
        echo "keys=$(stat -c %a:%U /home/karthik/.ssh/authorized_keys 2>/dev/null)"
        echo "pwauth=$(sed -n "s/^PasswordAuthentication //p" /etc/ssh/sshd_config.d/50-pond-firstboot.conf 2>/dev/null)"
        echo "sshd=$(test -L /etc/systemd/system/multi-user.target.wants/sshd.service && echo enabled)"
        echo "hostname=$(cat /etc/hostname)"
        echo "tz=$(readlink /etc/localtime)"
        echo "lang=$(sed -n "s/^LANG=//p" /etc/locale.conf)"
        echo "keymap=$(sed -n "s/^KEYMAP=//p" /etc/vconsole.conf 2>/dev/null)"
        echo "country=$(sed -n "s/^COUNTRY=//p" /etc/iw-regdomain 2>/dev/null)"
        f=$(ls /etc/NetworkManager/system-connections/*.nmconnection 2>/dev/null | head -1)
        echo "wifimode=$(stat -c %a "$f" 2>/dev/null)"
        echo "ssid=$(sed -n "s/^ssid=//p" "$f" 2>/dev/null | tr ";" " " | xargs -n1 2>/dev/null | python3 -c "import sys; print(bytes(int(x) for x in sys.stdin.read().split()).decode())" 2>/dev/null)"
        echo "pwned=$(test -e /tmp/pwned && echo yes)"
        echo "seed_left=$(ls /boot | grep -cE "^(user-data|network-config|meta-data)$")"
        echo "cmdline=$(cat /boot/cmdline.txt)"
        grep -E "failed" /tmp/log | sed "s/^/log=/"'
}

echo "1. customize -> first boot round trip"
mkdir -p "$T/boot" && echo "root=PARTUUID=x rw ds=nocloud;i=1" > "$T/boot/cmdline.txt" && touch "$T/boot/config.txt"
ssh-keygen -q -t ed25519 -N '' -f "$T/key" -C selftest
python3 "$HERE/tools/pondpi.py" customize "$T/boot" --hostname pi-self --user karthik \
    --password-hash "$(printf 'pw' | openssl passwd -6 -stdin)" --ssh-key "$T/key.pub" \
    --wifi-ssid 'Café;"x' --wifi-password 'p@ss \word1' --wifi-country in \
    --timezone Asia/Kolkata --locale en_IN.UTF-8 --keyboard us >/dev/null
state=$(apply_seed "$T/boot"); [[ -n ${DEBUG:-} ]] && echo "$state"
get() { sed -n "s/^$1=//p" <<<"$state"; }
[[ $(get setup) == ok ]] || { echo "  could not install test dependencies in the container (mirror down?); rerun"; exit 2; }
check "applies cleanly"                 '[[ $(get exit) == 0 ]]'
check "user in wheel/video/input/i2c"   '[[ $(get groups) == *wheel* && $(get groups) == *video* && $(get groups) == *input* && $(get groups) == *i2c* ]]'
check "password stored as crypt hash"   '[[ $(get hash) == "\$6\$" ]]'
check "authorized_keys 600, user-owned" '[[ $(get keys) == 600:karthik ]]'
check "SSH keys-only, sshd enabled"     '[[ $(get pwauth) == no && $(get sshd) == enabled ]]'
check "hostname / timezone / locale"    '[[ $(get hostname) == pi-self && $(get tz) == */Asia/Kolkata && $(get lang) == en_IN ]]'
check "console keymap"                  '[[ $(get keymap) == us ]]'
check "Wi-Fi keyfile 600, SSID intact"  '[[ $(get wifimode) == 600 && $(get ssid) == '"'"'Café;"x'"'"' ]]'
check "regulatory domain"               '[[ $(get country) == IN ]]'
check "seed deleted, ds= stripped"      '[[ $(get seed_left) == 0 && $(get cmdline) != *ds=nocloud* ]]'

echo "2. hostile seed"
mkdir -p "$T/evil" && echo "rw" > "$T/evil/cmdline.txt"
cat > "$T/evil/user-data" <<'EOF'
#cloud-config
hostname: "evil;touch /tmp/pwned"
timezone: "../../../../etc/shadow"
keyboard: {layout: "us\"; touch /tmp/pwned; \""}
runcmd: [[touch, /tmp/pwned]]
bootcmd: [[touch, /tmp/pwned]]
write_files: [{path: /tmp/pwned, content: x}]
user: {name: "root", passwd: "x"}
EOF
cat > "$T/evil/network-config" <<'EOF'
network: {version: 2, wifis: {wlan0: {regulatory-domain: "XX;rm", access-points: {"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {password: "short"}}}}}
EOF
state=$(apply_seed "$T/evil")
[[ $(get setup) == ok ]] || { echo "  could not install test dependencies in the container (mirror down?); rerun"; exit 2; }
check "nothing executed from user-data" '[[ -z $(get pwned) ]]'
check "bad values rejected, not applied" '[[ $(get hostname) != *evil* && -z $(get user) && -z $(get country) && -z $(get wifimode) ]]'
check "each rejection is logged"        '[[ $(grep -c "^log=" <<<"$state") -ge 5 ]]'

echo "3. Raspberry Pi Imager manifest"
if [[ -f $HERE/out/pond-pi5.rpi-imager-manifest ]]; then
    curl -sSfL -o "$T/schema.json" https://raw.githubusercontent.com/raspberrypi/rpi-imager/main/doc/json-schema/os-list-schema.json
    check "valid against Imager's schema" 'uvx --quiet --from jsonschema python -c "
import json, jsonschema, sys
jsonschema.Draft7Validator(json.load(open(sys.argv[1]))).validate(json.load(open(sys.argv[2])))" "$T/schema.json" "$HERE/out/pond-pi5.rpi-imager-manifest"'
else
    echo "  skip  no out/pond-pi5.rpi-imager-manifest (run ./pond-pi build)"
fi

exit $fail
