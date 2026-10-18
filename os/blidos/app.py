"""Starts the BlidOS shell (home screen) or greeter (profile picker and first-boot setup)."""
import json
import os
import subprocess
import sys
import threading
import traceback

from PySide6.QtCore import QObject, QSize, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication, QIcon, QPixmap
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider

from . import system
from .greetd import Greetd, LoginError

SESSION_COMMAND = ["/usr/bin/blidos-session"]

# Android's own system screens; BlidOS has its own versions or they aren't useful on a TV.
ANDROID_HIDDEN = {"com.android.settings", "com.android.vending", "com.android.documentsui",
                  "com.android.inputmethod.latin", "org.lineageos.jelly", "com.android.launcher3"}


def _calls(mode):
    """Everything the QML side may ask for, by name."""
    d = system.daemon
    calls = {
        # profiles
        "profiles": lambda: d("list")["profiles"],
        "whoami": lambda: d("whoami"),
        "createProfile": lambda name, pin=None, kids=False: d("create", name=name, pin=pin or None, kids=kids)["profile"],
        "updateProfile": lambda user, fields: d("update", user=user, **fields)["profile"],
        "setPin": lambda user, pin=None: d("set-pin", user=user, pin=pin or None),
        "deleteProfile": lambda user: d("delete", user=user),
        "setupState": lambda: d("setup-state"),
        "finishSetup": lambda: d("finish-setup"),
        # network
        "wifiEnabled": system.wifi_enabled,
        "setWifiEnabled": system.set_wifi_enabled,
        "wifiNetworks": system.wifi_networks,
        "wifiConnect": lambda ssid, password="": dict(zip(("ok", "message"), system.wifi_connect(ssid, password))),
        "wifiForget": system.wifi_forget,
        "connection": system.connection_summary,
        "ipAddress": system.ip_address,
        "restartComputer": system.restart,
        "shutDownComputer": system.shut_down,
        # bluetooth
        "bluetooth": lambda: {"available": system.bluetooth_available(), "on": system.bluetooth_on()},
        "setBluetoothOn": system.set_bluetooth_on,
        "bluetoothDevices": system.bluetooth_devices,
        "bluetoothScan": system.bluetooth_scan,
        "bluetoothPair": system.bluetooth_pair,
        "bluetoothConnect": system.bluetooth_connect,
        "bluetoothForget": system.bluetooth_forget,
    }
    if mode == "shell":
        calls.update({
            "apps": _apps,
            "launch": _launch,
            "androidRunning": system.android_running,
            "applyKids": lambda: d("apply-kids"),
            "androidInstalled": _android_installed,
            "restartAndroid": system.restart_android,
            "androidGraphics": lambda mode="": d("android-graphics", **({"mode": mode} if mode else {}))["mode"],
            "androidReport": system.save_android_report,
            "androidTv": lambda on=None: d("android-tv", **({} if on is None else {"on": on}))["on"],
            "androidStarted": lambda: d("android-started"),
            "androidSetup": lambda: d("android-setup"),
            "androidStatus": lambda: d("android-status"),
            "storeCategories": lambda: [{"id": k, "name": v} for k, v in system.STORE_CATEGORIES.items()],
            "storeBrowse": system.store_browse,
            "storeSearch": system.store_search,
            "storeInstalled": system.store_installed,
            "storeInstall": system.store_install,
            "storeJob": system.store_job,
            "storeRemove": system.store_remove,
            "storeOpen": system.store_open,
            "switchMode": system.switch_mode,
            "controllers": system.controllers,
            "controllerRemote": system.controller_remote,
            "kidsAppChoices": system.kids_app_choices,
            "openAndroidSettings": lambda: d("android-launch", package="com.android.settings"),
            "gsfId": lambda: d("gsf-id")["id"],
            "volume": system.volume,
            "setVolume": system.set_volume,
            "toggleMute": system.toggle_mute,
            "audioOutputs": system.audio_outputs,
            "setAudioOutput": system.set_audio_output,
            "displays": system.displays,
            "setDisplayMode": system.set_display_mode,
            "setDisplayScale": system.set_display_scale,
            "timezone": system.timezone,
            "timezones": system.timezones,
            "setTimezone": system.set_timezone,
            "drivers": lambda: d("drivers")["drivers"],
            "installDriver": lambda id: d("install-driver", id=id),
            "updateSystem": lambda: d("update-system"),
            "checkUpdates": lambda: d("check-updates"),
            "installUpdates": lambda blidos="": d("install-updates", blidos=blidos),
            "debFiles": lambda: d("deb-files")["files"],
            "debDetails": lambda path: d("deb-details", path=path),
            "installDeb": lambda key: d("install-deb", key=key),
            "installApk": system.install_apk,
            "job": lambda name: _job(name),
            "storage": system.storage,
            "version": system.os_version,
            "hasTerminal": system.has_terminal,
            "openTerminal": system.open_terminal,
            "switchProfile": system.switch_profile,
            "restart": system.restart,
            "shutDown": system.shut_down,
        })
    return calls


def _apps():
    """Home screen apps: Android (including Android TV) apps, then Linux apps."""
    labels = system.android_labels()
    apps = []
    try:
        for a in system.daemon("android-apps")["apps"]:
            pkg = a["package"]
            if pkg in ANDROID_HIDDEN:
                continue
            apps.append({"kind": "android", "id": pkg, "label": labels.get(pkg) or pkg.split(".")[-1].title(),
                         "icon": system.android_icon(pkg), "tv": a["tv"]})
    except system.DaemonError:
        pass  # Android isn't running yet
    apps.sort(key=lambda a: (not a["tv"], a["label"].lower()))
    for a in system.linux_apps():
        apps.append({"kind": "linux", "id": a["id"], "source": a["source"], "label": a["label"],
                     "icon": "image://icon/" + a["icon"] if a["icon"] else "", "exec": a["exec"]})
    return apps


def _job(name):
    j = system.daemon("job", name=name)
    return {"running": j["running"], "ok": j["succeeded"], "log": j["log"]}


def _android_installed():
    labels = system.android_labels()
    return [{"package": p, "label": labels.get(p) or p} for p in system.daemon("android-installed")["packages"]]


def _launch(kind, id, exec_line=""):
    if kind == "android":
        system.wait_for_android()  # until Android has started, its window would only be black
        system.open_android_window()
        open(system.LAUNCH_MARKER, "w").close()
        system.daemon("android-launch", package=id)
        system.show_android()
    else:
        system.launch_linux(exec_line)


class Backend(QObject):
    """QML calls `call(token, name, argsJson)`; the answer arrives later as `finished(token, ok, json)`."""
    finished = Signal(int, bool, str)
    loggedIn = Signal()

    def __init__(self, mode):
        super().__init__()
        self.mode = mode
        self.calls = _calls(mode)
        if mode == "greeter":
            self.calls["login"] = self._login

    @Slot(int, str, str)
    def call(self, token, name, args_json):
        args = json.loads(args_json or "[]")

        def work():
            try:
                fn = self.calls[name]
                value = fn(*args) if isinstance(args, list) else fn(**args)
                self.finished.emit(token, True, json.dumps(value))
            except (system.DaemonError, LoginError, ValueError) as e:
                self.finished.emit(token, False, json.dumps(str(e)))
            except Exception as e:
                traceback.print_exc()
                self.finished.emit(token, False, json.dumps(f"Something went wrong ({e.__class__.__name__})"))

        threading.Thread(target=work, daemon=True).start()

    def _login(self, user, pin):
        Greetd().login(user, pin, SESSION_COMMAND)
        self.loggedIn.emit()
        return True

    @Slot(result=str)
    def mode_(self):
        return self.mode


class IconProvider(QQuickImageProvider):
    """`image://icon/<name>`: icons from the system icon theme (for Linux apps)."""

    def __init__(self):
        super().__init__(QQuickImageProvider.Pixmap)

    def requestPixmap(self, name, size, requested):
        icon = QIcon(name) if name.startswith("/") else QIcon.fromTheme(name)
        px = icon.pixmap(QSize(128, 128)) if not icon.isNull() else QPixmap(1, 1)
        if size is not None:
            size.setWidth(px.width())
            size.setHeight(px.height())
        return px


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "shell"
    if mode not in ("shell", "greeter"):
        sys.exit("usage: blidos [shell|greeter]")
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    QGuiApplication.setDesktopFileName("blidos")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("BlidOS")
    QIcon.setThemeName(os.environ.get("BLIDOS_ICON_THEME", "Adwaita"))

    backend = Backend(mode)
    if mode == "greeter":
        backend.loggedIn.connect(app.quit)
    engine = QQmlApplicationEngine()
    engine.addImageProvider("icon", IconProvider())
    engine.rootContext().setContextProperty("backend", backend)
    engine.rootContext().setContextProperty("blidosMode", mode)
    qml_dir = os.path.join(os.path.dirname(__file__), "qml")
    engine.addImportPath(qml_dir)
    engine.load(QUrl.fromLocalFile(os.path.join(qml_dir, "Shell.qml" if mode == "shell" else "Greeter.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    if mode == "shell":
        # The session showed a loading screen as its background until now; go back to plain.
        QTimer.singleShot(2000, lambda: subprocess.Popen(
            ["swaymsg", "output * bg #0F1424 solid_color"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    sys.exit(app.exec())
