#!/bin/bash
# Fallback first-user setup on tty1, for cards flashed without user-data.
# Skipped once any regular account exists (e.g. created by pond-firstboot).
set -uo pipefail

done_marker() { mkdir -p /var/lib/pond && touch /var/lib/pond/setup-done; }

if getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 { found = 1 } END { exit !found }'; then
    done_marker
    exit 0
fi

# Readable on a 1080p/4K TV: kbd's 32px font instead of the 8x16 default.
setfont latarcyrheb-sun32 2>/dev/null
clear
printf '\n  Welcome to Pond on Raspberry Pi.\n  Create your account to finish setup.\n\n'

while true; do
    read -rp '  Username: ' username
    [[ $username =~ ^[a-z_][a-z0-9_-]{0,31}$ && $username != root ]] && break
    echo '  Use lowercase letters, numbers, underscore or hyphen; start with a letter or underscore.'
done

while true; do
    read -rsp '  Password: ' password; echo
    read -rsp '  Confirm password: ' confirm; echo
    if [[ -z $password ]]; then
        echo '  Enter a password.'
    elif [[ $password != "$confirm" ]]; then
        echo '  The passwords do not match.'
    else
        break
    fi
done

read -rp '  Computer name [pond]: ' hostname
hostname=${hostname:-pond}
until [[ $hostname =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; do
    read -rp '  Use up to 63 letters, numbers or dashes: ' hostname
done

useradd -m -G wheel,audio,video,input "$username" || exit 1
printf '%s:%s\n' "$username" "$password" | chpasswd || { userdel -r "$username"; exit 1; }
unset password confirm
echo "$hostname" > /etc/hostname
hostname "$hostname"

read -rp '  Set up Wi-Fi now? [y/N] ' wifi
if [[ $wifi == [yY]* ]]; then
    systemctl start NetworkManager.service
    nmtui-connect
fi

done_marker
printf '\n  Done. Starting Pond...\n'
setfont 2>/dev/null
