# Live USB, "Install BlidOS": run the graphical installer full screen.
if [ "$(tty)" = /dev/tty1 ] && grep -qw blidos.install /proc/cmdline; then
    . /usr/lib/blidos/gpu-env
    cage -s -d -- /usr/lib/blidos-installer/run-installer > /tmp/installer.log 2>&1
    echo "The installer closed. Type 'reboot' to restart."
fi
