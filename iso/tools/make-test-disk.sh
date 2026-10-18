#!/bin/bash
# Fresh 24 GB test disk: EFI partition with a fake Windows boot manager, a 4 GB "Other OS" partition, free space.
set -e
cd "$(dirname "$0")/../test"
rm -f disk.img && truncate -s 24G disk.img
printf 'label: gpt\nsize=300MiB, type=U, name="EFI system partition"\nsize=4GiB, type=L, name="Other OS"\n' | sfdisk -q disk.img
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd vars.fd
cd .. && WORK=$PWD ./tools/chroot.sh builder bash -c '
cd /work/test; export MTOOLS_SKIP_CHECK=1
mkfs.fat -F 32 -S 512 -s 1 -n ESP --offset 2048 disk.img $((300*1024)) >/dev/null
mmd -i disk.img@@1M ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot
mcopy -i disk.img@@1M /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi ::/EFI/Microsoft/Boot/bootmgfw.efi
echo fake > /tmp/BCD && mcopy -i disk.img@@1M /tmp/BCD ::/EFI/Microsoft/Boot/BCD
mke2fs -q -t ext4 -L OtherOS -E offset=$(( (2048 + 300*2048) * 512 )) disk.img 4G
fsck.fat -n --offset 2048 disk.img 2>&1 | tail -1 || true'
