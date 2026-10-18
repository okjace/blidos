if [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ]; then
    startx -- -nolisten tcp vt1 > /tmp/xsession.log 2>&1
    echo "The graphical installer couldn't start. See /tmp/xsession.log."
    echo "Try the 'safe graphics' option in the boot menu."
fi
