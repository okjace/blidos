"""Talks to the rest of the system: blidosd, NetworkManager, BlueZ, PipeWire, the display and Android."""
import configparser
import glob
import json
import os
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.request

from .daemon import SOCKET


class DaemonError(Exception):
    pass


def daemon(op, **args):
    """One request to blidosd. Raises DaemonError with a readable message on failure."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(120)
    try:
        s.connect(SOCKET)
        s.sendall((json.dumps({"op": op, **args}) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
    except OSError as e:
        raise DaemonError(f"BlidOS service isn't running ({e})")
    finally:
        s.close()
    resp = json.loads(data or b'{"ok": false, "error": "No answer"}')
    if not resp.pop("ok", False):
        raise DaemonError(resp.get("error", "Something went wrong"))
    return resp


def run(cmd, timeout=30, input=None):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, input=input)
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 1, "", str(e))


def _nmcli_fields(line):
    # nmcli -t escapes ":" inside values as "\:"
    return [f.replace("\\:", ":") for f in re.split(r"(?<!\\):", line)]


# ---------- Wi-Fi (NetworkManager) ----------

def wifi_enabled():
    return run(["nmcli", "radio", "wifi"]).stdout.strip() == "enabled"


def set_wifi_enabled(on):
    run(["nmcli", "radio", "wifi", "on" if on else "off"])


def wifi_networks(rescan=False):
    out = run(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list",
               "--rescan", "yes" if rescan else "auto"], timeout=40).stdout
    nets = {}
    for line in out.splitlines():
        f = _nmcli_fields(line)
        if len(f) < 4 or not f[1]:
            continue
        net = {"ssid": f[1], "signal": int(f[2] or 0), "secure": f[3] not in ("", "--"),
               "enterprise": "802.1X" in f[3], "active": f[0] == "*"}
        if f[1] not in nets or net["active"] or net["signal"] > nets[f[1]]["signal"]:
            nets[f[1]] = net
    return sorted(nets.values(), key=lambda n: (not n["active"], -n["signal"]))


def wifi_connect(ssid, password):
    cmd = ["nmcli", "device", "wifi", "connect", ssid]
    if password:
        cmd += ["password", password]
    r = run(cmd, timeout=60)
    return r.returncode == 0, (r.stderr or r.stdout).strip()


def wifi_forget(ssid):
    run(["nmcli", "connection", "delete", "id", ssid])


def connection_summary():
    out = run(["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device"]).stdout
    for line in out.splitlines():
        f = _nmcli_fields(line)
        if len(f) >= 3 and f[1] == "connected":
            if f[0] == "ethernet":
                return "Using Ethernet"
            if f[0] == "wifi":
                return f"Connected to {f[2]}"
    return "Not connected"


def ip_address():
    out = run(["nmcli", "-t", "-f", "IP4.ADDRESS", "device", "show"]).stdout
    for line in out.splitlines():
        addr = line.split(":", 1)[-1].split("/")[0]
        if addr and not addr.startswith("127."):
            return addr
    return None


# ---------- Bluetooth (BlueZ) ----------

def _btctl(*args, timeout=20):
    return run(["bluetoothctl", *args], timeout=timeout)


def bluetooth_available():
    return "Controller" in _btctl("list").stdout


def bluetooth_on():
    return "Powered: yes" in _btctl("show").stdout


def set_bluetooth_on(on):
    run(["rfkill", "unblock", "bluetooth"])
    _btctl("power", "on" if on else "off")


def _devices(which=None):
    out = _btctl("devices", *([which] if which else [])).stdout
    devs = []
    for line in out.splitlines():
        m = re.match(r"Device ([0-9A-F:]{17}) (.*)", line.strip())
        if m:
            devs.append({"address": m.group(1), "name": m.group(2)})
    return devs


def bluetooth_devices():
    paired = {d["address"] for d in _devices("Paired")}
    connected = {d["address"] for d in _devices("Connected")}
    result = []
    for d in _devices():
        d["paired"] = d["address"] in paired
        d["connected"] = d["address"] in connected
        result.append(d)
    return sorted(result, key=lambda d: (not d["connected"], not d["paired"], d["name"].lower()))


def bluetooth_scan(seconds=12):
    _btctl("--timeout", str(seconds), "scan", "on", timeout=seconds + 5)


def bluetooth_pair(address):
    # Remotes, controllers, headphones and speakers pair without a code.
    r = _btctl("--agent", "NoInputNoOutput", "pair", address, timeout=40)
    ok = "Pairing successful" in r.stdout or "AlreadyExists" in r.stdout
    if ok:
        _btctl("trust", address)
        _btctl("connect", address, timeout=20)
    return ok


def bluetooth_connect(address):
    return "Connection successful" in _btctl("connect", address, timeout=20).stdout


def bluetooth_forget(address):
    _btctl("remove", address)


# ---------- Sound (PipeWire) ----------

def volume():
    out = run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]).stdout
    m = re.search(r"Volume: ([\d.]+)", out)
    return {"level": round(float(m.group(1)) * 100) if m else 0, "muted": "MUTED" in out}


def set_volume(percent):
    run(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", f"{max(0, min(100, percent))}%"])
    run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"])


def toggle_mute():
    run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])


def audio_outputs():
    out = run(["wpctl", "status"]).stdout
    sinks, in_sinks = [], False
    for line in out.splitlines():
        if "Sinks:" in line:
            in_sinks = True
            continue
        if in_sinks:
            m = re.match(r"\s*│?\s*(\*)?\s*(\d+)\.\s+(.+?)\s*(\[vol:.*)?$", line)
            if not m:
                if line.strip(" │") == "" or "Sources:" in line or ":" in line and "." not in line:
                    break
                continue
            sinks.append({"id": int(m.group(2)), "name": m.group(3), "default": bool(m.group(1))})
    return sinks


def set_audio_output(sink_id):
    run(["wpctl", "set-default", str(sink_id)])


# ---------- Display (wlroots) ----------

def displays():
    out = run(["wlr-randr", "--json"]).stdout
    try:
        outputs = json.loads(out)
    except ValueError:
        return []
    result = []
    for o in outputs:
        modes = []
        for m in o.get("modes", []):
            label = f'{m["width"]}×{m["height"]} @ {round(m["refresh"])} Hz'
            modes.append({"label": label, "width": m["width"], "height": m["height"],
                          "refresh": m["refresh"], "current": m.get("current", False)})
        result.append({"name": o["name"], "description": o.get("description") or o["name"],
                       "scale": o.get("scale", 1.0), "modes": modes})
    return result


def set_display_mode(output, width, height, refresh):
    run(["swaymsg", f"output {output} mode {width}x{height}@{refresh:.3f}Hz"])
    _save_display(output, f"mode {width}x{height}@{refresh:.3f}Hz")


def set_display_scale(output, scale):
    run(["swaymsg", f"output {output} scale {scale}"])
    _save_display(output, f"scale {scale}")


def _save_display(output, setting):
    """Remembered per profile and re-applied by sway at login."""
    path = os.path.expanduser("~/.config/blidos/outputs.conf")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = [l for l in open(path).read().splitlines()] if os.path.exists(path) else []
    key = f"output {output} {setting.split()[0]} "
    lines = [l for l in lines if not l.startswith(key)] + [f"output {output} {setting}"]
    open(path, "w").write("\n".join(lines) + "\n")


# ---------- Time ----------

def timezones():
    return run(["timedatectl", "list-timezones"]).stdout.split()


def timezone():
    return run(["timedatectl", "show", "-p", "Timezone", "--value"]).stdout.strip()


def set_timezone(zone):
    return run(["timedatectl", "set-timezone", zone]).returncode == 0


# ---------- Apps ----------

ANDROID_ICONS = "~/.local/share/waydroid/data/icons"
HIDDEN_LINUX_APPS = {"blidos", "foot", "footclient", "foot-server", "org.codeberg.dnkl.foot",
                     "org.codeberg.dnkl.footclient", "org.codeberg.dnkl.foot-server", "nm-connection-editor",
                     "Waydroid", "calamares", "install-debian", "debian-uxterm", "debian-xterm",
                     "org.pulseaudio.pavucontrol", "bluetooth-sendto", "blidos-tv-mode"}


def android_labels():
    """Names Waydroid exported for Android apps (from their .desktop entries)."""
    labels = {}
    for path in glob.glob(os.path.expanduser("~/.local/share/applications/waydroid.*.desktop")):
        cp = configparser.ConfigParser(interpolation=None)
        try:
            cp.read(path)
            pkg = os.path.basename(path)[len("waydroid."):-len(".desktop")]
            labels[pkg] = cp.get("Desktop Entry", "Name", fallback=pkg)
        except configparser.Error:
            pass
    return labels


def android_icon(pkg):
    path = os.path.join(os.path.expanduser(ANDROID_ICONS), pkg + ".png")
    return "file://" + path if os.path.exists(path) else ""


ICON_DIRS = ["~/.local/share/flatpak/exports/share/icons", "/var/lib/flatpak/exports/share/icons",
             "~/.local/share/icons", "/usr/share/icons"]
ICON_SIZES = ["scalable", "512x512", "256x256", "192x192", "128x128", "96x96", "64x64", "48x48"]


def _icon_file(name):
    """An app icon's file, found directly: the icon theme's list is only read at startup, so it
    misses apps installed since."""
    if not name or name.startswith("/"):
        return name
    for d in ICON_DIRS:
        for size in ICON_SIZES:
            for ext in ("svg", "png"):
                path = os.path.join(os.path.expanduser(d), "hicolor", size, "apps", f"{name}.{ext}")
                if os.path.exists(path):
                    return path
    for ext in ("svg", "png", "xpm"):
        if os.path.exists(f"/usr/share/pixmaps/{name}.{ext}"):
            return f"/usr/share/pixmaps/{name}.{ext}"
    return name


def _base_apps():
    """Linux apps that come with BlidOS, mostly desktop-mode tools; they stay off the TV home screen."""
    try:
        with open("/usr/share/blidos/base-apps.txt") as f:
            return set(f.read().split())
    except OSError:
        return set()


def linux_apps():
    """Linux apps for the home screen: App Store (Flatpak) apps and apps you installed yourself."""
    seen, apps = set(), []
    base = _base_apps()
    dirs = [(os.path.expanduser("~/.local/share/flatpak/exports/share/applications"), "flatpak-user"),
            ("/var/lib/flatpak/exports/share/applications", "flatpak"),
            ("/usr/share/applications", "system"), ("/usr/local/share/applications", "system"),
            (os.path.expanduser("~/.local/share/applications"), "user")]
    for d, source in dirs:
        for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            app_id = os.path.basename(path)[:-len(".desktop")]
            if app_id in seen or app_id in HIDDEN_LINUX_APPS or app_id.startswith("waydroid."):
                continue
            if d == "/usr/share/applications" and app_id in base:
                continue
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                cp.read(path)
                e = cp["Desktop Entry"]
            except (configparser.Error, KeyError):
                continue
            if e.get("Type") != "Application" or e.getboolean("NoDisplay", False) or e.getboolean("Hidden", False):
                continue
            if e.get("Terminal", "false") == "true" or "Settings" in e.get("Categories", ""):
                continue
            seen.add(app_id)
            apps.append({"id": app_id, "source": source, "label": e.get("Name", app_id), "icon": _icon_file(e.get("Icon", "")),
                         "exec": re.sub(r"%[a-zA-Z]|@@u?", "", e.get("Exec", "")).strip()})
    return sorted(apps, key=lambda a: a["label"].lower())


def kids_app_choices():
    """What a parent can choose from for a Kids profile: their Android apps and Linux apps.
    Linux apps are "linux:<id>" (installed for everyone) or "flatpak:<id>" (App Store apps, which
    BlidOS installs for everyone once allowed)."""
    labels = android_labels()
    android = [{"id": p, "label": labels[p], "icon": android_icon(p)}
               for p in daemon("android-installed")["packages"] if p in labels]
    linux = [{"id": ("flatpak:" if a["source"].startswith("flatpak") else "linux:") + a["id"], "label": a["label"],
              "icon": "image://icon/" + a["icon"] if a["icon"] else ""} for a in linux_apps()]
    return {"android": sorted(android, key=lambda a: a["label"].lower()), "linux": linux}


# ---------- App Store (Flatpak apps from Flathub) ----------
#
# Apps install for this profile only (flatpak --user), like Android apps: every profile has its own.

FLATHUB_API = "https://flathub.org/api/v2"
FLATHUB_REPO = "https://dl.flathub.org/repo/flathub.flatpakrepo"
STORE_CATEGORIES = {"": "Popular", "game": "Games", "audiovideo": "Video and music", "education": "Learning",
                    "graphics": "Photos and art", "network": "Internet", "office": "Office", "utility": "Tools"}
_store_jobs = {}  # app id -> {"running", "ok", "message"}


def _flathub(path, body=None):
    req = urllib.request.Request(FLATHUB_API + path, data=json.dumps(body).encode() if body else None,
                                 headers={"Content-Type": "application/json", "User-Agent": "BlidOS"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r)
    except OSError:
        raise DaemonError("Can't reach the App Store. Check the internet connection.")


def _store_entry(hit):
    return {"id": hit["app_id"], "name": hit.get("name") or hit["app_id"], "summary": hit.get("summary") or "",
            "icon": hit.get("icon") or "", "developer": hit.get("developer_name") or "",
            "verified": bool(hit.get("verification_verified"))}


def _store_list(hits):
    return [_store_entry(h) for h in hits if "desktop" in (h.get("type") or "desktop")]


def _not_kids():
    if not daemon("kid-may", rule="store")["allowed"]:
        raise DaemonError("A parent hasn't allowed the App Store for this profile")


def store_browse(category=""):
    if category and category not in STORE_CATEGORIES:
        raise ValueError("Unknown category")
    path = f"/collection/category/{category}" if category else "/collection/popular"
    return _store_list(_flathub(path + "?page=1&per_page=36")["hits"])


def store_search(query):
    return _store_list(_flathub("/search", {"query": query[:100], "hits_per_page": 36})["hits"])


def store_installed():
    out = run(["flatpak", "list", "--app", "--columns=application"]).stdout
    return sorted(set(out.split()))


def _check_app_id(app_id):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", app_id or ""):
        raise ValueError("Unknown app")


def store_install(app_id):
    _check_app_id(app_id)
    _not_kids()
    if _store_jobs.get(app_id, {}).get("running"):
        return
    job = _store_jobs[app_id] = {"running": True, "ok": None, "message": "Installing…"}

    def work():
        run(["flatpak", "--user", "remote-add", "--if-not-exists", "flathub", FLATHUB_REPO], timeout=60)
        p = subprocess.Popen(["flatpak", "--user", "install", "-y", "--noninteractive", "flathub", app_id],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        last = ""
        for line in p.stdout:
            line = line.strip()
            if line:
                last = line
            m = re.search(r"(\d+)%", line)
            if m:
                job["message"] = f"Installing… {m.group(1)}%"
        job["ok"] = p.wait() == 0
        job["message"] = "Installed" if job["ok"] else (last or "Installing failed")
        job["running"] = False

    threading.Thread(target=work, daemon=True).start()


def store_job(app_id):
    return _store_jobs.get(app_id, {"running": False, "ok": None, "message": ""})


def store_remove(app_id):
    _check_app_id(app_id)
    _not_kids()
    r = run(["flatpak", "uninstall", "--user", "-y", "--noninteractive", app_id], timeout=300)
    if r.returncode != 0:
        if app_id in run(["flatpak", "list", "--system", "--app", "--columns=application"]).stdout.split():
            raise DaemonError("This app was installed for everyone in Desktop mode. Remove it there, in Discover.")
        raise DaemonError("Couldn't remove the app")


def store_open(app_id):
    _check_app_id(app_id)
    _start_and_wait(["flatpak", "run", app_id])


# ---------- Game controllers ----------

def _controller_battery(uniq):
    """Battery level of a wireless controller, matched by its Bluetooth address."""
    if not uniq:
        return None
    for d in glob.glob("/sys/class/power_supply/*"):
        if uniq.lower() in os.path.basename(d).lower():
            try:
                with open(os.path.join(d, "capacity")) as f:
                    return int(f.read())
            except (OSError, ValueError):
                return None
    return None


def controller_remote():
    """The controller helper's status: running, the controllers it uses, the last button pressed."""
    path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "blidos-gamepad.json")
    try:
        with open(path) as f:
            s = json.load(f)
    except (OSError, ValueError):
        return {"running": False, "pads": [], "last": "", "ago": None, "error": "Not running"}
    alive = s.get("running") and os.path.exists(f"/proc/{s.get('pid', 0)}")  # it may have stopped since
    return {"running": bool(alive), "pads": s.get("pads", []), "last": s.get("last", ""),
            "ago": round(time.time() - s["at"]) if s.get("at") else None, "error": s.get("error", "")}


def controllers():
    """Connected game controllers: Xbox, PlayStation, Switch, Steam and other USB/Bluetooth pads."""
    try:
        import evdev
        from evdev import ecodes
    except ImportError:
        return []
    found, seen = [], set()
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        keys = dev.capabilities().get(ecodes.EV_KEY, [])
        key = (dev.name, dev.uniq or dev.phys)
        if dev.name != "BlidOS controller remote" and key not in seen and \
                (ecodes.BTN_SOUTH in keys or ecodes.BTN_GAMEPAD in keys):
            seen.add(key)
            found.append({"name": dev.name,
                          "connection": {0x03: "USB", 0x05: "Bluetooth"}.get(dev.info.bustype, ""),
                          "battery": _controller_battery(dev.uniq)})
        dev.close()
    return sorted(found, key=lambda c: c["name"])


def _windows():
    """Ids of the app windows open now (sway)."""
    ids = set()

    def walk(node):
        if node.get("type") in ("con", "floating_con") and node.get("pid"):
            ids.add(node["id"])
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            walk(child)
    try:
        walk(json.loads(run(["swaymsg", "-t", "get_tree"]).stdout or "{}"))
    except ValueError:
        pass
    return ids


def _start_and_wait(cmd, timeout=120):
    """Starts an app and returns once its window is on screen, so BlidOS can show "Opening…"
    meanwhile (some apps, Flatpak ones especially, take a while the first time)."""
    before = _windows()
    p = subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    end = time.time() + timeout
    while time.time() < end:
        time.sleep(0.4)
        if _windows() - before:
            return
        code = p.poll()
        if code is not None and code != 0:
            raise DaemonError("The app didn't start")
        if code == 0 and time.time() > end - timeout + 15:
            return  # a launcher that handed off and quit; its app may show up later
    # Still no window: stop waiting, the app may be running in the background.


def launch_linux(exec_line):
    _start_and_wait(["sh", "-c", exec_line])


def android_session():
    out = run(["waydroid", "status"]).stdout
    return re.search(r"Session:\s+RUNNING", out) is not None


def android_running():
    """Android has finished starting. Its window stays black until then, so apps wait for this."""
    if not android_session():
        return False
    try:
        return daemon("android-ready")["ready"]
    except DaemonError:
        return False


def wait_for_android(timeout=300):
    """Waits until Android can show apps."""
    end = time.time() + timeout  # TV mode's start-android starts (and restarts) Android
    while time.time() < end:
        if android_running():
            return
        time.sleep(2)
    raise DaemonError("Android didn't finish starting. Try Settings → Android and Google Play → Graphics.")


def install_apk(path):
    """Installs an Android app file (from a USB drive or Downloads) into this profile's Android."""
    wait_for_android(timeout=240)
    copy = daemon("apk-fetch", path=path)["path"]
    try:
        r = run(["waydroid", "app", "install", copy], timeout=300)
    finally:
        try:
            os.unlink(copy)
        except OSError:
            pass
    if r.returncode != 0 or re.search(r"ERROR|Failed|stopped", r.stdout + r.stderr):
        raise DaemonError("Android couldn't install that app. It may be damaged, or made for another kind of device.")


def save_android_report():
    path = os.path.expanduser("~/blidos-android-report.txt")
    with open(path, "w") as f:
        f.write(daemon("android-report")["report"] + "\n")
    return path


LAUNCH_MARKER = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "blidos-launch")


def _android_window():
    return '"app_id": "Waydroid"' in run(["swaymsg", "-t", "get_tree"]).stdout


def open_android_window():
    """Makes sure Android's full-screen window exists (it shows Android's own home at first)."""
    if _android_window():
        return
    subprocess.Popen(["waydroid", "show-full-ui"], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(60):
        time.sleep(0.5)
        if _android_window():
            time.sleep(1.5)
            return


def show_android():
    """Brings Android's window forward. The session helper won't send you back home for a few seconds."""
    open(LAUNCH_MARKER, "w").close()
    run(["swaymsg", '[app_id="Waydroid"] focus'])


def restart_android():
    """Stops this profile's Android; TV mode's start-android starts it again."""
    run(["waydroid", "session", "stop"], timeout=60)


# ---------- Session and power ----------

def switch_mode(mode):
    """TV mode or Desktop mode (KDE Plasma): the session restarts in the other mode."""
    if mode not in ("tv", "desktop"):
        raise ValueError("Unknown mode")
    if mode == "desktop" and not daemon("kid-may", rule="desktop")["allowed"]:
        raise DaemonError("A parent hasn't allowed Desktop mode for this profile")
    subprocess.Popen(["/usr/lib/blidos/switch-mode", mode], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def switch_profile():
    """Ends this profile's session; greetd shows the profile picker again."""
    # Tells the session loop this is a sign-out, so it doesn't take a quick exit for a failed start.
    open(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "blidos-signout"), "w").close()
    run(["swaymsg", "exit"])


def restart():
    run(["systemctl", "reboot"])


def shut_down():
    run(["systemctl", "poweroff"])


def has_terminal():
    return shutil.which("foot") is not None


def open_terminal():
    subprocess.Popen(["foot"], start_new_session=True)


def os_version():
    try:
        return open("/etc/blidos-version").read().strip()
    except OSError:
        return "development"


def storage():
    st = os.statvfs(os.path.expanduser("~"))
    return {"total": st.f_blocks * st.f_frsize, "free": st.f_bavail * st.f_frsize}
