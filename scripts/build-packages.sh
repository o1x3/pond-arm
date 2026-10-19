#!/usr/bin/env bash
# Build Pond's own packages for aarch64 inside the ALARM builder container.
# Sources: github.com/amarsbar/pond-pkgbuilds (mounted read-only at /src).
# Output: a local pacman repo at /w/repo (pond-pi.db).
set -euo pipefail

SRC=/src/pond-pkgbuilds
WORK=/w/pkgbuild
REPO=/w/repo
PONDREPO=https://repo.butterfly.so/x86_64

# Build order matters: later packages depend on earlier ones via the local repo.
PACKAGES=(
  ttf-onest
  ttf-advent-pro
  hyprtoolkit
  paru
  pond-interface/pond-wallpaper
  pond-interface/pond-lockscreen
  pond-interface/pond-screenshot
  pond-interface/pond-plymouth-theme
  package-manager/pond-pm
  pond-launcher
  package-manager/pond-pm-extension
  pond-interface/pond-shell
  ananicy-rules
  pond-system-optimizations
  pond-snapper-support
  pond-fish-config
)
# AUR-derived 'any' packages Pond ships without a PKGBUILD in pond-pkgbuilds.
# Architecture-independent, so the signed x86_64-repo builds are reused as-is.
PREBUILT_ANY=(fish-autopair fish-pure-prompt)

mkdir -p "$WORK" "$REPO"
chown builder: "$WORK" "$REPO"

if ! grep -q '^\[pond-pi\]' /etc/pacman.conf; then
  printf '\n[pond-pi]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$REPO" >> /etc/pacman.conf
fi
[[ -f $REPO/pond-pi.db ]] || sudo -u builder repo-add -q "$REPO/pond-pi.db.tar.zst"

for pkg in "${PACKAGES[@]}"; do
  name=${pkg##*/}
  if compgen -G "$REPO/$name-[0-9]*.pkg.tar.*" >/dev/null || compgen -G "$REPO/$name-[0-9]*:*.pkg.tar.*" >/dev/null; then
    echo ">>> $name: already built"
    continue
  fi
  echo ">>> building $name"
  rm -rf "${WORK:?}/$name"
  cp -a "$SRC/$pkg" "$WORK/$name"
  chown -R builder: "$WORK/$name"
  # Pond only declares x86_64 for some packages; the code is portable.
  sed -i -E "/^arch=/{/aarch64|'any'|\(any\)/! s/\)$/ 'aarch64')/}" "$WORK/$name/PKGBUILD"
  pacman -Sy >/dev/null
  (cd "$WORK/$name" && sudo -u builder MAKEFLAGS="-j$(nproc)" makepkg -s --noconfirm --skippgpcheck --nocheck -f) \
    > "$WORK/$name.log" 2>&1 || { echo "!!! $name failed; tail of $WORK/$name.log:"; tail -40 "$WORK/$name.log"; exit 1; }
  for f in "$WORK/$name"/*.pkg.tar.*; do
    [[ $f == *-debug-* ]] && continue
    cp "$f" "$REPO/"
    sudo -u builder repo-add -q "$REPO/pond-pi.db.tar.zst" "$REPO/$(basename "$f")"
  done
done

# Prebuilt 'any' packages: verify against Pond's signing key before trusting them.
# The fingerprint matches /usr/share/pacman/keyrings/pond.gpg in Pond's rootfs.
POND_KEY=B14C6E33AD2B9746842FFD245E3D63FCAA540F08
export GNUPGHOME=$(mktemp -d)
gpg -q --import "$SRC/.github/keys/pond-repository.asc"
gpg --with-colons --fingerprint | grep -q "^fpr:::::::::$POND_KEY:" || { echo "Pond key fingerprint mismatch"; exit 1; }
echo "$POND_KEY:6:" | gpg -q --import-ownertrust
for name in "${PREBUILT_ANY[@]}"; do
  compgen -G "$REPO/$name-*.pkg.tar.*" >/dev/null && { echo ">>> $name: already present"; continue; }
  file=$(bsdtar -xOf /w/ponddb/pond.db "$(bsdtar -tf /w/ponddb/pond.db | grep -E "^$name-[^/]+/desc$")" | sed -n '/%FILENAME%/{n;p;}')
  curl -sSfL -o "$REPO/$file" "$PONDREPO/$file"
  curl -sSfL -o "$REPO/$file.sig" "$PONDREPO/$file.sig"
  gpg -q --verify "$REPO/$file.sig" "$REPO/$file"
  bsdtar -xOf "$REPO/$file" .PKGINFO | grep -qx 'arch = any' || { echo "$name is not arch=any"; exit 1; }
  rm "$REPO/$file.sig"
  chown builder: "$REPO/$file"
  sudo -u builder repo-add -q "$REPO/pond-pi.db.tar.zst" "$REPO/$file"
done
rm -rf "$GNUPGHOME"
echo ">>> done"; ls "$REPO"
