package com.blidos.launcher.ui

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Drawable

data class AppEntry(
    val packageName: String,
    val label: String,
    val component: ComponentName,
    val banner: Drawable?,
    val icon: Drawable,
    val isTvApp: Boolean,
)

/** Finds installed apps, including anything downloaded from Google Play. */
object AppRepository {
    const val PLAY_STORE = "com.android.vending"
    val ADULT_ONLY = setOf(PLAY_STORE, "com.android.tv.settings", "com.android.settings")

    /** Android's own system screens. BlidOS has its own versions, so they never show as apps. */
    private val ANDROID_SYSTEM_APPS = setOf(
        "com.android.settings", "com.android.tv.settings", "com.android.traceur", "com.android.documentsui",
        "com.android.stk", "com.android.launcher3", "com.google.android.googlequicksearchbox",
        "com.android.dialer", "com.android.contacts", "com.android.messaging", "com.android.camera2",
    )

    fun load(context: Context): List<AppEntry> {
        val pm = context.packageManager
        val apps = LinkedHashMap<String, AppEntry>()
        // TV apps first so they win over the phone-style entry of the same package.
        for (category in arrayOf(Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER)) {
            val isTv = category == Intent.CATEGORY_LEANBACK_LAUNCHER
            @Suppress("DEPRECATION")
            val matches = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(category), 0)
            for (match in matches) {
                val info = match.activityInfo
                if (info.packageName == context.packageName || apps.containsKey(info.packageName)) continue
                if (info.packageName in ANDROID_SYSTEM_APPS) continue
                apps[info.packageName] = AppEntry(
                    packageName = info.packageName,
                    label = match.loadLabel(pm).toString(),
                    component = ComponentName(info.packageName, info.name),
                    banner = if (isTv) info.loadBanner(pm) ?: info.applicationInfo.loadBanner(pm) else null,
                    icon = match.loadIcon(pm),
                    isTvApp = isTv,
                )
            }
        }
        return apps.values.sortedWith(compareByDescending<AppEntry> { it.isTvApp }.thenBy { it.label.lowercase() })
    }

    fun launch(context: Context, app: AppEntry) {
        val category = if (app.isTvApp) Intent.CATEGORY_LEANBACK_LAUNCHER else Intent.CATEGORY_LAUNCHER
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(category)
            .setComponent(app.component)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        try {
            context.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            context.toast("Couldn't open ${app.label}")
        }
    }
}
