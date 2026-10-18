#!/bin/bash
# Enter a Debian root filesystem as fake root, with /proc, /dev, /sys and DNS ready.
# usage: chroot.sh <rootdir> [command...]
set -e
ROOT=$(realpath "$1"); shift
HERE=$(dirname "$(realpath "$0")")
exec "$HERE/nsenter-root.sh" bash -c '
  set -e
  R="$1"; shift
  mount --rbind /dev "$R/dev"
  mount -t proc proc "$R/proc"
  mount --rbind /sys "$R/sys" 2>/dev/null || true
  mount -t tmpfs tmpfs "$R/tmp"
  [ -e "$R/etc/resolv.conf" ] || [ -L "$R/etc/resolv.conf" ] && rm -f "$R/etc/resolv.conf"
  cp /etc/resolv.conf "$R/etc/resolv.conf"
  for d in /work; do [ -d "$R$d" ] && [ -n "$WORK" ] && mount --bind "$WORK" "$R$d"; done
  exec chroot "$R" /usr/bin/env -i HOME=/root TERM=xterm PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 "${@:-/bin/bash}"
' _ "$ROOT" "$@"
