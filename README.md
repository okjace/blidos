# BlidOS

BlidOS comes in two forms:

- **BlidOS for PCs**: a TV operating system built on Linux (Debian 13). It has its own full-screen interface, profiles with PINs, and runs Android and Android TV apps with Google Play. You install drivers the normal Linux way. See [BlidOS for PCs](#blidos-for-pcs).
- **The BlidOS app**: a home screen ("launcher") you can install on an existing Android TV or Google TV.

## BlidOS for PCs

| Part | What it is |
|---|---|
| Base | Debian 13 with firmware for Intel, AMD, NVIDIA, Realtek, Broadcom, MediaTek and Atheros hardware, plus Broadcom's own Wi-Fi driver (`wl`) for MacBooks (e.g. MacBook Air 2013–2017) |
| Profiles | Each profile is a Linux user, and its 4-digit PIN is that user's password. Five wrong PINs lock it for a minute |
| Interface | The BlidOS home screen, profile picker and settings: full screen and remote-friendly, written in Python and Qt/QML |
| Android apps | [Waydroid](https://waydro.id) running Android 13 with Google Play. Apps that have an Android TV screen open in it. Each profile has its own Android apps and Google account |
| App Store | Linux apps and games from Flathub, made for the remote. Each profile has its own apps |
| Desktop mode | A full KDE Plasma desktop for mouse and keyboard, one click away from the TV home screen |
| Installer | A graphical installer (Calamares) that installs to the partition you pick, next to Windows |

**Install it:**

1. Download the ISO from [Releases](https://github.com/okjace/blidos/releases). If it's in parts, join them as the release notes say. Write `BlidOS-<version>-x86_64.iso` to a USB stick of at least 4 GB with [balenaEtcher](https://etcher.balena.io/), Rufus (DD mode) or Ventoy.
2. In your PC's firmware settings, turn off **Secure Boot**. Then boot from the USB stick.
3. Choose **Install BlidOS**. To look around first, choose **Try BlidOS**.
4. Pick where BlidOS goes: alongside another system, a partition you choose, the whole disk, or your own partitions. BlidOS needs at least 16 GB.
5. Restart. The boot menu lists BlidOS, plus Windows if it's installed.

**First start:** BlidOS setup asks for your name and PIN, connects to the internet, and lets you add the other people who use the TV, including Kids profiles.

**Drivers and other software:**

- **Settings → Drivers** detects NVIDIA graphics and Broadcom Wi-Fi and installs the right drivers.
- **Settings → Install a package** installs `.deb` files (drivers and Linux apps, along with anything they need) and `.apk` files (Android apps) from a USB drive or a Downloads folder.
- The owner profile can also use `sudo` in the Terminal (Settings → Terminal). The password is the owner's PIN, and the username is `profile1`.

**Updates:** Settings → Updates installs everything with one button. That covers new BlidOS versions and system updates from the internet (security fixes, drivers, the kernel). BlidOS finds new versions in three places:

- online, in this repository's [Releases](https://github.com/okjace/blidos/releases) (0.5.1 and newer; the owner gets a notice after signing in);
- on a USB stick written from a newer BlidOS ISO (0.5.1 and newer);
- as a `blidos_<version>_all.deb` file on a USB stick (FAT32 or exFAT) or in Downloads. This works on every version, so older versions update this way.

Profiles, Android apps and files are never touched, because:

- BlidOS is a single package (`blidos`), so an update replaces only BlidOS's own files;
- an install that would remove any installed package is stopped instead;
- installing needs 1.5 GB free, so it can't run out of space halfway;
- a copy of the profile list and system settings is saved to `/var/backups/blidos` first;
- if the power goes out during an install, BlidOS finishes it at the next start.

**App Store:** the App Store tile on the home screen lists popular apps and games from Flathub, by category, with search. Apps install for the current profile only and appear on the home screen. Kids profiles don't get the App Store.

**Desktop mode:** the Desktop mode tile switches the profile to KDE Plasma (Dolphin, Konsole, Firefox, Discover). Android stops while you're there. The "BlidOS TV mode" icon on the desktop switches back. A profile starts in whichever mode it used last. Kids profiles stay in TV mode.

**Android apps and Android TV apps:** Google Play installs Android apps, and apps that have an Android TV screen (YouTube, Netflix, Spotify, Plex and many more) open in it.

For TV-only apps, turn on **Settings → Android and Google Play → Android TV mode**. Android then runs as a real Android TV, with its TV system screens, and TV-only apps install and run. Install them from `.apk` files with Settings → Install a package. The Google Play included here is the phone edition, which refuses to open on a TV. To use Google Play in Android TV mode, install the **Google Play Store (Android TV)** app file the same way. Android only accepts it if Google signed it.

How it works: this Android (LineageOS 20) is a tablet build. Marked as a TV, it switches to its TV system screens, which have no phone lock screen to draw on, and they crashed over and over: that was the black-screen bug in 0.3. In TV mode, BlidOS adds an overlay that runs Android without its lock screen (profiles have BlidOS PINs). See `os/android-tv/`.

**If Android apps still show black:** BlidOS waits until Android has finished starting before it opens an app, and on every start it checks the graphics chip to choose how Android draws. On some chips another setting works better: Settings → Android and Google Play → Graphics → **Compatible** (or **Software**). "Save a problem report" writes `~/blidos-android-report.txt` with the graphics chip and Android's errors.

**Android on first start:** the ISO doesn't include Android, because its image contains Google's apps, which can't be redistributed. On a new install, BlidOS downloads Android with Google Play from Waydroid's servers (about 1 GB) as soon as it's online. The home screen shows the progress, and Android apps work once it's done.

**Google Play:** BlidOS isn't a Google-certified device, so each profile needs a one-time registration. Settings → Android and Google Play shows the device ID to enter at google.com/android/uncertified. Some streaming apps (Netflix, for example) play at lower quality on uncertified devices.

**Controllers:** Xbox (USB cable or Bluetooth), PlayStation 3/4/5, Switch Pro and Joy-Con, Steam and most other USB or Bluetooth controllers work in games, in Android apps and on the BlidOS screens. On BlidOS screens, the D-pad or left stick moves, A (Cross) selects and B (Circle) goes back. The Xbox, PS or Home button goes back to the home screen from anywhere. Settings → Controllers lists connected controllers with their battery level and explains pairing. Microsoft's USB Xbox Wireless Adapter isn't supported yet (Debian has no driver for it), so connect those controllers by cable or Bluetooth instead.

**Kids profiles:** in Settings → Profiles → the kid → Apps and permissions, the owner chooses:

- **Android apps** from the owner's Google Play installs. BlidOS copies them into the kid's Android and turns everything else off.
- **Linux apps**: App Store apps (BlidOS installs them for everyone once allowed) and other installed programs, such as Firefox.
- **What they can do**, all off until allowed: Google Play (install their own Android apps), the App Store, Desktop mode, Settings (Wi-Fi, Bluetooth, sound, display), and restart and shut down.

**Build it:** `os/build-os.sh` builds the ISO without root (Debian in a user namespace). The steps are `packages` (Debian and all packages), `system` (BlidOS and the Android images) and `iso`. The `system` step also writes `blidos_<version>_all.deb`, the BlidOS update file, next to the ISO. To release an update, raise the version in `os/rootfs/etc/blidos-version` and run `os/build-os.sh system`. The code:

- `os/blidos/`: the interface (`qml/`), the root service `daemon.py` (profiles, PINs, Kids rules, drivers, updates) and system helpers;
- `os/rootfs/`: system configuration (greetd, sway session, PAM lockout, permissions, Waydroid setup, boot splash);
- `os/installer/`: installer configuration;
- `os/debian/`: how BlidOS is packaged (`control`, and the install scripts that run on every update).

`os/tools/preview.py` renders any screen with sample data, so you can check the interface without a PC.

**Status:** tested in a VM. Setup, PIN sign-in and lockout, the home screen, settings, and Android starting with Google Play installed all work. Not yet tested: real hardware, legacy BIOS, and a full Google sign-in.

## The BlidOS app (Android TV and Google TV)

The app replaces the stock TV home screen and adds:

- **Profiles with PINs.** A "Who's watching?" screen on startup, up to 6 profiles, and optional 4-digit PINs entered with the remote. PINs are stored only as salted PBKDF2 hashes. Five wrong tries lock the profile for 60 seconds, and turning the TV off signs the current profile out.
- **Kids profiles.** The Owner picks which apps a Kids profile can see. Kids profiles have no access to Google Play, Wi-Fi, Bluetooth, system settings, or profile management.
- **Google Play.** Google Play is the first tile in the Apps row. Every installed app, including ones you download from Play, shows up automatically, using its TV banner when it has one.
- **Wi-Fi.** See nearby networks, signal strength and the current connection, and join a network with a password.
- **Bluetooth.** See paired devices, search for nearby ones, and pair remotes, game controllers, keyboards, headphones and speakers.

Only the Owner profile can manage profiles and open system settings. The first time BlidOS starts it creates an **Owner** profile with no PIN. Set one under **Settings → Profiles**.

## Why it's a launcher and not a whole new OS

Google Play and Google Play Services are licensed only to Google-certified devices. A custom Android TV build (an AOSP fork) can't legally include Play unless Google certifies it. BlidOS runs as the home screen on a certified Android TV or Google TV device, so Google Play, Wi-Fi drivers and Bluetooth stacks come from that device and keep working.

If you later make your own device image, you can build BlidOS into it as the system home app. See [Building it into a system image](#building-it-into-a-system-image).

## Build

You need **JDK 17** and the **Android SDK (platform 34)**. The easiest way to get both is [Android Studio](https://developer.android.com/studio):

1. **File → Open** and choose this folder. Android Studio downloads Gradle 8.7 and the SDK pieces it needs.
2. Choose **Build → Build APK(s)**. The APK lands in `app/build/outputs/apk/debug/`.

To build from the command line instead, create the Gradle wrapper once, with Gradle 8.7 or newer installed:

```bash
gradle wrapper --gradle-version 8.7
```

```bash
./gradlew assembleDebug
```

## Install on a TV

1. On the TV, open **Settings → Device Preferences → About** and select **Build** 7 times to turn on Developer options.
2. Turn on **Developer options → USB debugging** (and **Network debugging** if your TV has it).
3. Connect and install:

```bash
adb connect <tv-ip-address>
```

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

4. Press **Home** on the remote. If the TV asks which home app to use, choose **BlidOS → Always**.

Google TV and most newer Android TV builds don't offer that choice. On those you have to turn off the stock launcher. This is reversible.

```bash
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
```

That's the Google TV launcher. On older Android TV builds the stock launcher is `com.google.android.tvlauncher`. To bring the stock launcher back:

```bash
adb shell pm enable com.google.android.apps.tv.launcherx
```

## Notes and limits

- **Wi-Fi on Android 10+.** Android only lets the system turn Wi-Fi on or off, so the toggle opens the TV's Wi-Fi settings. On Android 11+, joining a network shows a system prompt that saves and connects it. Enterprise (EAP) and WEP networks have to be joined from the TV's own settings.
- **Location permission.** Android requires location access to list Wi-Fi networks. BlidOS asks for it the first time you open Wi-Fi.
- **Bluetooth on Android 13+.** Bluetooth can be turned on from BlidOS, but turning it off and unpairing happen in the TV's Bluetooth settings.
- **Profile locking.** A profile stays signed in until you switch profiles or the TV turns off. An app that's already open when the TV wakes keeps running. The lock applies the next time you go Home.
- **Kids mode** controls what the home screen shows. It doesn't block apps opened another way, for example a link inside an allowed app. For stronger limits, combine it with the TV's own parental controls.

## Building it into a system image

If you build your own AOSP Android TV image (without Google Play), you can make BlidOS the default home app:

1. Add the APK as a prebuilt in your device tree (`Android.bp` with `android_app_import`, `privileged: true`, `overrides: ["TvLauncher"]`), and add `BlidOS` to `PRODUCT_PACKAGES`.
2. As a privileged or platform-signed app, it could then toggle Wi-Fi and Bluetooth directly and forget networks or devices. Those calls are blocked for regular apps, so this version doesn't use them.

## Project layout

```
app/src/main/java/com/blidos/launcher/
  BlidApp.kt               Session state; signs out when the screen turns off
  data/Profile.kt          Profile model and JSON storage format
  data/ProfileStore.kt     Saving profiles, PIN checks and lockout
  data/PinHasher.kt        Salted PBKDF2 PIN hashing
  ui/HomeActivity.kt       The home screen: apps, Google Play, settings row
  ui/ProfilePickerActivity "Who's watching?" screen
  ui/ProfilesActivity.kt   Owner screen: add, rename, PIN, Kids mode, delete
  ui/PinDialog.kt          Remote-friendly PIN keypad
  ui/WifiActivity.kt       Wi-Fi networks and joining
  ui/BluetoothActivity.kt  Bluetooth pairing
  ui/AppRepository.kt      Finding and launching installed apps
  ui/UiKit.kt              Shared colors, tiles and focus effects
```
