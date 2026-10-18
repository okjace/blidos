#!/bin/bash
# Publishes a BlidOS version on GitHub (okjace/blidos): the update file, the ISO and checksums.
# GitHub limits each file to 2 GB, so a bigger ISO is uploaded in parts (joined again after
# downloading; the release notes say how).
# usage: os/tools/release.sh VERSION [OUT_DIR]
set -euo pipefail
VERSION=$1
OUT=${2:-$HOME/blidos-os-build/out}
REPO=$(cat "$(dirname "$0")/../rootfs/etc/blidos/update-source")
ISO=$OUT/BlidOS-$VERSION-x86_64.iso
DEB=$OUT/blidos_${VERSION}_all.deb
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

files=()
[ -f "$DEB" ] && files+=("$DEB")
if [ -f "$ISO" ]; then
    if [ "$(stat -c %s "$ISO")" -gt 2000000000 ]; then
        split -b 1900M -d -a 1 "$ISO" "$STAGE/BlidOS-$VERSION-x86_64.iso.part"
        files+=("$STAGE"/BlidOS-$VERSION-x86_64.iso.part*)
        PARTS=yes
    else
        files+=("$ISO")
    fi
fi
(cd "$OUT" && sha256sum "$(basename "$ISO")" ${DEB:+$(basename "$DEB")} 2>/dev/null) > "$STAGE/SHA256SUMS" || true
files+=("$STAGE/SHA256SUMS")

{
    echo "BlidOS $VERSION, a TV operating system for PCs (Debian 13, Android apps, profiles with PINs)."
    echo
    echo "**New install:** write the ISO to a USB stick (balenaEtcher, Rufus in DD mode, or Ventoy), boot it and choose Install BlidOS."
    if [ "${PARTS:-}" = yes ]; then
        echo
        echo "The ISO is bigger than GitHub's 2 GB limit, so it's in parts. Download every \`.part\` file, then join them:"
        echo
        echo "- Linux or Mac: \`cat BlidOS-$VERSION-x86_64.iso.part* > BlidOS-$VERSION-x86_64.iso\`"
        echo "- Windows (Command Prompt): \`copy /b BlidOS-$VERSION-x86_64.iso.part0 + BlidOS-$VERSION-x86_64.iso.part1 BlidOS-$VERSION-x86_64.iso\`"
        echo
        echo "Check it against SHA256SUMS before writing it to a stick."
    fi
    echo
    echo "**Updating:** BlidOS 0.5.1 and newer find new versions here by themselves (Settings → Updates). Older versions: copy \`blidos_${VERSION}_all.deb\` to a USB stick (FAT32 or exFAT), plug it in and open Settings → Updates. Profiles, apps and files stay as they are."
} > "$STAGE/notes.md"

if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "${files[@]}" --repo "$REPO" --clobber
else
    gh release create "v$VERSION" "${files[@]}" --repo "$REPO" --title "BlidOS $VERSION" --notes-file "$STAGE/notes.md"
fi
echo "Published: https://github.com/$REPO/releases/tag/v$VERSION"
