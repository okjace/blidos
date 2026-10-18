"""blidosd: the small root service behind BlidOS.

It owns everything that needs root: profiles (one Linux user each, with the PIN as the user's
password), Kids rules inside Android, drivers and system updates. Clients talk to it over a
UNIX socket, one JSON request per line. Every request is checked against the caller's user id
(SO_PEERCRED), so a profile can only do what it's allowed to.
"""
import configparser
import glob
import grp
import hashlib
import json
import os
import pwd
import re
import shutil
import socket
import sqlite3
import struct
import subprocess
import threading
import time
import urllib.request

SOCKET = "/run/blidos/blidosd.sock"
STATE = "/var/lib/blidos/profiles.json"
SETUP_DONE = "/var/lib/blidos/setup-done"
GREETER_USER = "_greetd"
USER_GROUPS = ["blidos", "audio", "video", "render", "input", "netdev", "plugdev"]
MAX_PROFILES = 8
GOOGLE = "com.android.vending"
ANDROID_SETTINGS = "com.android.settings"

_profiles_lock = threading.Lock()  # profile changes happen one at a time
_jobs_lock = threading.Lock()
_jobs = {}  # name -> {"running": bool, "log": [str], "ok": bool|None}


# ---------- Profile storage ----------

def _load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except FileNotFoundError:
        return []


def _save(profiles):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(profiles, f, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, STATE)


def _has_password(user):
    try:
        out = subprocess.run(["passwd", "-S", user], capture_output=True, text=True).stdout.split()
        return len(out) > 1 and out[1] == "P"
    except Exception:
        return False


# What a Kids profile may do besides opening its allowed apps. Parents turn these on per kid.
KIDS_RULES = {"googlePlay": False,  # Google Play: install their own Android apps
              "store": False,       # the App Store (Linux apps and games)
              "desktop": False,     # Desktop mode (KDE Plasma)
              "settings": False,    # Wi-Fi, Bluetooth, sound, display
              "power": False}       # restart and shut down


def _rules(p):
    saved = p.get("rules", {})
    return {k: bool(saved.get(k, default)) for k, default in KIDS_RULES.items()}


def _kid_may(profiles, user, rule):
    me = next((p for p in profiles if p["user"] == user), None)
    return not (me and me.get("kids")) or _rules(me)[rule]


def _public(p):
    return {
        "user": p["user"], "name": p["name"], "color": p.get("color", 0),
        "owner": p.get("owner", False), "kids": p.get("kids", False),
        "allowed": p.get("allowed", []), "rules": _rules(p), "hasPin": _has_password(p["user"]),
    }


def _new_username(profiles):
    taken = {p["user"] for p in profiles}
    n = 1
    while f"profile{n}" in taken or _user_exists(f"profile{n}"):
        n += 1
    return f"profile{n}"


def _user_exists(user):
    try:
        pwd.getpwnam(user)
        return True
    except KeyError:
        return False


def _set_pin(user, pin):
    if pin is None:
        subprocess.run(["passwd", "-d", user], check=True, capture_output=True)
        return
    if not re.fullmatch(r"\d{4}", str(pin)):
        raise ValueError("A PIN is 4 digits")
    subprocess.run(["chpasswd"], input=f"{user}:{pin}\n", text=True, check=True, capture_output=True)
    subprocess.run(["faillock", "--user", user, "--reset"], capture_output=True)


# ---------- Who's asking ----------

def _caller(conn):
    creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    _, uid, _ = struct.unpack("3i", creds)
    try:
        name = pwd.getpwuid(uid).pw_name
    except KeyError:
        name = None
    return uid, name


def _role(uid, name, profiles):
    if uid == 0:
        return "root"
    if name == GREETER_USER:
        return "greeter"
    for p in profiles:
        if p["user"] == name:
            return "owner" if p.get("owner") else ("kids" if p.get("kids") else "profile")
    return "other"


class Denied(Exception):
    pass


def _require(role, *allowed):
    if role not in allowed and role != "root":
        raise Denied("Not allowed")


# ---------- Android (Waydroid) ----------

def _waydroid_shell(cmd, timeout=30):
    return subprocess.run(["waydroid", "shell", "--", "sh", "-c", cmd],
                          capture_output=True, text=True, timeout=timeout)


def _android_ready():
    """Android has finished starting (until then its window is black)."""
    try:
        return _waydroid_shell("getprop sys.boot_completed", timeout=8).stdout.strip() == "1"
    except subprocess.TimeoutExpired:
        return False


# How Android draws. "auto" lets Waydroid pick from the graphics chip. The others are for chips
# where the automatic choice shows black screens.
WAYDROID_CFG = "/var/lib/waydroid/waydroid.cfg"
ANDROID_READY = "/var/lib/waydroid/blidos-android-ready"  # written when first-start setup (the download) has finished
GRAPHICS = {
    "auto": {},
    "compatible": {"ro.hardware.gralloc": "minigbm_gbm_mesa", "ro.hardware.egl": "mesa"},
    "software": {"ro.hardware.gralloc": "default", "ro.hardware.egl": "swiftshader"},
}


GRAPHICS_CHOICE = "/var/lib/blidos/android-graphics"


def _graphics_mode():
    try:
        with open(GRAPHICS_CHOICE) as f:
            mode = f.read().strip()
    except OSError:
        mode = "auto"
    return mode if mode in GRAPHICS else "auto"


def _has_3d():
    """A graphics chip Android can draw with (virtual machines: virgl)."""
    drivers = " ".join(os.path.basename(os.path.realpath(p)) for p in glob.glob("/sys/class/drm/card*/device/driver"))
    if re.search(r"i915|xe|amdgpu|radeon|nouveau", drivers):
        return True
    for f in glob.glob("/sys/bus/virtio/devices/*/features"):
        try:
            if open(os.path.join(os.path.dirname(f), "device")).read().strip() == "0x0010" and open(f).read(1) == "1":
                return True
        except OSError:
            pass
    return False


# Android TV mode: Android reports itself as a TV (so Android TV apps install and run) and uses its
# TV system screens. Those have no phone lock screen, so an overlay turns Android's off. Off by
# default: Google Play for phones, the one in this Android, won't run on a TV.
TV_CHOICE = "/var/lib/blidos/android-tv"
TV_FILES = {"/usr/share/blidos/android-tv/blidos-television.xml":
            "/var/lib/waydroid/overlay/system/etc/permissions/blidos-television.xml",
            "/usr/share/blidos/android-tv/BlidOSTvOverlay.apk":
            "/var/lib/waydroid/overlay/system/product/overlay/BlidOSTvOverlay.apk"}
ALWAYS_PROPS = {"persist.waydroid.uevent": "true"}  # controllers (and other USB/Bluetooth input) reach Android


def _tv_mode():
    try:
        with open(TV_CHOICE) as f:
            return f.read().strip() == "on"
    except OSError:
        return False


def _apply_tv_files():
    """Puts the Android TV mode files in Waydroid's overlay, or takes them out. Returns whether anything changed."""
    changed = False
    for src, dest in TV_FILES.items():
        want = _tv_mode() and os.path.exists(src)
        if want and not (os.path.exists(dest) and open(src, "rb").read() == open(dest, "rb").read()):
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copyfile(src, dest)
            os.chmod(dest, 0o644)
            changed = True
        elif not want and os.path.exists(dest):
            os.unlink(dest)
            changed = True
    return changed


def _apply_graphics():
    """Puts the chosen graphics mode (and the settings BlidOS always wants) into Android's
    settings. "auto" looks at the graphics chip every time, so a first start without working
    graphics (safe mode, a missing driver) doesn't leave Android drawing in software, or trying
    hardware that isn't there, for good. Returns whether anything changed."""
    if not os.path.exists(ANDROID_READY):
        return False  # still downloading: the setup picks graphics itself
    mode = _graphics_mode()
    wanted = GRAPHICS[mode] if mode != "auto" else ({} if _has_3d() else GRAPHICS["software"])
    cfg = configparser.ConfigParser()
    cfg.read(WAYDROID_CFG)
    if not cfg.has_section("properties"):
        cfg.add_section("properties")
    keys = ("ro.hardware.gralloc", "ro.hardware.egl")
    same = {k: cfg.get("properties", k) for k in keys if cfg.has_option("properties", k)} == wanted
    same = same and all(cfg.get("properties", k, fallback=None) == v for k, v in ALWAYS_PROPS.items())
    if same:
        return False
    for key in keys:
        cfg.remove_option("properties", key)
    for key, value in {**wanted, **ALWAYS_PROPS}.items():
        cfg.set("properties", key, value)
    with open(WAYDROID_CFG, "w") as f:
        cfg.write(f)
    # Rewrites Android's hardware settings from the config.
    subprocess.run(["waydroid", "upgrade", "--offline"], capture_output=True, timeout=300)
    return True


def _restart_android():
    subprocess.run(["systemctl", "restart", "waydroid-container"], capture_output=True, timeout=120)


def _set_graphics(mode):
    with open(GRAPHICS_CHOICE, "w") as f:
        f.write(mode + "\n")
    if _apply_graphics():
        _restart_android()


def _set_tv_mode(on):
    with open(TV_CHOICE, "w") as f:
        f.write(("on" if on else "off") + "\n")
    if _apply_tv_files():
        _restart_android()


def _android_report():
    """What's needed to work out why Android shows black screens on this computer."""
    def run(cmd, timeout=20):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return (r.stdout + r.stderr).strip()
        except Exception as e:
            return f"({e})"

    def tail(path, n):
        try:
            with open(path, errors="replace") as f:
                return "".join(f.readlines()[-n:]).strip()
        except OSError as e:
            return f"({e})"

    gpu = "\n".join(l for l in run(["lspci", "-nnk"]).splitlines()
                    if re.search(r"VGA|3D|Display|Kernel driver", l))
    props = "\n".join(l for l in tail("/var/lib/waydroid/waydroid_base.prop", 400).splitlines()
                      if re.search(r"gralloc|egl|vulkan|gbm", l))
    parts = [
        ("BlidOS", tail("/etc/blidos-version", 1)),
        ("Graphics chips", gpu),
        ("Graphics mode", _graphics_mode()),
        ("Android TV mode", "on" if _tv_mode() else "off"),
        ("Android graphics settings", props),
        ("Android status", run(["waydroid", "status"])),
        ("Android finished starting", "yes" if _android_ready() else "no"),
        ("Waydroid log", tail("/var/lib/waydroid/waydroid.log", 60)),
        ("Android crashes", run(["waydroid", "shell", "--", "logcat", "-d", "-b", "crash", "-t", "60"])),
        ("Android graphics errors", "\n".join(run(["waydroid", "shell", "--", "logcat", "-d", "-t", "2000", "*:E"]).splitlines()[-80:])),
    ]
    return "\n\n".join(f"== {title}\n{body}" for title, body in parts)


def _android_packages():
    out = _waydroid_shell("pm list packages").stdout
    return [line.split(":", 1)[1].strip() for line in out.splitlines() if line.startswith("package:")]


def _launchable():
    """Apps with a phone/tablet or Android TV launcher entry, as (package, label) pairs."""
    found = {}
    for category in ("android.intent.category.LEANBACK_LAUNCHER", "android.intent.category.LAUNCHER"):
        out = _waydroid_shell(
            f"cmd package query-activities --brief -a android.intent.action.MAIN -c {category}").stdout
        for line in out.splitlines():
            line = line.strip()
            if "/" in line and not line.startswith("priority"):
                pkg = line.split("/", 1)[0]
                found.setdefault(pkg, category.endswith("LEANBACK_LAUNCHER"))
    return found


def _android_data(user):
    return os.path.join(pwd.getpwnam(user).pw_dir, ".local/share/waydroid/data")


def _owner_apks(owner_user):
    """Android apps the owner installed (from Google Play), as {package: [apk paths]}."""
    apps = {}
    for base in glob.glob(os.path.join(_android_data(owner_user), "app", "*", "*", "base.apk")):
        folder = os.path.dirname(base)
        pkg = os.path.basename(folder).split("-", 1)[0]
        apps[pkg] = sorted(glob.glob(os.path.join(folder, "*.apk")))
    return apps


ANDROID_HOMES = {"com.android.launcher3", "com.android.settings", "com.google.android.apps.nexuslauncher"}


def _resolve(pkg):
    """The activity that opens an app: its Android TV entry if it has one, else its phone/tablet entry."""
    for category in ("android.intent.category.LEANBACK_LAUNCHER", "android.intent.category.LAUNCHER"):
        out = _waydroid_shell(
            f"cmd package resolve-activity --brief -a android.intent.action.MAIN -c {category} {pkg}").stdout
        lines = [l.strip() for l in out.splitlines() if "/" in l]
        if lines:
            return lines[-1]
    return None


def _apply_kids(profile, owner_user):
    """Inside a Kids profile's Android: copy in the allowed apps from the owner's Android, hide everything
    else. With Google Play allowed, the apps they install themselves stay too."""
    play = _rules(profile)["googlePlay"]
    allowed = {a for a in profile.get("allowed", []) if ":" not in a} - {GOOGLE, ANDROID_SETTINGS}
    installed = set(_android_packages())
    staging_host = os.path.join(_android_data(profile["user"]), "local", "tmp", "blidos")
    for pkg, apks in _owner_apks(owner_user).items():
        if pkg not in allowed or pkg in installed:
            continue
        shutil.rmtree(staging_host, ignore_errors=True)
        os.makedirs(staging_host)
        for apk in apks:
            shutil.copy(apk, staging_host)
        names = " ".join(f"/data/local/tmp/blidos/{os.path.basename(a)}" for a in apks)
        _waydroid_shell(f"pm install-multiple -r {names}", timeout=180)
    shutil.rmtree(staging_host, ignore_errors=True)
    launchable = _launchable()
    for pkg in launchable:
        verb = "enable" if pkg in allowed or (play and pkg != ANDROID_SETTINGS) else "disable-user --user 0"
        _waydroid_shell(f"pm {verb} {pkg}")
    _waydroid_shell(f"pm {'enable' if play else 'disable-user --user 0'} {GOOGLE}")
    _waydroid_shell(f"pm disable-user --user 0 {ANDROID_SETTINGS}")


def _gsf_id(user):
    """The Google Services Framework id that has to be registered at google.com/android/uncertified."""
    home = pwd.getpwnam(user).pw_dir
    db = os.path.join(home, ".local/share/waydroid/data/data/com.google.android.gsf/databases/gservices.db")
    if not os.path.exists(db):
        return None
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        row = con.execute("select value from main where name = 'android_id'").fetchone()
        return row[0] if row else None
    finally:
        con.close()


# ---------- Drivers and updates (long-running jobs) ----------

DRIVERS = {
    "nvidia": {
        "name": "NVIDIA graphics driver",
        "detect": lambda pci: "[10de:" in pci and ("VGA" in pci or "3D controller" in pci),
        "packages": ["nvidia-driver", "firmware-misc-nonfree", "linux-headers-amd64"],
    },
    "broadcom-wifi": {
        "name": "Broadcom Wi-Fi driver",
        "detect": lambda pci: re.search(r"14e4:(43(1|2|3|5|6|a|b|c)\w)", pci) is not None,
        "packages": ["broadcom-sta-dkms", "linux-headers-amd64"],
    },
    "amd-firmware": {
        "name": "AMD graphics firmware",
        "detect": lambda pci: "[1002:" in pci and ("VGA" in pci or "Display" in pci),
        "packages": ["firmware-amd-graphics"],
    },
    "intel-firmware": {
        "name": "Intel graphics and Wi-Fi firmware",
        "detect": lambda pci: "[8086:" in pci and ("VGA" in pci or "Network controller" in pci),
        "packages": ["firmware-intel-graphics", "firmware-iwlwifi", "intel-media-va-driver"],
    },
}


def _installed(pkg):
    r = subprocess.run(["dpkg-query", "-W", "-f=${Status}", pkg], capture_output=True, text=True)
    return "install ok installed" in r.stdout


def _drivers():
    pci = subprocess.run(["lspci", "-nn"], capture_output=True, text=True).stdout
    result = []
    for key, d in DRIVERS.items():
        lines = [l for l in pci.splitlines() if d["detect"](l)]
        if lines:
            result.append({
                "id": key, "name": d["name"], "device": lines[0].split(": ", 1)[-1][:80],
                "installed": all(_installed(p) for p in d["packages"]),
            })
    return result


def _run_job(name, steps):
    """Runs install steps in the background, one job at a time (they all use apt).
    A step is a command list, ("optional", command) for one that may fail, or a Python function."""
    with _jobs_lock:
        if any(j["running"] for j in _jobs.values()):
            raise ValueError("Something else is installing. Try again when it's finished.")
        job = _jobs[name] = {"running": True, "log": [], "ok": None}

    def work():
        env = dict(os.environ, DEBIAN_FRONTEND="noninteractive")
        ok = True
        try:
            for step in steps:
                if callable(step):
                    step(job["log"])
                    continue
                optional = isinstance(step, tuple)
                cmd = step[1] if optional else step
                job["log"].append("$ " + " ".join(cmd))
                p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
                for line in p.stdout:
                    job["log"].append(line.rstrip())
                    del job["log"][:-200]
                if p.wait() != 0 and not optional:
                    ok = False
                    break
        except Exception as e:
            job["log"].append(str(e))
            ok = False
        job["ok"] = ok
        job["running"] = False

    threading.Thread(target=work, daemon=True).start()


def _apt(args):
    # --no-remove: an install that would remove any installed package stops instead.
    return ["apt-get", "-y", "--no-remove", "-o", "Dpkg::Options::=--force-confdef",
            "-o", "Dpkg::Options::=--force-confold"] + args


# ---------- Packages (.deb files) and updates ----------
#
# Installs never touch profiles, Android apps or files: those live in /home, /var/lib/blidos and
# /var/lib/waydroid, which no package owns. On top of that, every install:
#   - needs 1.5 GB free, so it can't fail halfway for lack of space;
#   - first finishes any install that was cut off (for example by a power cut);
#   - saves a copy of the profile list and system settings to /var/backups/blidos;
#   - refuses to remove any installed package (apt --no-remove).

MEDIA = "/run/blidos/media"
DEB_CACHE = "/var/cache/blidos/debs"
BACKUPS = "/var/backups/blidos"
MIN_FREE = 1536 * 1024 * 1024
# iso9660: a USB stick written from a BlidOS ISO carries that version's update file.
MOUNTABLE = {"vfat", "exfat", "ntfs", "ntfs3", "ext2", "ext3", "ext4", "btrfs", "xfs", "iso9660"}


def _usb_drives():
    """(mount point, label) of each partition on a USB or other removable drive, mounting read-only as needed."""
    out = subprocess.run(["lsblk", "-J", "-p", "-o", "PATH,TRAN,HOTPLUG,RM,FSTYPE,LABEL,MOUNTPOINTS"],
                         capture_output=True, text=True).stdout
    found = []

    def walk(dev, removable):
        removable = removable or dev.get("tran") == "usb" or dev.get("hotplug") in (True, "1")
        if removable and dev.get("fstype") in MOUNTABLE:
            found.append(dev)
        for child in dev.get("children") or []:
            walk(child, removable)

    for dev in json.loads(out or '{"blockdevices": []}')["blockdevices"]:
        walk(dev, False)
    drives = []
    for dev in found:
        label = dev.get("label") or "USB drive"
        mounted = [m for m in dev.get("mountpoints") or [] if m]
        if mounted:
            drives.append((mounted[0], label))
            continue
        target = os.path.join(MEDIA, os.path.basename(dev["path"]))
        os.makedirs(target, exist_ok=True)
        if subprocess.run(["mount", "-o", "ro,nosuid,nodev,noexec", dev["path"], target],
                          capture_output=True).returncode == 0:
            drives.append((target, label))
    return drives


def _unmount_usb():
    for name in os.listdir(MEDIA) if os.path.isdir(MEDIA) else []:
        path = os.path.join(MEDIA, name)
        subprocess.run(["umount", path], capture_output=True)
        try:
            os.rmdir(path)
        except OSError:
            pass


def _deb_files():
    """Package files on USB drives and in each profile's Downloads folder: .deb (Linux) and
    .apk (Android)."""
    places = list(_usb_drives())
    for p in _load():
        try:
            home = pwd.getpwnam(p["user"]).pw_dir
        except KeyError:
            continue
        places.append((os.path.join(home, "Downloads"), "Downloads (" + p["name"] + ")"))
    files, seen = [], set()
    for root, where in places:
        depth0 = root.rstrip("/").count("/")
        for folder, dirs, names in os.walk(root):
            if folder.count("/") - depth0 >= 3:
                dirs[:] = []
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for n in sorted(names):
                path = os.path.join(folder, n)
                kind = n.lower().rsplit(".", 1)[-1]
                size = os.path.getsize(path) if os.path.isfile(path) and not os.path.islink(path) else -1
                if kind in ("deb", "apk") and size >= 0 and (n, size, where) not in seen:
                    seen.add((n, size, where))
                    files.append({"path": path, "file": n, "where": where, "size": size, "kind": kind})
                    if len(files) >= 200:
                        return files
    return files


def _deb_fields(path):
    r = subprocess.run(["dpkg-deb", "-f", path, "Package", "Version", "Architecture", "Description"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise ValueError("This file isn't a working package. It may be damaged or only partly copied.")
    fields = {}
    for line in r.stdout.splitlines():
        if ":" in line and not line.startswith(" "):
            k, v = line.split(":", 1)
            fields[k] = v.strip()
    return fields


def _installed_version(pkg):
    r = subprocess.run(["dpkg-query", "-W", "-f=${Status}|${Version}", pkg], capture_output=True, text=True)
    status, _, version = r.stdout.partition("|")
    return version if "install ok installed" in status else ""


def _newer(a, b):
    return subprocess.run(["dpkg", "--compare-versions", a, "gt", b]).returncode == 0


APK_DIR = "/run/blidos/apk"


def _fetch_apk(path, uid):
    """A copy of a listed .apk that only the asking profile can read, for it to install into its
    own Android (Waydroid installs through the profile's session, not as root)."""
    if path not in {f["path"] for f in _deb_files() if f["kind"] == "apk"}:
        raise ValueError("That file isn't on a USB drive or in Downloads anymore")
    os.makedirs(APK_DIR, mode=0o711, exist_ok=True)
    dest = os.path.join(APK_DIR, f"{uid}-{int(time.time())}.apk")
    shutil.copyfile(path, dest)
    os.chown(dest, uid, -1)
    os.chmod(dest, 0o600)
    return dest


def _deb_details(path):
    """Copies a listed .deb somewhere only root can write (so it can't change before it's
    installed), and describes it."""
    if path not in {f["path"] for f in _deb_files() if f["kind"] == "deb"}:
        raise ValueError("That file isn't on a USB drive or in Downloads anymore")
    os.makedirs(DEB_CACHE, mode=0o700, exist_ok=True)
    for old in glob.glob(os.path.join(DEB_CACHE, "*.deb")):
        if time.time() - os.path.getmtime(old) > 86400:
            os.unlink(old)
    digest = hashlib.sha256()
    tmp = os.path.join(DEB_CACHE, "incoming.tmp")
    with open(path, "rb") as src, open(tmp, "wb") as dst:
        for chunk in iter(lambda: src.read(1 << 20), b""):
            digest.update(chunk)
            dst.write(chunk)
    key = digest.hexdigest()
    os.replace(tmp, os.path.join(DEB_CACHE, key + ".deb"))
    f = _deb_fields(os.path.join(DEB_CACHE, key + ".deb"))
    pkg, version, arch = f.get("Package", ""), f.get("Version", ""), f.get("Architecture", "")
    installed = _installed_version(pkg)
    problem = ""
    machine = subprocess.run(["dpkg", "--print-architecture"], capture_output=True, text=True).stdout.strip()
    if arch not in ("all", machine):
        problem = f"This package is for {arch} computers. This computer needs {machine} or all."
    elif installed and not _newer(version, installed) and installed != version:
        problem = f"A newer version ({installed}) is already installed."
    return {"key": key, "package": pkg, "version": version, "arch": arch, "installed": installed,
            "summary": f.get("Description", "").split("\n")[0], "problem": problem, "blidos": pkg == "blidos"}


def _cached_deb(key):
    if not re.fullmatch(r"[0-9a-f]{64}", str(key)):
        raise ValueError("Unknown package")
    path = os.path.join(DEB_CACHE, key + ".deb")
    if not os.path.exists(path):
        raise ValueError("Choose the package again")
    return path


def _before_install(log):
    """Checks and backups shared by every install."""
    free = shutil.disk_usage("/").free
    if free < MIN_FREE:
        raise ValueError(f"Not enough free space ({free / 1e9:.1f} GB). Installing needs 1.5 GB free.")
    os.makedirs(BACKUPS, mode=0o700, exist_ok=True)
    backup = os.path.join(BACKUPS, time.strftime("before-install-%Y%m%d-%H%M%S.tar.gz"))
    subprocess.run(["tar", "-czf", backup, "--ignore-failed-read", "/etc", "/var/lib/blidos"],
                   capture_output=True)
    for old in sorted(glob.glob(os.path.join(BACKUPS, "before-install-*.tar.gz")))[:-5]:
        os.unlink(old)
    log.append("Saved a copy of your settings to " + backup)


def _install_steps(debs=(), upgrade=False):
    steps = [_before_install, ["dpkg", "--configure", "-a"], ("optional", _apt(["update"]))]
    if debs:
        steps.append(_apt(["install", "--reinstall"] + list(debs)))  # same version again: reinstall it
    if upgrade:
        steps.append(_apt(["upgrade", "--with-new-pkgs"]))  # never removes anything
    return steps


UPDATE_SOURCE = "/etc/blidos/update-source"   # GitHub "owner/repository" whose releases carry BlidOS updates
GITHUB_DEB = os.path.join(DEB_CACHE, "github-update.deb")
_apt_refresh = {"running": False, "ok": None, "at": 0}
_github = {}  # the newest release seen: {"version", "url", "digest", "size"}


def _refresh_package_lists():
    """apt-get update, in the background (it can take minutes on a slow connection)."""
    if _apt_refresh["running"] or any(j["running"] for j in _jobs.values()):
        return
    _apt_refresh["running"] = True

    def work():
        try:
            r = subprocess.run(["apt-get", "-q", "update", "-o", "APT::Update::Error-Mode=any"],
                               capture_output=True, timeout=600)
            _apt_refresh["ok"] = r.returncode == 0
        except subprocess.TimeoutExpired:
            _apt_refresh["ok"] = False
        _apt_refresh["at"] = time.time()
        _apt_refresh["running"] = False

    threading.Thread(target=work, daemon=True).start()


def _github_release():
    """The newest BlidOS release on GitHub: its version and the update file (blidos_<version>_all.deb)."""
    try:
        with open(UPDATE_SOURCE) as f:
            repo = f.read().strip()
    except OSError:
        return None
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        return None
    req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/latest",
                                 headers={"Accept": "application/vnd.github+json", "User-Agent": "BlidOS"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            release = json.load(r)
    except (OSError, ValueError):
        return None
    for asset in release.get("assets", []):
        m = re.fullmatch(r"blidos_([0-9][A-Za-z0-9.+~-]*)_all\.deb", asset.get("name", ""))
        url = asset.get("browser_download_url", "")
        if m and url.startswith(f"https://github.com/{repo}/releases/download/"):
            found = {"version": m.group(1), "url": url, "size": asset.get("size", 0),
                     "digest": (asset.get("digest") or "").removeprefix("sha256:")}
            _github.clear()
            _github.update(found)
            return found
    return None


def _download_github_update(log):
    """Downloads the update file found on GitHub and checks it before it's installed."""
    if not _github:
        raise ValueError("Check for updates again")
    log.append("Downloading BlidOS " + _github["version"] + " from GitHub…")
    os.makedirs(DEB_CACHE, mode=0o700, exist_ok=True)
    tmp = GITHUB_DEB + ".part"
    digest = hashlib.sha256()
    req = urllib.request.Request(_github["url"], headers={"User-Agent": "BlidOS"})
    with urllib.request.urlopen(req, timeout=60) as r, open(tmp, "wb") as f:
        for chunk in iter(lambda: r.read(1 << 20), b""):
            digest.update(chunk)
            f.write(chunk)
    if _github["digest"] and digest.hexdigest() != _github["digest"]:
        os.unlink(tmp)
        raise ValueError("The download was damaged (its checksum doesn't match). Try again.")
    fields = _deb_fields(tmp)
    if fields.get("Package") != "blidos" or fields.get("Version") != _github["version"]:
        os.unlink(tmp)
        raise ValueError("That download isn't a BlidOS update")
    os.replace(tmp, GITHUB_DEB)
    log.append("Downloaded and checked.")


def _check_updates():
    """System updates waiting (from Debian and Waydroid) and the newest BlidOS: on GitHub, on a
    USB drive (an update file, or a stick made from a BlidOS ISO) or in Downloads. Answers right
    away; the package lists refresh in the background (refreshing: true means ask again soon)."""
    if time.time() - _apt_refresh["at"] > 3600:
        _refresh_package_lists()
    sim = subprocess.run(["apt-get", "-s", "upgrade", "--with-new-pkgs"], capture_output=True, text=True).stdout
    system = sorted({l.split()[1] for l in sim.splitlines() if l.startswith("Inst ")})
    current = _installed_version("blidos")
    candidates = []
    release = _github_release()
    if release:
        candidates.append({"url": release["url"], "version": release["version"], "where": "GitHub",
                           "size": release["size"]})
    for f in _deb_files():
        if f["kind"] != "deb" or not f["file"].lower().startswith("blidos"):
            continue
        try:
            fields = _deb_fields(f["path"])
        except ValueError:
            continue
        if fields.get("Package") == "blidos":
            candidates.append({"path": f["path"], "version": fields.get("Version", ""), "where": f["where"],
                               "size": f["size"]})
    blidos = None
    for c in candidates:  # the newest; a local file wins a tie (no download)
        if (not current or _newer(c["version"], current)) and \
                (not blidos or _newer(c["version"], blidos["version"]) or
                 (c["version"] == blidos["version"] and "path" in c)):
            blidos = c
    return {"current": current, "system": system, "blidos": blidos, "online": bool(release) or bool(_apt_refresh["ok"]),
            "refreshing": _apt_refresh["running"]}


# ---------- Android starting up: what's happening, and getting unstuck ----------

_starting_since = {}  # "session" -> when this Android session was first seen starting


def _tail_lines(path, n):
    try:
        with open(path, errors="replace") as f:
            text = f.read()[-20000:]
    except OSError:
        return []
    lines = [l.strip() for l in re.split(r"[\r\n]+", text) if l.strip()]
    return lines[-n:]


def _session_running():
    out = subprocess.run(["waydroid", "status"], capture_output=True, text=True, timeout=15).stdout
    return re.search(r"Session:\s+RUNNING", out) is not None


def _android_status():
    """Where Android is on its way to running, for the "Starting Android" screen."""
    if not os.path.exists(ANDROID_READY):
        lines = _tail_lines("/var/lib/blidos/android-setup.log", 12)
        found = [re.search(r"\[Downloading\] ([0-9.]+) MB/([0-9.]+) MB", l) for l in lines]
        found = [m for m in found if m]
        if found and float(found[-1].group(2)) > 0:
            pct = round(float(found[-1].group(1)) / float(found[-1].group(2)) * 100)
            return {"stage": "downloading", "title": "Downloading Android", "progress": pct,
                    "detail": "About 1 GB, once. Android works when this is done.", "lines": lines}
        return {"stage": "setting-up", "title": "Setting up Android", "progress": None,
                "detail": "Waiting for the internet, then downloading Android (once)." if not lines else "Almost there.",
                "lines": lines}
    try:
        running = _session_running()
    except subprocess.TimeoutExpired:
        running = False
    if not running:
        _starting_since.pop("session", None)
        return {"stage": "waiting", "title": "Starting Android", "progress": None,
                "detail": "Starting this profile's Android…", "lines": _tail_lines("/var/lib/waydroid/waydroid.log", 10)}
    if _android_ready():
        _starting_since.pop("session", None)
        return {"stage": "running", "title": "Android is ready", "progress": 100, "detail": "", "lines": []}
    since = _starting_since.setdefault("session", time.time())
    try:
        log = _waydroid_shell("logcat -d -t 14 -v brief 2>/dev/null", timeout=8).stdout.splitlines()
    except subprocess.TimeoutExpired:
        log = []
    elapsed = int(time.time() - since)
    return {"stage": "starting", "title": "Starting Android", "progress": None, "elapsed": elapsed,
            "detail": "Android is booting. The first start of a profile takes the longest."
                      + (" Still going: BlidOS tries other graphics settings after a few minutes." if elapsed > 120 else ""),
            "lines": [l.strip() for l in log if l.strip()][-12:]}


FALLBACK = {"auto": "compatible", "compatible": "software"}
FALLBACK_AFTER = 360  # seconds an Android start may take before BlidOS tries other graphics settings


def _android_watchdog():
    """Android stuck starting (it never finishes, often a graphics problem): try the next
    graphics mode (Compatible, then Software) and start it again, by itself."""
    while True:
        time.sleep(20)
        try:
            if not os.path.exists(ANDROID_READY) or not _session_running():
                _starting_since.pop("session", None)
                continue
            since = _starting_since.setdefault("session", time.time())
            if _android_ready():
                _starting_since.pop("session", None)
                continue
            mode = _graphics_mode()
            if time.time() - since > FALLBACK_AFTER and mode in FALLBACK:
                with open("/var/lib/blidos/android-graphics-fallback.log", "a") as f:
                    f.write(time.strftime("%F %T ") + f"Android didn't start with {mode} graphics; trying {FALLBACK[mode]}\n")
                _starting_since.pop("session", None)
                _set_graphics(FALLBACK[mode])
        except Exception:
            pass


def _check_graphics_at_start():
    if not os.path.exists(ANDROID_READY):
        return
    try:
        changed = _apply_tv_files()
        if _apply_graphics() or changed:
            _restart_android()
    except Exception:
        pass


def _recover_installs():
    """At startup: finish an install that was cut off (power cut, crash) so the system is consistent."""
    if os.listdir("/var/lib/dpkg/updates"):
        _run_job("recovery", [["dpkg", "--configure", "-a"]])


# ---------- Requests ----------

MUTATING = {"create", "update", "set-pin", "delete"}


def handle(req, uid, name):
    if req.get("op") in MUTATING:
        with _profiles_lock:
            return _handle(req, uid, name)
    return _handle(req, uid, name)


def _handle(req, uid, name):
    op = req.get("op")
    profiles = _load()
    role = _role(uid, name, profiles)

    if op == "list":
        return {"profiles": [_public(p) for p in profiles]}

    if op == "whoami":
        me = next((p for p in profiles if p["user"] == name), None)
        return {"role": role, "profile": _public(me) if me else None}

    if op == "create":
        # During first-boot setup the greeter makes the owner and anyone else; later only the owner can.
        first = not profiles
        if os.path.exists(SETUP_DONE):
            _require(role, "owner")
        else:
            _require(role, "greeter", "owner")
        if len(profiles) >= MAX_PROFILES:
            raise ValueError(f"You can have up to {MAX_PROFILES} profiles")
        display = str(req["name"]).strip()[:20] or "Profile"
        user = _new_username(profiles)
        groups = USER_GROUPS + (["sudo"] if first else [])  # the owner can use sudo with their PIN
        subprocess.run(["useradd", "--create-home", "--shell", "/bin/bash", "--comment", display,
                        "--groups", ",".join(g for g in groups if _group_exists(g)), user],
                       check=True, capture_output=True)
        _set_pin(user, req.get("pin"))
        profile = {"user": user, "name": display, "color": len(profiles) % 6, "owner": first,
                   "kids": bool(req.get("kids")) and not first, "allowed": []}
        profiles.append(profile)
        _save(profiles)
        return {"profile": _public(profile)}

    if op == "setup-state":
        return {"done": os.path.exists(SETUP_DONE), "profiles": len(profiles)}

    if op == "finish-setup":
        _require(role, "greeter", "owner")
        if not profiles:
            raise ValueError("Create your profile first")
        os.makedirs(os.path.dirname(SETUP_DONE), exist_ok=True)
        open(SETUP_DONE, "w").close()
        return {}

    if op == "update":
        target = _find(profiles, req["user"])
        _require(role, "owner")
        before = set(target.get("allowed", []))
        if "rules" in req:
            target["rules"] = {k: bool(v) for k, v in dict(req["rules"]).items() if k in KIDS_RULES}
        for key in ("name", "color", "kids", "allowed"):
            if key in req:
                if key == "kids" and target.get("owner"):
                    continue
                target[key] = req[key]
        if "name" in req:
            subprocess.run(["usermod", "--comment", str(req["name"])[:20], target["user"]], capture_output=True)
        _save(profiles)
        # App Store apps the owner allowed: they're installed for the owner only, so install them for
        # everyone (the kid's profile then finds them).
        new = [a.split(":", 1)[1] for a in set(target.get("allowed", [])) - before if a.startswith("flatpak:")]
        new = [a for a in new if re.fullmatch(r"[A-Za-z0-9_.-]+", a) and subprocess.run(
            ["flatpak", "info", "--system", a], capture_output=True).returncode != 0]
        if new:
            _run_job("kids-apps", [["flatpak", "install", "--system", "-y", "--noninteractive", "flathub", *new]])
        return {"profile": _public(target), "installing": new}

    if op == "kid-may":
        # Whether this profile may use something parents can turn off (always yes for grown-ups).
        if req.get("rule") not in KIDS_RULES:
            raise ValueError("Unknown rule")
        return {"allowed": _kid_may(profiles, name, req["rule"])}

    if op == "set-pin":
        target = _find(profiles, req["user"])
        # The owner manages everyone's PIN; during setup the greeter sets the owner's first PIN.
        if not (role in ("owner", "root") or (role == "greeter" and target.get("owner") and not _has_password(target["user"]))):
            raise Denied("Not allowed")
        _set_pin(target["user"], req.get("pin"))
        return {}

    if op == "delete":
        _require(role, "owner")
        target = _find(profiles, req["user"])
        if target.get("owner"):
            raise ValueError("The owner profile can't be deleted")
        subprocess.run(["loginctl", "terminate-user", target["user"]], capture_output=True)
        time.sleep(1)
        subprocess.run(["userdel", "--remove", target["user"]], capture_output=True)
        _save([p for p in profiles if p["user"] != target["user"]])
        return {}

    if op == "android-apps":
        _require(role, "owner", "profile", "kids")
        apps = _launchable()
        me = next((p for p in profiles if p["user"] == name), None)
        if me and me.get("kids") and not _rules(me)["googlePlay"]:
            allowed = set(me.get("allowed", []))
            apps = {k: v for k, v in apps.items() if k in allowed}
        return {"apps": [{"package": k, "tv": v} for k, v in apps.items()]}

    if op == "android-launch":
        _require(role, "owner", "profile", "kids")
        pkg = req["package"]
        if not re.fullmatch(r"[A-Za-z0-9_.]+", pkg):
            raise ValueError("Bad package name")
        me = next((p for p in profiles if p["user"] == name), None)
        if me and me.get("kids") and pkg not in me.get("allowed", []) and not _rules(me)["googlePlay"]:
            raise Denied("Not allowed")
        component = _resolve(pkg)
        if not component:
            raise ValueError("That app can't be opened")
        _waydroid_shell(f"am start -n {component}")
        return {}

    if op == "android-ready":
        _require(role, "owner", "profile", "kids")
        return {"ready": _android_ready()}

    if op == "android-graphics":
        _require(role, "owner", "profile")
        if req.get("mode"):
            _require(role, "owner")
            if req["mode"] not in GRAPHICS:
                raise ValueError("Unknown graphics mode")
            _set_graphics(req["mode"])
        return {"mode": _graphics_mode()}

    if op == "android-status":
        _require(role, "owner", "profile", "kids")
        return _android_status()

    if op == "android-setup":
        # First start on a new install: Android is downloading.
        progress = ""
        try:
            with open("/var/lib/blidos/android-setup.log", errors="replace") as f:
                found = re.findall(r"\[Downloading\] ([0-9.]+) MB/([0-9.]+) MB", f.read()[-4000:])
            if found and float(found[-1][1]) > 0:
                progress = f"{float(found[-1][0]) / float(found[-1][1]) * 100:.0f}%"
        except (OSError, ValueError):
            pass
        return {"done": os.path.exists(ANDROID_READY), "progress": progress}

    if op == "android-tv":
        _require(role, "owner", "profile")
        if "on" in req:
            _require(role, "owner")
            _set_tv_mode(bool(req["on"]))
        return {"on": _tv_mode()}

    if op == "android-started":
        # Controllers connected before Android started: announce them again so Android sees them.
        _require(role, "owner", "profile", "kids")
        subprocess.run(["udevadm", "trigger", "--action=add", "--subsystem-match=input",
                        "--property-match=ID_INPUT_JOYSTICK=1"],
                       capture_output=True, timeout=30)
        return {}

    if op == "android-report":
        _require(role, "owner", "profile")
        return {"report": _android_report()}

    if op == "android-top":
        # Which Android app is in front, so BlidOS can come back when you leave an app.
        _require(role, "owner", "profile", "kids")
        out = _waydroid_shell("dumpsys activity activities | grep -m1 topResumedActivity").stdout
        m = re.search(r" ([A-Za-z0-9_.]+)/", out)
        pkg = m.group(1) if m else None
        return {"package": pkg, "home": pkg is None or pkg in ANDROID_HOMES}

    if op == "android-installed":
        # Apps the owner can hand to a Kids profile.
        _require(role, "owner")
        return {"packages": sorted(_owner_apks(name))}

    if op == "apply-kids":
        me = next((p for p in profiles if p["user"] == name), None)
        owner = next((p for p in profiles if p.get("owner")), None)
        if me and me.get("kids") and owner:
            _apply_kids(me, owner["user"])
        return {}

    if op == "gsf-id":
        _require(role, "owner", "profile")
        return {"id": _gsf_id(name)}

    if op == "drivers":
        _require(role, "owner")
        return {"drivers": _drivers()}

    if op == "install-driver":
        _require(role, "owner")
        d = DRIVERS[req["id"]]
        _run_job("drivers", _install_steps() + [_apt(["install"] + d["packages"])])
        return {}

    if op == "update-system":
        _require(role, "owner")
        _run_job("updates", _install_steps(upgrade=True))
        return {}

    if op == "check-updates":
        _require(role, "owner")
        try:
            return _check_updates()
        finally:
            _unmount_usb()

    if op == "install-updates":
        # Everything at once: the newer BlidOS from a USB drive (if chosen), then system updates.
        _require(role, "owner")
        source = req.get("blidos") or ""
        if source.startswith("https://"):
            # From GitHub: the file is downloaded and checked as the first install step.
            if source != _github.get("url"):
                raise ValueError("Check for updates again")
            steps = _install_steps([GITHUB_DEB], upgrade=True)
            steps.insert(1, _download_github_update)
        else:
            try:
                debs = [_cached_deb(_deb_details(source)["key"])] if source else []
            finally:
                _unmount_usb()
            steps = _install_steps(debs, upgrade=True)
        _run_job("updates", steps)
        return {}

    if op == "deb-files":
        _require(role, "owner")
        try:
            return {"files": _deb_files()}
        finally:
            _unmount_usb()

    if op == "deb-details":
        _require(role, "owner")
        try:
            return _deb_details(req["path"])
        finally:
            _unmount_usb()

    if op == "apk-fetch":
        _require(role, "owner")
        try:
            return {"path": _fetch_apk(req["path"], uid)}
        finally:
            _unmount_usb()

    if op == "install-deb":
        _require(role, "owner")
        _run_job("packages", _install_steps([_cached_deb(req["key"])]))
        return {}

    if op == "job":
        _require(role, "owner")
        job = _jobs.get(req["name"], {"running": False, "log": [], "ok": None})
        return {"running": job["running"], "succeeded": job["ok"], "log": job["log"][-40:]}

    raise ValueError(f"Unknown request {op!r}")


def _find(profiles, user):
    for p in profiles:
        if p["user"] == user:
            return p
    raise ValueError("No such profile")


def _group_exists(g):
    try:
        grp.getgrnam(g)
        return True
    except KeyError:
        return False


def _serve(conn):
    with conn:
        uid, name = _caller(conn)
        f = conn.makefile("rwb")
        for line in f:
            try:
                req = json.loads(line)
                resp = {**handle(req, uid, name), "ok": True}
            except Denied as e:
                resp = {"ok": False, "error": str(e)}
            except Exception as e:
                resp = {"ok": False, "error": str(e) or e.__class__.__name__}
            f.write((json.dumps(resp) + "\n").encode())
            f.flush()


def main():
    os.makedirs(os.path.dirname(SOCKET), exist_ok=True)
    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCKET)
    os.chmod(SOCKET, 0o666)  # anyone may connect; each request is checked against the caller
    srv.listen(16)
    _recover_installs()
    threading.Thread(target=_check_graphics_at_start, daemon=True).start()
    threading.Thread(target=_android_watchdog, daemon=True).start()
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=_serve, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
