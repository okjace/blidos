#!/bin/bash
# Builds the BlidOS ISO: Debian 13 + the BlidOS interface + Android apps (Waydroid).
# Runs without root (user namespaces). Usage:  os/build-os.sh [packages|system|iso|all]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OS=$REPO/os
TOOLS=$REPO/iso/tools
WORK=${WORK:-$HOME/blidos-os-build}
ROOT=$WORK/root
DEBIAN_ROOTFS=${DEBIAN_ROOTFS:-$HOME/blidos-iso/dl/debian-rootfs.tar.xz}
WAYDROID_IMAGES=${WAYDROID_IMAGES:-$HOME/blidos-os-dl/waydroid}
BUILDER=${BUILDER:-$HOME/blidos-iso/builder}
VERSION=$(cat "$OS/rootfs/etc/blidos-version")
STEP=${1:-all}

in_root() { "$TOOLS/chroot.sh" "$ROOT" bash -euc "$1"; }
as_root() { "$TOOLS/nsenter-root.sh" bash -euc "$1"; }
step() { echo; echo "==> $*"; }

PACKAGES=(
    # Kernel, firmware and drivers
    linux-image-amd64 linux-headers-amd64 firmware-linux firmware-linux-nonfree firmware-misc-nonfree
    firmware-amd-graphics firmware-intel-graphics firmware-iwlwifi firmware-realtek firmware-atheros
    firmware-brcm80211 firmware-mediatek firmware-sof-signed intel-microcode amd64-microcode
    # Broadcom Wi-Fi that only works with Broadcom's own driver (wl), e.g. MacBook Air 2013-2017 (BCM4360)
    broadcom-sta-dkms dkms gcc make
    initramfs-tools systemd-sysv dbus-user-session polkitd libpam-modules locales
    # Network, Bluetooth, sound
    network-manager wpasupplicant iw rfkill bluez pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils
    # Graphics and the BlidOS interface
    libgl1-mesa-dri libegl-mesa0 libglx-mesa0 mesa-vulkan-drivers va-driver-all
    greetd cage sway swayidle xwayland wlr-randr foot
    python3 python3-pyside6.qtcore python3-pyside6.qtgui python3-pyside6.qtqml python3-pyside6.qtquick
    qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-templates qml6-module-qtquick-window
    qml6-module-qtquick-layouts qml6-module-qtqml-workerscript qt6-wayland qt6-svg-plugins
    fonts-noto-core adwaita-icon-theme
    # Android apps
    waydroid lxc
    # Game controllers: the controller-as-remote helper, Steam controller and Valve device access
    python3-evdev steam-devices
    # App Store (Flatpak apps from Flathub)
    flatpak xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    # Desktop mode: KDE Plasma
    kde-plasma-desktop plasma-nm plasma-pa bluedevil kscreen powerdevil systemsettings konsole
    plasma-discover plasma-discover-backend-flatpak xdg-desktop-portal-kde breeze firefox-esr
    # Booting and installing
    plymouth
    grub-efi-amd64-bin grub-pc-bin grub2-common os-prober efibootmgr dosfstools e2fsprogs ntfs-3g btrfs-progs xfsprogs
    live-boot calamares squashfs-tools rsync
    # Tools
    pciutils usbutils sqlite3 ca-certificates curl unzip less nano
)

if [ "$STEP" = packages ] || [ "$STEP" = all ]; then
    step "Debian base system"
    as_root "rm -rf '$ROOT' && mkdir -p '$ROOT' && tar -xJf '$DEBIAN_ROOTFS' -C '$ROOT' --numeric-owner"
    in_root "
        sed -i 's/ main contrib\$/ main contrib non-free non-free-firmware/' /etc/apt/sources.list
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends curl ca-certificates gnupg >/dev/null
        curl -fsSL https://repo.waydro.id/waydroid.gpg -o /usr/share/keyrings/waydroid.gpg
        echo 'deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ trixie main' > /etc/apt/sources.list.d/waydroid.list
        apt-get update -qq
    "
    step "Installing packages (kernel, firmware, interface, Android)"
    in_root "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${PACKAGES[*]} > /tmp/apt.log 2>&1 || { tail -30 /tmp/apt.log; exit 1; }"
fi

if [ "$STEP" = system ] || [ "$STEP" = all ]; then
    step "Packages added since the base system was built"
    in_root "
        # Packages added to the list since the base system was built.
        missing=\$(for p in ${PACKAGES[*]}; do dpkg -s \$p >/dev/null 2>&1 || echo \$p; done)
        if [ -n \"\$missing\" ]; then
            echo \"Installing: \$missing\"
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \$missing > /tmp/apt.log 2>&1 || { tail -30 /tmp/apt.log; exit 1; }
        fi
    "
    step "Building the BlidOS package (blidos_${VERSION}_all.deb)"
    # BlidOS ships as one Debian package, so updates replace exactly its files and nothing else.
    mkdir -p "$WORK/out"
    python3 "$OS/tools/make-deb.py" "$VERSION" "$WORK/out/blidos_${VERSION}_all.deb" >/dev/null
    as_root "
        cp '$WORK/out/blidos_${VERSION}_all.deb' '$ROOT/var/tmp/blidos.deb'
        cp -a '$OS/installer/.' '$ROOT/'
        chown -R 0:0 '$ROOT/etc/calamares' '$ROOT/root'
    "
    in_root "DEBIAN_FRONTEND=noninteractive dpkg -i /var/tmp/blidos.deb && rm /var/tmp/blidos.deb"
    step "Android system images"
    # Public ISOs don't include Android: its image contains Google's apps, which can't be
    # redistributed, so BlidOS downloads it from Waydroid on first start. BUNDLE_ANDROID=1 puts it
    # in the ISO for offline installs; don't publish an ISO built that way.
    if [ "${BUNDLE_ANDROID:-0}" = 1 ]; then
        as_root "
            mkdir -p '$ROOT/usr/share/waydroid-extra/images'
            cd '$ROOT/usr/share/waydroid-extra/images'
            [ -e system.img ] || unzip -o -q '$WAYDROID_IMAGES/system.zip'
            [ -e vendor.img ] || unzip -o -q '$WAYDROID_IMAGES/vendor.zip'
        "
        mkdir -p "$WORK/out" && touch "$WORK/out/android-bundled-$VERSION"  # os/tools/release.sh refuses these
    else
        as_root "rm -rf '$ROOT/usr/share/waydroid-extra/images'"
        rm -f "$WORK/out/android-bundled-$VERSION"
    fi
    step "System settings"
    in_root "
        echo blidos > /etc/hostname
        printf '127.0.0.1 localhost\n127.0.1.1 blidos\n' > /etc/hosts
        sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen >/dev/null
        echo 'LANG=en_US.UTF-8' > /etc/default/locale
        systemctl mask systemd-networkd-wait-online.service >/dev/null 2>&1 || true
        : > /etc/machine-id
        ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
        # Build the Broadcom wl driver for the installed kernel (needs no internet on the target computer).
        for k in \$(ls /lib/modules); do
            dkms autoinstall -k \$k >/dev/null 2>&1 || true
            find /lib/modules/\$k -name 'wl.ko*' | grep -q . || { echo \"Broadcom wl driver did not build for \$k\"; exit 1; }
        done
        # Flathub, the app store's source.
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        # Linux apps that come with BlidOS (desktop-mode tools) stay off the TV home screen.
        mkdir -p /usr/share/blidos
        ls /usr/share/applications | sed -n 's/\.desktop\$//p' | grep -vx firefox-esr > /usr/share/blidos/base-apps.txt
        update-initramfs -u -k all >/dev/null 2>&1
        apt-get clean
        rm -rf /var/lib/apt/lists/* /tmp/*
    "
fi

if [ "$STEP" = iso ] || [ "$STEP" = all ]; then
    step "Building the ISO"
    rm -rf "$WORK/iso" && mkdir -p "$WORK/iso/live" "$WORK/iso/boot/grub" "$WORK/out"
    cp "$OS/art/grub-background.svg" "$WORK/"
    WORK_IN_BUILDER=/work
    WORK="$WORK" "$TOOLS/chroot.sh" "$BUILDER" bash -euc "
        cd /work
        rsvg-convert -w 1920 -h 1080 grub-background.svg -o iso/boot/grub/background.png
        cp iso/boot/grub/background.png root/usr/share/blidos/grub-background.png 2>/dev/null || true
        cp root/boot/vmlinuz-* iso/live/vmlinuz
        cp root/boot/initrd.img-* iso/live/initrd.img
        mksquashfs root iso/live/filesystem.squashfs -comp xz -Xbcj x86 -noappend -no-progress -e boot/grub
        cat > iso/boot/grub/grub.cfg <<'CFG'
set timeout=10
set default=0
insmod all_video
insmod png
if loadfont unicode; then
    set gfxmode=auto
    insmod gfxterm
    terminal_output gfxterm
    background_image /boot/grub/background.png
fi
set menu_color_normal=white/black
set menu_color_highlight=black/light-cyan
search --no-floppy --set=root --file /live/vmlinuz

menuentry 'Try BlidOS' {
    linux /live/vmlinuz boot=live quiet splash loglevel=3 vt.global_cursor_default=0
    initrd /live/initrd.img
}
menuentry 'Install BlidOS' {
    linux /live/vmlinuz boot=live blidos.install quiet loglevel=3 vt.global_cursor_default=0
    initrd /live/initrd.img
}
menuentry 'Try BlidOS (safe graphics)' {
    linux /live/vmlinuz boot=live nomodeset quiet
    initrd /live/initrd.img
}
menuentry 'Install BlidOS (safe graphics)' {
    linux /live/vmlinuz boot=live blidos.install nomodeset quiet
    initrd /live/initrd.img
}
if [ \"\\\$grub_platform\" = efi ]; then
    menuentry 'UEFI firmware settings' { fwsetup }
fi
CFG
        echo 'BlidOS $VERSION' > iso/.disk-info 2>/dev/null || true
        # The update file rides along: a stick made from this ISO updates older BlidOS (Settings → Updates).
        mkdir -p iso/blidos-update && cp out/blidos_${VERSION}_all.deb iso/blidos-update/
        grub-mkrescue -o out/BlidOS-$VERSION-x86_64.iso iso -- -volid BLIDOS 2>&1 | tail -2
        cd out && sha256sum BlidOS-$VERSION-x86_64.iso > BlidOS-$VERSION-x86_64.iso.sha256
        ls -lh BlidOS-$VERSION-x86_64.iso
    "
fi
