#!/bin/bash
# Copies BlidOS (kernel, initrd and Android system image) from the USB stick onto the chosen partition.
set -euo pipefail
ROOT="$1"
SRC=/run/live/medium/blidos
DEST="$ROOT/blidos"

[ -d "$SRC" ] || { echo "Can't find the BlidOS files on the install media ($SRC)."; exit 1; }
mkdir -p "$DEST"
for f in "$SRC"/*; do
    case "$(basename "$f")" in cmdline.txt) continue ;; esac
    echo "Copying $(basename "$f")…"
    cp -a "$f" "$DEST/"
done
# Android keeps apps and settings here.
mkdir -p "$DEST/data"
chmod 0771 "$DEST/data"
sync
echo "BlidOS files copied to $DEST"
