package com.blidos.launcher.data

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Process
import android.os.UserHandle
import android.os.UserManager
import android.provider.Settings
import android.util.Log

/**
 * Android multi-user controls, so every BlidOS profile gets its own Android user:
 * separate app data, Google accounts and Play Store installs.
 *
 * These are system APIs. They only work when BlidOS ships as a privileged system app
 * (the BlidOS PC image grants the permissions in privapp-permissions-blidos.xml).
 * Everywhere else [isAvailable] is false and profiles share one Android user.
 */
class UserControl(context: Context) {
    private val app = context.applicationContext
    private val um = app.getSystemService(UserManager::class.java)
    private val am = app.getSystemService(ActivityManager::class.java)

    val myUserId: Int = idOf(Process.myUserHandle())
    val isSystemUser: Boolean get() = myUserId == 0

    val isAvailable: Boolean by lazy {
        app.checkSelfPermission(MANAGE_USERS) == PackageManager.PERMISSION_GRANTED &&
            UserManager.supportsMultipleUsers()
    }

    /** Creates a full Android user for a profile. Returns its user id, or null if that isn't possible. */
    fun createUser(name: String): Int? = attempt("createUser") {
        val created = UserManager::class.java
            .getMethod("createUser", String::class.java, String::class.java, Int::class.javaPrimitiveType)
            .invoke(um, name, USER_TYPE_SECONDARY, 0)
        // Android 13 returns a UserInfo here; some versions return a UserHandle.
        when (created) {
            is UserHandle -> idOf(created)
            null -> null
            else -> created.javaClass.getField("id").getInt(created)
        }
    }

    fun removeUser(userId: Int): Boolean = attempt("removeUser") {
        UserManager::class.java.getMethod("removeUser", UserHandle::class.java)
            .invoke(um, handleOf(userId)) as Boolean
    } ?: false

    fun userExists(userId: Int): Boolean = attempt("getUserInfo") {
        UserManager::class.java.getMethod("getUserInfo", Int::class.javaPrimitiveType).invoke(um, userId) != null
    } ?: false

    fun setUserName(userId: Int, name: String) {
        attempt("setUserName") {
            UserManager::class.java.getMethod("setUserName", Int::class.javaPrimitiveType, String::class.java)
                .invoke(um, userId, name)
        }
    }

    /** Brings another profile's Android user to the screen. */
    fun switchTo(userId: Int): Boolean = attempt("switchUser") {
        ActivityManager::class.java.getMethod("switchUser", UserHandle::class.java)
            .invoke(am, handleOf(userId)) as Boolean
    } ?: false

    /** The Android user that's on screen right now. */
    fun currentUserId(): Int? = attempt("getCurrentUser") {
        ActivityManager::class.java.getMethod("getCurrentUser").invoke(null) as Int
    }

    fun setRestriction(userId: Int, key: String, value: Boolean) {
        attempt("setUserRestriction") {
            UserManager::class.java
                .getMethod("setUserRestriction", String::class.java, Boolean::class.javaPrimitiveType, UserHandle::class.java)
                .invoke(um, key, value, handleOf(userId))
        }
    }

    /** Hides or shows an app for the user BlidOS is running in. Hidden apps can't be opened at all. */
    fun setAppHidden(packageName: String, hidden: Boolean) {
        attempt("setApplicationHiddenSettingAsUser") {
            PackageManager::class.java.getMethod(
                "setApplicationHiddenSettingAsUser",
                String::class.java, Boolean::class.javaPrimitiveType, UserHandle::class.java,
            ).invoke(app.packageManager, packageName, hidden, Process.myUserHandle())
        }
    }

    /** Makes an app that's installed for another profile available in this one too. */
    fun installExisting(packageName: String): Boolean = attempt("installExistingPackage") {
        PackageManager::class.java.getMethod("installExistingPackage", String::class.java)
            .invoke(app.packageManager, packageName)
        true
    } ?: false

    /** Hides Android's own user switcher, so only BlidOS (with its PINs) can change profiles. */
    fun hideSystemUserSwitcher() {
        attempt("user_switcher_enabled") { Settings.Global.putInt(app.contentResolver, "user_switcher_enabled", 0) }
    }

    /** What the tablet setup wizard normally does when it finishes. */
    fun markSetupComplete(wholeDevice: Boolean) {
        attempt("provisioning") {
            if (wholeDevice) Settings.Global.putInt(app.contentResolver, Settings.Global.DEVICE_PROVISIONED, 1)
            Settings.Secure.putInt(app.contentResolver, "user_setup_complete", 1)
        }
    }

    fun isDeviceProvisioned(): Boolean =
        Settings.Global.getInt(app.contentResolver, Settings.Global.DEVICE_PROVISIONED, 0) == 1

    fun isUserSetupComplete(): Boolean =
        Settings.Secure.getInt(app.contentResolver, "user_setup_complete", 0) == 1

    private fun <T> attempt(what: String, block: () -> T): T? =
        try {
            block()
        } catch (e: Exception) {
            Log.w(TAG, "$what failed", (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e)
            null
        }

    companion object {
        private const val TAG = "BlidOS/Users"
        const val MANAGE_USERS = "android.permission.MANAGE_USERS"
        private const val USER_TYPE_SECONDARY = "android.os.usertype.full.SECONDARY"

        val KIDS_RESTRICTIONS = listOf(
            UserManager.DISALLOW_INSTALL_UNKNOWN_SOURCES,
            UserManager.DISALLOW_UNINSTALL_APPS,
            UserManager.DISALLOW_ADD_USER,
            UserManager.DISALLOW_REMOVE_USER,
            UserManager.DISALLOW_FACTORY_RESET,
            UserManager.DISALLOW_DEBUGGING_FEATURES,
        )

        fun idOf(handle: UserHandle): Int =
            try {
                UserHandle::class.java.getMethod("getIdentifier").invoke(handle) as Int
            } catch (_: Exception) {
                handle.hashCode()
            }

        fun handleOf(userId: Int): UserHandle =
            UserHandle::class.java.getMethod("of", Int::class.javaPrimitiveType).invoke(null, userId) as UserHandle
    }
}
