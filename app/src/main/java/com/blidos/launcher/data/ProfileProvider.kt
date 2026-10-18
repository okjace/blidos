package com.blidos.launcher.data

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Binder
import android.os.Bundle
import android.os.Process
import com.blidos.launcher.Session

/**
 * Lives in Android user 0, where the profile list and PINs are kept. BlidOS running in a profile's own
 * Android user asks it for that profile's settings (never the PIN), and asks it to lock before
 * switching back to the profile picker.
 */
class ProfileProvider : ContentProvider() {
    override fun onCreate() = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        // Only BlidOS itself (in any Android user) may ask.
        if (Binder.getCallingUid() % PER_USER_RANGE != Process.myUid() % PER_USER_RANGE) {
            throw SecurityException("Not allowed")
        }
        val store = ProfileStore(context!!)
        return when (method) {
            METHOD_PROFILE_FOR_USER -> Bundle().apply {
                val profile = arg?.toIntOrNull()?.let(store::forUser)
                putString(KEY_JSON, profile?.toPublicJson()?.toString())
            }
            METHOD_LOCK -> {
                Session.lock()
                Bundle.EMPTY
            }
            else -> null
        }
    }

    override fun query(uri: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, s: String?, a: Array<out String>?) = 0
    override fun update(uri: Uri, v: ContentValues?, s: String?, a: Array<out String>?) = 0

    companion object {
        private const val AUTHORITY = "com.blidos.launcher.profiles"
        private const val PER_USER_RANGE = 100_000
        private const val METHOD_PROFILE_FOR_USER = "profileForUser"
        private const val METHOD_LOCK = "lock"
        private const val KEY_JSON = "json"

        /** Talks to the provider in Android user 0, wherever BlidOS is running. */
        private fun callOwner(context: Context, method: String, arg: String?): Bundle? =
            try {
                context.contentResolver.call(Uri.parse("content://0@$AUTHORITY"), method, arg, null)
            } catch (e: Exception) {
                android.util.Log.w("BlidOS/Profiles", "call $method failed", e)
                null
            }

        fun profileForUser(context: Context, userId: Int): Profile? =
            callOwner(context, METHOD_PROFILE_FOR_USER, userId.toString())
                ?.getString(KEY_JSON)
                ?.let { Profile.fromJson(org.json.JSONObject(it)) }

        fun lockOwnerSession(context: Context) {
            callOwner(context, METHOD_LOCK, null)
        }
    }
}
