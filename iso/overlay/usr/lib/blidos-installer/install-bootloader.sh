#!/bin/bash
# Installs GRUB and writes a boot menu with BlidOS plus any other OS found (e.g. Windows).
set -euo pipefail
ROOT="$1"
CMDLINE=$(cat /run/live/medium/blidos/cmdline.txt)

ROOTDEV=$(findmnt -no SOURCE --target "$ROOT")
UUID=$(blkid -s UUID -o value "$ROOTDEV")
DISK=/dev/$(lsblk -no PKNAME "$ROOTDEV" | head -n1)
echo "BlidOS partition: $ROOTDEV (UUID $UUID) on $DISK"

mkdir -p "$ROOT/boot/grub"
if [ -d /sys/firmware/efi ]; then
    ESP="$ROOT/boot/efi"
    mountpoint -q "$ESP" || { echo "No EFI system partition is mounted at /boot/efi."; exit 1; }
    grub-install --target=x86_64-efi --efi-directory="$ESP" --boot-directory="$ROOT/boot" \
        --bootloader-id=BlidOS --recheck
    # Some PCs ignore boot entries and only start EFI/BOOT/BOOTX64.EFI. Use it only if nothing else owns it.
    if [ ! -e "$ESP/EFI/BOOT/BOOTX64.EFI" ]; then
        mkdir -p "$ESP/EFI/BOOT"
        cp "$ESP/EFI/BlidOS/grubx64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI"
    fi
    FIRMWARE=uefi
else
    grub-install --target=i386-pc --boot-directory="$ROOT/boot" --recheck "$DISK"
    FIRMWARE=bios
fi

CFG="$ROOT/boot/grub/grub.cfg"
cat > "$CFG" <<CFG
set timeout=5
set default=0
insmod part_gpt
insmod part_msdos
insmod ext2
insmod all_video
if loadfont unicode; then
    set gfxmode=auto
    insmod gfxterm
    terminal_output gfxterm
fi
set menu_color_normal=white/black
set menu_color_highlight=black/light-cyan

menuentry "BlidOS" {
    search --no-floppy --fs-uuid --set=root $UUID
    linux /blidos/kernel $CMDLINE SRC=/blidos quiet
    initrd /blidos/initrd.img
}
menuentry "BlidOS (safe graphics)" {
    search --no-floppy --fs-uuid --set=root $UUID
    linux /blidos/kernel $CMDLINE SRC=/blidos nomodeset HWACCEL=0
    initrd /blidos/initrd.img
}
CFG

# Add other operating systems so dual-boot keeps working.
os-prober 2>/dev/null | while IFS=: read -r dev label _ kind; do
    case "$kind" in
        efi)
            part=${dev%@*}; path=${dev#*@}
            u=$(blkid -s UUID -o value "$part") || continue
            printf 'menuentry "%s" {\n    insmod fat\n    insmod chain\n    search --no-floppy --fs-uuid --set=root %s\n    chainloader %s\n}\n' "$label" "$u" "$path" >> "$CFG"
            ;;
        chain)
            u=$(blkid -s UUID -o value "$dev") || continue
            printf 'menuentry "%s" {\n    insmod chain\n    search --no-floppy --fs-uuid --set=root %s\n    chainloader +1\n}\n' "$label" "$u" >> "$CFG"
            ;;
    esac
    echo "Added boot entry: $label"
done

if [ "$FIRMWARE" = uefi ]; then
    printf 'menuentry "UEFI firmware settings" {\n    fwsetup\n}\n' >> "$CFG"
fi
# Keep the installer log on the BlidOS partition for troubleshooting.
for log in /root/.cache/calamares/session.log /root/.cache/Calamares/session.log; do
    [ -f "$log" ] && cp "$log" "$ROOT/blidos/installer.log" && break
done
sync
echo "Boot menu written to $CFG"
