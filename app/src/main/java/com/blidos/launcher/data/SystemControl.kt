package com.blidos.launcher.data

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import android.util.Log

/**
 * System settings BlidOS changes itself, so nothing shows Android's own Settings screens.
 * Most of these need the privileged permissions the BlidOS PC image grants; each call fails quietly
 * (returning false) where they aren't available.
 */
class SystemControl(context: Context) {
    private val app = context.applicationContext
    private val resolver = app.contentResolver

    val isSystemApp: Boolean =
        app.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0

    // ---- Sound ----

    private val audio get() = app.getSystemService(AudioManager::class.java)

    val maxVolume: Int get() = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
    val volume: Int get() = audio.getStreamVolume(AudioManager.STREAM_MUSIC)

    fun setVolume(level: Int) {
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, level.coerceIn(0, maxVolume), AudioManager.FLAG_PLAY_SOUND)
    }

    var clickSounds: Boolean
        get() = Settings.System.getInt(resolver, Settings.System.SOUND_EFFECTS_ENABLED, 1) == 1
        set(on) {
            attempt("sound effects") {
                Settings.System.putInt(resolver, Settings.System.SOUND_EFFECTS_ENABLED, if (on) 1 else 0)
                if (on) audio.loadSoundEffects() else audio.unloadSoundEffects()
            }
        }

    // ---- Display and sleep ----

    var screenTimeoutMs: Int
        get() = Settings.System.getInt(resolver, Settings.System.SCREEN_OFF_TIMEOUT, 600_000)
        set(ms) {
            attempt("screen timeout") { Settings.System.putInt(resolver, Settings.System.SCREEN_OFF_TIMEOUT, ms) }
        }

    var fontScale: Float
        get() = Settings.System.getFloat(resolver, Settings.System.FONT_SCALE, 1f)
        set(scale) {
            attempt("font scale") { Settings.System.putFloat(resolver, Settings.System.FONT_SCALE, scale) }
        }

    /** Turns off Android's screensaver (which would show Android's clock). */
    fun disableScreensaver() {
        attempt("screensaver") {
            Settings.Secure.putInt(resolver, "screensaver_enabled", 0)
            Settings.Secure.putInt(resolver, "screensaver_activate_on_sleep", 0)
            Settings.Secure.putInt(resolver, "screensaver_activate_on_dock", 0)
        }
    }

    // ---- Date and time ----

    var use24Hour: Boolean
        get() = Settings.System.getString(resolver, Settings.System.TIME_12_24) == "24"
        set(on) {
            attempt("24 hour") { Settings.System.putString(resolver, Settings.System.TIME_12_24, if (on) "24" else "12") }
        }

    var autoTime: Boolean
        get() = Settings.Global.getInt(resolver, Settings.Global.AUTO_TIME, 1) == 1
        set(on) {
            attempt("auto time") { Settings.Global.putInt(resolver, Settings.Global.AUTO_TIME, if (on) 1 else 0) }
        }

    var autoTimeZone: Boolean
        get() = Settings.Global.getInt(resolver, Settings.Global.AUTO_TIME_ZONE, 1) == 1
        set(on) {
            attempt("auto zone") { Settings.Global.putInt(resolver, Settings.Global.AUTO_TIME_ZONE, if (on) 1 else 0) }
        }

    fun setTimeZone(id: String): Boolean = attempt("time zone") {
        autoTimeZone = false
        app.getSystemService(AlarmManager::class.java).setTimeZone(id)
        true
    } ?: false

    // ---- Power ----

    fun restart() {
        attempt("reboot") { app.getSystemService(PowerManager::class.java).reboot(null) }
    }

    fun shutDown() {
        attempt("shutdown") {
            PowerManager::class.java
                .getMethod("shutdown", Boolean::class.javaPrimitiveType, String::class.java, Boolean::class.javaPrimitiveType)
                .invoke(app.getSystemService(PowerManager::class.java), false, "BlidOS", false)
        }
    }

    // ---- Apps ----

    fun forceStop(packageName: String): Boolean = attempt("forceStop") {
        ActivityManager::class.java.getMethod("forceStopPackage", String::class.java)
            .invoke(app.getSystemService(ActivityManager::class.java), packageName)
        true
    } ?: false

    /** Uninstalls without Android's confirmation dialog (BlidOS asks first). */
    fun uninstall(packageName: String): Boolean = attempt("uninstall") {
        val sender = PendingIntent.getBroadcast(
            app, packageName.hashCode(), Intent("com.blidos.launcher.UNINSTALLED").setPackage(app.packageName),
            PendingIntent.FLAG_IMMUTABLE,
        ).intentSender
        app.packageManager.packageInstaller.uninstall(packageName, sender)
        true
    } ?: false

    fun isUserApp(packageName: String): Boolean =
        try {
            app.packageManager.getApplicationInfo(packageName, 0).flags and ApplicationInfo.FLAG_SYSTEM == 0
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }

    // ---- Bluetooth ----

    /** Unpairs a device, like "Forget" in Android's Bluetooth settings. */
    fun forgetDevice(device: BluetoothDevice): Boolean = attempt("removeBond") {
        BluetoothDevice::class.java.getMethod("removeBond").invoke(device) as Boolean
    } ?: false

    // ---- Storage and device info ----

    data class Storage(val totalBytes: Long, val freeBytes: Long)

    fun storage(): Storage {
        val stat = StatFs(app.filesDir.absolutePath)
        return Storage(stat.totalBytes, stat.availableBytes)
    }

    val deviceName: String get() = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
    val androidVersion: String get() = Build.VERSION.RELEASE

    private fun <T> attempt(what: String, block: () -> T): T? =
        try {
            block()
        } catch (e: Exception) {
            Log.w("BlidOS/System", "$what failed", (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e)
            null
        }
}
