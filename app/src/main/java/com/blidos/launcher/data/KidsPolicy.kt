package com.blidos.launcher.data

import android.content.Context
import android.content.Intent
import com.blidos.launcher.ui.AppRepository

/**
 * Runs inside a Kids profile's own Android user. Makes the apps a parent allowed available and hides
 * every other app, so it can't be opened from anywhere, not just the home screen.
 */
object KidsPolicy {
    private const val PREFS = "kids_policy"
    private const val KEY_HIDDEN = "hidden"

    fun apply(context: Context, profile: Profile, users: UserControl) {
        if (!users.isAvailable) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val allowed = profile.allowedApps - AppRepository.ADULT_ONLY

        for (pkg in allowed) {
            if (!isInstalled(context, pkg)) users.installExisting(pkg)
            users.setAppHidden(pkg, false)
        }

        // Hidden apps drop out of the launchable list, so carry forward what was hidden last time.
        val previouslyHidden = prefs.getStringSet(KEY_HIDDEN, emptySet()).orEmpty()
        val toHide = (launchablePackages(context) + previouslyHidden + AppRepository.ADULT_ONLY) -
            allowed - context.packageName
        toHide.forEach { users.setAppHidden(it, true) }
        prefs.edit().putStringSet(KEY_HIDDEN, toHide).apply()
    }

    private fun isInstalled(context: Context, pkg: String) =
        try {
            context.packageManager.getApplicationInfo(pkg, 0)
            true
        } catch (_: Exception) {
            false
        }

    @Suppress("DEPRECATION")
    private fun launchablePackages(context: Context): Set<String> =
        arrayOf(Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER).flatMap { category ->
            context.packageManager
                .queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(category), 0)
                .map { it.activityInfo.packageName }
        }.toSet()
}
