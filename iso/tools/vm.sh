#!/bin/bash
# Start the test VM headless. usage: vm.sh [extra qemu args...]
cd "$(dirname "$0")/../test"
rm -f /tmp/claude-1000/blidos-qmp.sock
export QEMU_MODULE_DIR="$(cd ../qemu-mods/modules && pwd)"
exec qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 3072 -machine q35 \
 -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
 -drive if=pflash,format=raw,file=vars.fd \
 -drive file=disk.img,format=raw,if=none,id=d0 -device nvme,drive=d0,serial=blidos0 \
 -vga none -device virtio-vga -display none -device qemu-xhci -device usb-tablet -device usb-kbd \
 -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
 -qmp unix:/tmp/claude-1000/blidos-qmp.sock,server,nowait "$@"
