# Android TV mode overlay

`BlidOSTvOverlay.apk` lets BlidOS's Android (LineageOS 20, a tablet build) run as an Android TV:
with the TV feature on, Android uses its TV system screens, which have nowhere to draw the phone
lock screen. The overlay points Android's lock screen service at a component that doesn't exist,
so Android runs without one (BlidOS profiles have their own PINs).

The built APK is in `os/rootfs/usr/share/blidos/android-tv/`. To rebuild it you need `aapt2`
(Android SDK build tools, or Google's Maven `com.android.tools.build:aapt2` jar) and the image's
`framework-res.apk`:

```bash
aapt2 compile --dir os/android-tv/res -o res.zip
aapt2 link -o unsigned.apk -I framework-res.apk --manifest os/android-tv/AndroidManifest.xml res.zip
os/tools/sign-apk.py os/android-tv/signing-key.pem os/android-tv/signing-cert.pem unsigned.apk os/rootfs/usr/share/blidos/android-tv/BlidOSTvOverlay.apk
```
