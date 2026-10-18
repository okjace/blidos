#!/bin/bash
# Builds the BlidOS installer ISO. Runs inside the Debian "builder" chroot with this folder at /work:
#   WORK=$HOME/blidos-iso ./tools/chroot.sh builder /work/build-iso.sh
set -euo pipefail

VERSION=0.1.0
W=/work
BLISS=$W/work/bliss            # unpacked Bliss OS ISO (kernel, initrd.img, efs/system.img)
APK=$W/work/BlidOS.apk
OUT=$W/out
ISO=$OUT/iso
LABEL="u:object_r:system_file:s0"

step() { echo; echo "==> $*"; }

# SKIP_SYSTEM=1 reuses the system.efs from the last build (it takes the longest).
if [ "${SKIP_SYSTEM:-0}" = 1 ] && [ -f "$ISO/blidos/system.efs" ]; then
    rm -rf "$ISO/live" "$ISO/boot" "$ISO/.disk"
else
    rm -rf "$ISO"
fi
mkdir -p "$ISO/blidos" "$ISO/live" "$ISO/boot/grub" "$ISO/.disk"

if [ "${SKIP_SYSTEM:-0}" != 1 ] || [ ! -f "$ISO/blidos/system.efs" ]; then
step "Adding BlidOS to the Android system image"
IMG=$W/work/system.img
cp --sparse=always "$BLISS/efs/system.img" "$IMG"
printf '%s\0' "$LABEL" > /tmp/selinux-label
debugfs -w -f - "$IMG" <<EOF
mkdir /system/priv-app/BlidOS
sif /system/priv-app/BlidOS mode 040755
sif /system/priv-app/BlidOS uid 0
sif /system/priv-app/BlidOS gid 0
ea_set -f /tmp/selinux-label /system/priv-app/BlidOS security.selinux
write $APK /system/priv-app/BlidOS/BlidOS.apk
sif /system/priv-app/BlidOS/BlidOS.apk mode 0100644
sif /system/priv-app/BlidOS/BlidOS.apk uid 0
sif /system/priv-app/BlidOS/BlidOS.apk gid 0
ea_set -f /tmp/selinux-label /system/priv-app/BlidOS/BlidOS.apk security.selinux
EOF
# Privileged permissions, hidden-API access, and room for one Android user per profile.
PAYLOAD=$W/payload
debugfs -R "cat /system/build.prop" "$IMG" > /tmp/build.prop
cat >> /tmp/build.prop <<'PROPS'
# BlidOS: one Android user per profile, and BlidOS's own setup instead of the tablet wizard.
fw.max_users=8
fw.show_multiuserui=1
ro.setupwizard.mode=DISABLED
PROPS
add_file() { # <local file> <path in image>
    cat <<CMDS
rm $2
write $1 $2
sif $2 mode 0100644
sif $2 uid 0
sif $2 gid 0
ea_set -f /tmp/selinux-label $2 security.selinux
CMDS
}
{
    add_file $PAYLOAD/privapp-permissions-blidos.xml /system/etc/permissions/privapp-permissions-blidos.xml
    add_file $PAYLOAD/blidos-sysconfig.xml /system/etc/sysconfig/blidos.xml
    add_file /tmp/build.prop /system/build.prop
    # BlidOS has its own setup screen, so the tablet setup wizard goes.
    echo "rm /system/system_ext/priv-app/SetupWizard/SetupWizard.apk"
    echo "rmdir /system/system_ext/priv-app/SetupWizard"
} | debugfs -w -f - "$IMG" 2>&1 | grep -vE "^debugfs( |:)" || true
debugfs -R "ls /system/system_ext/priv-app" "$IMG" | grep -c SetupWizard && { echo "SetupWizard still present"; exit 1; } || true
debugfs -R "cat /system/build.prop" "$IMG" | tail -4
debugfs -R "ls -l /system/priv-app/BlidOS" "$IMG"
debugfs -R "ea_list /system/priv-app/BlidOS/BlidOS.apk" "$IMG"
e2fsck -fn "$IMG"

step "Packing system.efs"
rm -rf $W/work/efsroot && mkdir $W/work/efsroot
mv "$IMG" $W/work/efsroot/system.img
cp "$BLISS/efs/system_image_info.txt" $W/work/efsroot/
mkfs.erofs -zlz4hc "$ISO/blidos/system.efs" $W/work/efsroot
rm -rf $W/work/efsroot
fi

step "Copying the Android kernel and initrd"
cp "$BLISS/kernel" "$BLISS/initrd.img" "$ISO/blidos/"
echo "root=/dev/ram0" > "$ISO/blidos/cmdline.txt"

step "Packing the graphical installer"
cp "$W/live/boot/vmlinuz-"* "$ISO/live/vmlinuz"
cp "$W/live/boot/initrd.img-"* "$ISO/live/initrd.img"
mksquashfs "$W/live" "$ISO/live/filesystem.squashfs" -comp xz -noappend -no-progress \
    -e boot -e root/apt.log -e var/cache/apt/archives -e var/lib/apt/lists

step "Writing the boot menu"
echo "BlidOS $VERSION x86_64" > "$ISO/.disk/info"
cat > "$ISO/boot/grub/grub.cfg" <<'EOF'
set timeout=10
set default=0
insmod all_video
if loadfont unicode; then
    set gfxmode=auto
    insmod gfxterm
    terminal_output gfxterm
fi
set menu_color_normal=white/black
set menu_color_highlight=black/light-cyan
search --no-floppy --set=root --file /blidos/kernel

menuentry "Install BlidOS (graphical installer)" {
    linux /live/vmlinuz boot=live quiet
    initrd /live/initrd.img
}
menuentry "Install BlidOS (safe graphics)" {
    linux /live/vmlinuz boot=live nomodeset quiet
    initrd /live/initrd.img
}
menuentry "Try BlidOS without installing" {
    linux /blidos/kernel root=/dev/ram0 SRC=/blidos quiet
    initrd /blidos/initrd.img
}
menuentry "Try BlidOS (safe graphics)" {
    linux /blidos/kernel root=/dev/ram0 SRC=/blidos nomodeset HWACCEL=0 quiet
    initrd /blidos/initrd.img
}
if [ "$grub_platform" = "efi" ]; then
    menuentry "UEFI firmware settings" {
        fwsetup
    }
fi
EOF

step "Building the ISO (BIOS + UEFI)"
NAME="BlidOS-$VERSION-x86_64.iso"
grub-mkrescue -o "$OUT/$NAME" "$ISO" -- -volid BLIDOS
(cd "$OUT" && sha256sum "$NAME" > "$NAME.sha256")
ls -lh "$OUT/$NAME"
