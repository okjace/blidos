package com.blidos.launcher.data

import org.json.JSONArray
import org.json.JSONObject

data class Profile(
    val id: String,
    val name: String,
    val colorIndex: Int,
    val isOwner: Boolean = false,
    val isKids: Boolean = false,
    val pinHash: String? = null,
    val pinSalt: String? = null,
    /** Packages a Kids profile may open. Ignored for regular profiles. */
    val allowedApps: Set<String> = emptySet(),
    /** The Android user that holds this profile's apps, data and Google account. Null when profiles share one user. */
    val userId: Int? = null,
) {
    val hasPin: Boolean get() = pinHash != null && pinSalt != null

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("colorIndex", colorIndex)
        put("isOwner", isOwner)
        put("isKids", isKids)
        put("pinHash", pinHash)
        put("pinSalt", pinSalt)
        put("allowedApps", JSONArray(allowedApps.toList()))
        put("userId", userId)
    }

    /** Everything except the PIN, for BlidOS running in this profile's own Android user. */
    fun toPublicJson(): JSONObject = toJson().apply {
        remove("pinHash")
        remove("pinSalt")
        put("hasPin", hasPin)
    }

    companion object {
        fun fromJson(json: JSONObject): Profile {
            val apps = json.optJSONArray("allowedApps") ?: JSONArray()
            return Profile(
                id = json.getString("id"),
                name = json.getString("name"),
                colorIndex = json.optInt("colorIndex", 0),
                isOwner = json.optBoolean("isOwner", false),
                isKids = json.optBoolean("isKids", false),
                pinHash = if (json.isNull("pinHash")) null else json.getString("pinHash"),
                pinSalt = if (json.isNull("pinSalt")) null else json.getString("pinSalt"),
                allowedApps = (0 until apps.length()).map { apps.getString(it) }.toSet(),
                userId = if (json.isNull("userId")) null else json.getInt("userId"),
            )
        }
    }
}
