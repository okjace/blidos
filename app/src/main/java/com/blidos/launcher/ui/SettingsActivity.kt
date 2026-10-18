package com.blidos.launcher.ui

import android.accounts.AccountManager
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.ConnectivityManager
import android.os.Bundle
import android.provider.Settings
import android.text.format.Formatter
import android.view.KeyEvent
import android.widget.LinearLayout
import android.widget.ScrollView
import com.blidos.launcher.Session
import com.blidos.launcher.data.PinCheck
import com.blidos.launcher.data.Profile
import com.blidos.launcher.data.ProfileProvider
import com.blidos.launcher.data.ProfileStore
import com.blidos.launcher.data.SystemControl
import com.blidos.launcher.data.UserControl
import java.util.TimeZone

/** BlidOS's own settings, in place of Android's Settings app. Not available in Kids profiles. */
class SettingsActivity : Activity() {
    private lateinit var store: ProfileStore
    private lateinit var users: UserControl
    private lateinit var system: SystemControl
    private lateinit var body: LinearLayout
    private var profile: Profile? = null
    private val pages = ArrayDeque<() -> Unit>()
    private var focusNextRow = false

    private val isOwner get() = users.isSystemUser && profile?.isOwner == true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = ProfileStore(this)
        users = UserControl(this)
        system = SystemControl(this)
        profile = if (users.isSystemUser) Session.profileId?.let(store::get)
        else ProfileProvider.profileForUser(this, users.myUserId)
        if (profile == null || profile?.isKids == true) {
            finish()
            return
        }

        body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(64), dp(40), dp(64), dp(40))
            clipChildren = false
            clipToPadding = false
        }
        setContentView(ScrollView(this).apply {
            background = screenBackground()
            isFillViewport = true
            clipChildren = false
            addView(body)
        })
        open(::mainPage)
    }

    override fun onResume() {
        super.onResume()
        pages.lastOrNull()?.invoke()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && pages.size > 1) {
            pages.removeLast()
            pages.last()()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun open(page: () -> Unit) {
        pages.addLast(page)
        page()
    }

    private fun refresh() = pages.last()()

    private fun page(title: String, subtitle: String? = null) {
        body.removeAllViews()
        body.addView(label(title, 34f, bold = true))
        subtitle?.let { body.addView(label(it, 17f, Palette.TEXT_DIM).apply { setPadding(0, dp(8), 0, dp(8)) }) }
        body.addView(android.view.View(this), LinearLayout.LayoutParams(1, dp(16)))
        focusNextRow = true
    }

    private fun row(title: String, detail: String = "", onClick: () -> Unit) {
        val view = listRow(title, detail, onClick)
        body.addView(view)
        if (focusNextRow) {
            view.requestFocus()
            focusNextRow = false
        }
    }

    private fun onOff(value: Boolean) = if (value) "On" else "Off"

    // ---- Pages ----

    private fun mainPage() {
        page("Settings", "Signed in as ${profile?.name}")
        row("Wi-Fi") { startActivity(Intent(this, WifiActivity::class.java)) }
        row("Bluetooth") { startActivity(Intent(this, BluetoothActivity::class.java)) }
        row("Sound", "Volume ${system.volume} of ${system.maxVolume}") { open(::soundPage) }
        row("Display and sleep") { open(::displayPage) }
        row("Date and time", TimeZone.getDefault().id.replace('_', ' ')) { open(::timePage) }
        row("Apps") { open(::appsPage) }
        row("Google accounts", googleAccounts().firstOrNull() ?: "Not signed in") { open(::accountsPage) }
        row("Storage", "${Formatter.formatShortFileSize(this, system.storage().freeBytes)} free") { open(::storagePage) }
        if (isOwner) row("Profiles", "PINs and Kids mode") { startActivity(Intent(this, ProfilesActivity::class.java)) }
        row("About BlidOS") { open(::aboutPage) }
        row("Restart") { confirm("Restart now?", "Restart") { system.restart() } }
        row("Shut down") { confirm("Shut down now?", "Shut down") { system.shutDown() } }
        if (isOwner && users.isAvailable) row("Reset profiles", "Remove everyone and start setup again") { resetProfiles() }
    }

    private fun soundPage() {
        page("Sound")
        row("Volume", "${system.volume} of ${system.maxVolume}") {}
        body.addView(buttonRow(
            pillButton("Quieter") { system.setVolume(system.volume - 1); refresh() },
            pillButton("Louder") { system.setVolume(system.volume + 1); refresh() },
            pillButton("Mute") { system.setVolume(0); refresh() },
        ))
        row("Click sounds", onOff(system.clickSounds)) { system.clickSounds = !system.clickSounds; refresh() }
    }

    private fun displayPage() {
        page("Display and sleep")
        body.addView(sectionHeader("Turn the screen off after"))
        val timeouts = listOf(
            "5 minutes" to 300_000, "15 minutes" to 900_000, "30 minutes" to 1_800_000,
            "1 hour" to 3_600_000, "4 hours" to 14_400_000, "Never" to Int.MAX_VALUE,
        )
        timeouts.forEach { (name, ms) ->
            row(name, if (system.screenTimeoutMs == ms) "Selected" else "") { system.screenTimeoutMs = ms; refresh() }
        }
        body.addView(sectionHeader("Text size"))
        listOf("Small" to 0.85f, "Default" to 1f, "Large" to 1.15f, "Largest" to 1.3f).forEach { (name, scale) ->
            row(name, if (kotlin.math.abs(system.fontScale - scale) < 0.01f) "Selected" else "") {
                system.fontScale = scale
                refresh()
            }
        }
    }

    private fun timePage() {
        page("Date and time")
        row("Set time automatically", onOff(system.autoTime)) { system.autoTime = !system.autoTime; refresh() }
        row("24-hour clock", onOff(system.use24Hour)) { system.use24Hour = !system.use24Hour; refresh() }
        row("Time zone", TimeZone.getDefault().id.replace('_', ' ')) { open(::zonePage) }
    }

    private fun zonePage() {
        page("Time zone")
        row("Automatic", onOff(system.autoTimeZone)) { system.autoTimeZone = true; refresh() }
        COMMON_ZONES.forEach { id ->
            row(id.replace('_', ' '), if (TimeZone.getDefault().id == id) "Selected" else "") {
                if (system.setTimeZone(id)) refresh() else toast("Couldn't change the time zone")
            }
        }
    }

    private fun appsPage() {
        page("Apps", "Choose an app to open, stop or uninstall it.")
        AppRepository.load(this).forEach { app ->
                row(app.label, if (system.isUserApp(app.packageName)) "Installed" else "Built in") { appOptions(app) }
            }
    }

    private fun appOptions(app: AppEntry) {
        val actions = mutableListOf<Pair<String, () -> Unit>>()
        actions += "Open" to { AppRepository.launch(this, app) }
        actions += "Force stop" to { toast(if (system.forceStop(app.packageName)) "Stopped ${app.label}" else "Couldn't stop it") }
        if (system.isUserApp(app.packageName)) {
            actions += "Uninstall" to {
                confirm("Uninstall ${app.label}?", "Uninstall") {
                    if (system.uninstall(app.packageName)) {
                        toast("Uninstalling ${app.label}")
                        body.postDelayed({ refresh() }, 1500)
                    } else {
                        toast("Couldn't uninstall it")
                    }
                }
            }
        }
        AlertDialog.Builder(this, DIALOG_THEME)
            .setTitle(app.label)
            .setItems(actions.map { it.first }.toTypedArray()) { _, i -> actions[i].second() }
            .show()
    }

    private fun accountsPage() {
        page("Google accounts", "These accounts belong to ${profile?.name} only.")
        googleAccounts().forEach { name ->
            row(name, "Signed in") {
                AlertDialog.Builder(this, DIALOG_THEME)
                    .setTitle(name)
                    .setMessage("To sign out of this account, remove it in the account manager.")
                    .setPositiveButton("Open account manager") { _, _ -> openSettings(Settings.ACTION_SYNC_SETTINGS) }
                    .setNegativeButton("Close", null)
                    .show()
            }
        }
        row("Add a Google account") {
            try {
                AccountManager.get(this).addAccount("com.google", null, null, null, this, null, null)
            } catch (_: Exception) {
                toast("Google sign-in isn't available")
            }
        }
    }

    private fun storagePage() {
        val s = system.storage()
        page("Storage")
        row("Used", Formatter.formatFileSize(this, s.totalBytes - s.freeBytes)) {}
        row("Free", Formatter.formatFileSize(this, s.freeBytes)) {}
        row("Total", Formatter.formatFileSize(this, s.totalBytes)) {}
    }

    private fun aboutPage() {
        page("About BlidOS")
        val version = packageManager.getPackageInfo(packageName, 0).versionName
        row("BlidOS version", version ?: "") {}
        row("Device", system.deviceName) {}
        row("Based on", "Android ${system.androidVersion}") {}
        row("IP address", ipAddress() ?: "Not connected") {}
        row("Profiles", store.all().size.toString()) {}
    }

    // ---- Helpers ----

    private fun resetProfiles() {
        val owner = store.owner()
        val doReset = {
            store.all().filterNot { it.isOwner }.forEach { p ->
                p.userId?.let(users::removeUser)
                store.delete(p.id)
            }
            store.clearPin(owner.id)
            store.isSetupDone = false
            Session.lock()
            startActivity(Intent(this, SetupActivity::class.java))
            finish()
        }
        confirm("Reset profiles?", "Reset",
            "This removes every profile except yours, with their apps, data and Google accounts, " +
                "removes your PIN, and starts BlidOS setup again.") {
            if (!owner.hasPin) {
                doReset()
                return@confirm
            }
            PinDialog(this, "Enter your PIN", "To reset profiles") { pin ->
                when (val r = store.checkPin(owner.id, pin)) {
                    PinCheck.Ok -> { doReset(); null }
                    is PinCheck.Wrong -> "Wrong PIN. ${r.attemptsLeft} tries left."
                    is PinCheck.LockedOut -> "Too many tries. Wait ${r.seconds} seconds."
                }
            }.show()
        }
    }

    private fun confirm(title: String, action: String, message: String? = null, onYes: () -> Unit) {
        AlertDialog.Builder(this, DIALOG_THEME)
            .setTitle(title)
            .apply { message?.let(::setMessage) }
            .setPositiveButton(action) { _, _ -> onYes() }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun googleAccounts(): List<String> =
        try {
            AccountManager.get(this).getAccountsByType("com.google").map { it.name }
        } catch (_: Exception) {
            emptyList()
        }

    private fun ipAddress(): String? {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return null
        return cm.getLinkProperties(cm.activeNetwork)?.linkAddresses
            ?.map { it.address.hostAddress }
            ?.firstOrNull { it != null && ':' !in it }
    }

    companion object {
        private val COMMON_ZONES = listOf(
            "America/New_York", "America/Chicago", "America/Denver", "America/Phoenix", "America/Los_Angeles",
            "America/Anchorage", "Pacific/Honolulu", "America/Toronto", "America/Vancouver", "America/Mexico_City",
            "America/Sao_Paulo", "America/Buenos_Aires", "Europe/London", "Europe/Dublin", "Europe/Lisbon",
            "Europe/Paris", "Europe/Berlin", "Europe/Madrid", "Europe/Rome", "Europe/Amsterdam", "Europe/Stockholm",
            "Europe/Warsaw", "Europe/Athens", "Europe/Istanbul", "Europe/Moscow", "Africa/Cairo", "Africa/Lagos",
            "Africa/Johannesburg", "Asia/Dubai", "Asia/Karachi", "Asia/Kolkata", "Asia/Dhaka", "Asia/Bangkok",
            "Asia/Jakarta", "Asia/Shanghai", "Asia/Hong_Kong", "Asia/Singapore", "Asia/Manila", "Asia/Seoul",
            "Asia/Tokyo", "Australia/Perth", "Australia/Adelaide", "Australia/Sydney", "Pacific/Auckland",
        )
    }
}
