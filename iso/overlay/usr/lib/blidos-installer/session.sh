#!/bin/bash
# Runs the installer full screen. If it is closed, asks what to do next.
xsetroot -solid "#0F1424"
while true; do
    calamares
    xmessage -center -title "BlidOS installer" \
        -buttons "Open installer again:0,Restart:1,Shut down:2" \
        "The BlidOS installer is closed. Remove the USB stick before restarting."
    case $? in
        1) systemctl -i reboot; exit ;;
        2) systemctl -i poweroff; exit ;;
    esac
done
