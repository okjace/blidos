package com.blidos.launcher.data

import android.content.Context
import org.json.JSONArray
import java.util.UUID

sealed interface PinCheck {
    object Ok : PinCheck
    data class Wrong(val attemptsLeft: Int) : PinCheck
    data class LockedOut(val seconds: Long) : PinCheck
}

/** Saves profiles in the launcher's private storage. There is always exactly one Owner profile. */
class ProfileStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("profiles", Context.MODE_PRIVATE)
    private val attempts = context.applicationContext.getSharedPreferences("pin_attempts", Context.MODE_PRIVATE)

    fun all(): List<Profile> {
        val raw = prefs.getString(KEY_PROFILES, null)
        if (raw == null) {
            val owner = Profile(id = newId(), name = "Owner", colorIndex = 0, isOwner = true)
            write(listOf(owner))
            return listOf(owner)
        }
        val array = JSONArray(raw)
        return List(array.length()) { Profile.fromJson(array.getJSONObject(it)) }
    }

    fun get(id: String): Profile? = all().firstOrNull { it.id == id }

    fun forUser(userId: Int): Profile? =
        all().firstOrNull { it.userId == userId } ?: if (userId == 0) owner() else null

    fun owner(): Profile = all().first { it.isOwner }

    /** True once the BlidOS first-boot setup has been finished. */
    var isSetupDone: Boolean
        get() = prefs.getBoolean(KEY_SETUP_DONE, false)
        set(value) = prefs.edit().putBoolean(KEY_SETUP_DONE, value).apply()

    fun canAdd(): Boolean = all().size < MAX_PROFILES

    fun add(name: String, userId: Int? = null): Profile {
        val list = all()
        val profile = Profile(id = newId(), name = name, colorIndex = list.size, userId = userId)
        write(list + profile)
        return profile
    }

    fun edit(id: String, transform: (Profile) -> Profile) {
        write(all().map { if (it.id == id) transform(it) else it })
    }

    fun setPin(id: String, pin: String) {
        val salt = PinHasher.newSalt()
        val hash = PinHasher.hash(pin, salt)
        edit(id) { it.copy(pinSalt = salt, pinHash = hash) }
        clearAttempts(id)
    }

    fun clearPin(id: String) {
        edit(id) { it.copy(pinSalt = null, pinHash = null) }
        clearAttempts(id)
    }

    fun delete(id: String) {
        write(all().filterNot { it.id == id && !it.isOwner })
        clearAttempts(id)
    }

    /** Checks a PIN, locking the profile for a minute after too many wrong tries. */
    fun checkPin(id: String, pin: String): PinCheck {
        val profile = get(id) ?: return PinCheck.Wrong(0)
        val salt = profile.pinSalt
        val hash = profile.pinHash
        if (salt == null || hash == null) return PinCheck.Ok

        val now = System.currentTimeMillis()
        val lockedUntil = attempts.getLong("${id}_until", 0L)
        if (lockedUntil > now) return PinCheck.LockedOut((lockedUntil - now + 999) / 1000)

        if (PinHasher.verify(pin, salt, hash)) {
            clearAttempts(id)
            return PinCheck.Ok
        }

        val fails = attempts.getInt("${id}_fails", 0) + 1
        if (fails >= MAX_ATTEMPTS) {
            attempts.edit()
                .putInt("${id}_fails", 0)
                .putLong("${id}_until", now + LOCKOUT_MS)
                .apply()
            return PinCheck.LockedOut(LOCKOUT_MS / 1000)
        }
        attempts.edit().putInt("${id}_fails", fails).apply()
        return PinCheck.Wrong(MAX_ATTEMPTS - fails)
    }

    private fun clearAttempts(id: String) {
        attempts.edit().remove("${id}_fails").remove("${id}_until").apply()
    }

    private fun write(list: List<Profile>) {
        prefs.edit().putString(KEY_PROFILES, JSONArray(list.map { it.toJson() }).toString()).apply()
    }

    companion object {
        const val MAX_PROFILES = 6
        const val PIN_LENGTH = 4
        private const val MAX_ATTEMPTS = 5
        private const val LOCKOUT_MS = 60_000L
        private const val KEY_PROFILES = "profiles"
        private const val KEY_SETUP_DONE = "setup_done"

        private fun newId() = UUID.randomUUID().toString()
    }
}
