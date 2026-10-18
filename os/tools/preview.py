#!/usr/bin/env python3
"""Renders BlidOS screens to PNG with sample data, no system needed.

usage: QT_QPA_PLATFORM=offscreen PYTHONPATH=os python3 os/tools/preview.py shell|greeter out.png [page.qml]
"""
import json
import os
import sys

from PySide6.QtCore import QObject, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from blidos.app import IconProvider

SAMPLE = {
    "whoami": {"role": "owner", "profile": {"user": "profile1", "name": "Alex", "color": 0, "owner": True, "kids": False, "allowed": [], "hasPin": True}},
    "profiles": [
        {"user": "profile1", "name": "Alex", "color": 0, "owner": True, "kids": False, "allowed": [], "hasPin": True},
        {"user": "profile2", "name": "Sam", "color": 1, "owner": False, "kids": False, "allowed": [], "hasPin": False},
        {"user": "profile3", "name": "Mia", "color": 2, "owner": False, "kids": True, "allowed": [], "hasPin": False},
    ],
    "setupState": {"done": True, "profiles": 3},
    "androidRunning": True,
    "apps": [
        {"kind": "android", "id": "com.google.android.youtube.tv", "label": "YouTube", "icon": "", "tv": True},
        {"kind": "android", "id": "com.netflix.ninja", "label": "Netflix", "icon": "", "tv": True},
        {"kind": "android", "id": "com.spotify.tv.android", "label": "Spotify", "icon": "", "tv": True},
        {"kind": "linux", "id": "org.kde.kodi", "label": "Kodi", "icon": "", "exec": "kodi"},
    ],
    "connection": "Connected to HomeWiFi",
    "wifiEnabled": True,
    "wifiNetworks": [
        {"ssid": "HomeWiFi", "signal": 82, "secure": True, "enterprise": False, "active": True},
        {"ssid": "Neighbor 5G", "signal": 44, "secure": True, "enterprise": False, "active": False},
        {"ssid": "Cafe", "signal": 25, "secure": False, "enterprise": False, "active": False},
    ],
    "bluetooth": {"available": True, "on": True},
    "bluetoothDevices": [{"address": "AA:BB:CC:DD:EE:FF", "name": "TV Remote", "paired": True, "connected": True}],
    "volume": {"level": 45, "muted": False},
    "audioOutputs": [{"id": 40, "name": "HDMI / DisplayPort", "default": True}, {"id": 41, "name": "Speakers", "default": False}],
    "displays": [{"name": "HDMI-A-1", "description": "Living room TV", "scale": 1.0,
                  "modes": [{"label": "3840×2160 @ 60 Hz", "width": 3840, "height": 2160, "refresh": 60, "current": False},
                            {"label": "1920×1080 @ 60 Hz", "width": 1920, "height": 1080, "refresh": 60, "current": True}]}],
    "drivers": [{"id": "nvidia", "name": "NVIDIA graphics driver", "device": "GeForce RTX 3060", "installed": False}],
    "job": {"running": False, "ok": None, "log": []},
    "checkUpdates": {"current": "0.3.0", "online": True, "system": ["firefox-esr", "libssl3t64", "linux-image-amd64", "mesa-vulkan-drivers", "waydroid"],
                     "blidos": {"path": "/run/blidos/media/sdb1/blidos_0.3.1_all.deb", "version": "0.3.1", "where": "SANDISK"}},
    "debFiles": [{"path": "/run/blidos/media/sdb1/2017-wifi-dri.deb", "file": "2017-wifi-dri.deb", "where": "SANDISK", "size": 2483000},
                 {"path": "/home/profile1/Downloads/steam_latest.deb", "file": "steam_latest.deb", "where": "Downloads (Jace)", "size": 4120000}],
    "version": "0.2.0", "ipAddress": "192.168.1.20", "storage": {"total": 500e9, "free": 380e9},
    "timezone": "America/New_York", "timezones": ["America/New_York", "Europe/London"], "gsfId": "3A1B2C4D5E6F7081",
    "hasTerminal": True,
    "androidGraphics": "auto",
    "androidSetup": {"done": True, "progress": ""},
    "storeCategories": [{"id": "", "name": "Popular"}, {"id": "game", "name": "Games"}, {"id": "audiovideo", "name": "Video and music"},
                        {"id": "education", "name": "Learning"}, {"id": "graphics", "name": "Photos and art"}, {"id": "network", "name": "Internet"},
                        {"id": "office", "name": "Office"}, {"id": "utility", "name": "Tools"}],
    "storeInstalled": ["org.videolan.VLC"],
    "storeJob": {"running": False, "ok": None, "message": ""},
    "kidsAppChoices": {"android": [{"id": "com.google.android.youtube.tv", "label": "YouTube", "icon": ""}, {"id": "com.netflix.ninja", "label": "Netflix", "icon": ""}],
                       "linux": [{"id": "flatpak:net.sourceforge.ExtremeTuxRacer", "label": "Extreme Tux Racer", "icon": ""}, {"id": "linux:firefox-esr", "label": "Firefox ESR", "icon": ""}]},
    "controllers": [{"name": "Xbox Wireless Controller", "connection": "Bluetooth", "battery": 80},
                    {"name": "Sony Interactive Entertainment DualSense Wireless Controller", "connection": "USB", "battery": None}],
}
if os.environ.get("PREVIEW_LIVE_STORE"):  # real Flathub results, to check the parsing
    from blidos.system import store_browse
    SAMPLE["storeBrowse"] = store_browse("")


class FakeBackend(QObject):
    finished = Signal(int, bool, str)

    @Slot(int, str, str)
    def call(self, token, name, args):
        value = SAMPLE.get(name, None)
        QTimer.singleShot(10, lambda: self.finished.emit(token, True, json.dumps(value)))


def main():
    mode, out = sys.argv[1], sys.argv[2]
    page = sys.argv[3] if len(sys.argv) > 3 else None
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()
    engine.warnings.connect(lambda ws: [print("QML:", w.toString(), file=sys.stderr) for w in ws])
    engine.addImageProvider("icon", IconProvider())
    backend = FakeBackend()
    engine.rootContext().setContextProperty("backend", backend)
    engine.rootContext().setContextProperty("blidosMode", mode)
    qml = os.path.join(os.path.dirname(__file__), "..", "blidos", "qml")
    engine.addImportPath(qml)
    engine.load(QUrl.fromLocalFile(os.path.join(qml, "Shell.qml" if mode == "shell" else "Greeter.qml")))
    if not engine.rootObjects():
        sys.exit("QML failed to load")
    win = engine.rootObjects()[0]
    win.setProperty("visibility", 2)  # windowed, so the offscreen size is used
    win.setWidth(1920)
    win.setHeight(1080)
    if page:
        QTimer.singleShot(400, lambda: win.push(page, json.loads(os.environ.get("PREVIEW_PROPS", "{}"))))

    def dump(item, depth=0):
        if depth > 5:
            return
        print("  " * depth, item.metaObject().className(), item.objectName(), int(item.x()), int(item.y()),
              int(item.width()), int(item.height()), "visible" if item.isVisible() else "hidden", file=sys.stderr)
        for c in item.childItems():
            dump(c, depth + 1)

    def shoot():
        if os.environ.get("BLIDOS_DUMP"):
            dump(win.contentItem())
        win.grabWindow().save(out)
        app.quit()

    QTimer.singleShot(int(os.environ.get("PREVIEW_DELAY_MS", "1500")), shoot)
    app.exec()


if __name__ == "__main__":
    main()
