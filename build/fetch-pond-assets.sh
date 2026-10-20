#!/usr/bin/env bash
# Fetch Pond's fonts and logo from Butterfly's own root filesystem download, the
# same file and checksum Pond's installer uses. They have no licence that would let
# this repository redistribute them, so every build gets them from Butterfly.
# Output: /w/pond-assets/usr/share/{fonts/otf-pond-gramercy,icons/.../pond.svg}.
set -euo pipefail

ROOTFS_SHA256=1feff559c2f8179a12fad152e6c31fc089f9f28b616f188605170f37819115b3
ROOTFS_URL=https://releases.butterfly.so/rootfs/$ROOTFS_SHA256/pond-rootfs.tar.zst
ASSETS=/w/pond-assets
DOWNLOAD=/w/pond-rootfs-$ROOTFS_SHA256.tar.zst
MEMBERS=('*usr/share/fonts/otf-pond-gramercy/*.otf' '*usr/share/icons/hicolor/scalable/apps/pond.svg')
FONT_COUNT=16

complete() {
    [[ $(cat "$ASSETS/.rootfs-sha256" 2>/dev/null) == "$ROOTFS_SHA256" ]] &&
        [[ $(find "$ASSETS/usr/share/fonts/otf-pond-gramercy" -name '*.otf' 2>/dev/null | wc -l) == "$FONT_COUNT" ]] &&
        [[ -s $ASSETS/usr/share/icons/hicolor/scalable/apps/pond.svg ]]
}

if complete; then
    echo ">>> Pond fonts and logo: cached"
    exit 0
fi

echo ">>> downloading Pond's root filesystem for its fonts and logo (about 2.5 GB, once)"
# -C - resumes a partial download after an interruption.
for attempt in 1 2 3 4 5; do
    curl -fL --progress-bar --retry 5 --retry-delay 5 -C - -o "$DOWNLOAD" "$ROOTFS_URL" && break
    (( attempt == 5 )) && { echo "pond-assets: download failed: $ROOTFS_URL" >&2; exit 1; }
    echo "download interrupted; retrying ($attempt/5)" >&2
    sleep 10
done

got=$(sha256sum "$DOWNLOAD" | cut -d' ' -f1)
if [[ $got != "$ROOTFS_SHA256" ]]; then
    rm -f "$DOWNLOAD"
    echo "pond-assets: checksum mismatch for $ROOTFS_URL (got $got); download removed, rerun to retry" >&2
    exit 1
fi

rm -rf "$ASSETS"
mkdir -p "$ASSETS"
tar -I zstd -xf "$DOWNLOAD" -C "$ASSETS" --wildcards --no-same-owner "${MEMBERS[@]}"
[[ -d $ASSETS/usr ]] || { echo "pond-assets: nothing extracted from the download" >&2; exit 1; }
echo "$ROOTFS_SHA256" > "$ASSETS/.rootfs-sha256"

if ! complete; then
    echo "pond-assets: expected $FONT_COUNT fonts and pond.svg in the download, found:" >&2
    find "$ASSETS" -type f >&2
    exit 1
fi
rm -f "$DOWNLOAD"
echo ">>> Pond fonts and logo: extracted to $ASSETS"
