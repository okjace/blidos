package com.blidos.launcher.ui

import android.accounts.AccountManager
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Typeface
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextClock
import android.widget.TextView
import com.blidos.launcher.R
import com.blidos.launcher.Session
import com.blidos.launcher.data.KidsPolicy
import com.blidos.launcher.data.Profile
import com.blidos.launcher.data.ProfileProvider
import com.blidos.launcher.data.ProfileStore
import com.blidos.launcher.data.UserControl

/** The BlidOS home screen. Registered as the TV's HOME app. */
@SuppressLint("MissingPermission")
class HomeActivity : Activity() {
    private lateinit var store: ProfileStore
    private lateinit var users: UserControl
    private lateinit var content: LinearLayout
    private var lastFocusTag: Any? = null
    private var defaultFocus: View? = null

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = updateStatus()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = ProfileStore(this)
        users = UserControl(this)
        content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(32), 0, dp(48))
            clipChildren = false
            clipToPadding = false
        }
        setContentView(ScrollView(this).apply {
            background = screenBackground()
            isFillViewport = true
            clipChildren = false
            addView(content)
        })
    }

    override fun onStart() {
        super.onStart()
        registerSystemReceiver(statusReceiver, IntentFilter().apply {
            addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION)
            addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        })
    }

    override fun onStop() {
        unregisterReceiver(statusReceiver)
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        if (!users.isSystemUser) {
            resumeInOwnUser()
            return
        }
        // First boot: BlidOS's own setup instead of the tablet setup wizard.
        if (!store.isSetupDone && (users.isAvailable || !users.isDeviceProvisioned())) {
            content.removeAllViews()
            startActivity(Intent(this, SetupActivity::class.java))
            return
        }
        val profile = Session.profileId?.let(store::get)
        if (profile == null) {
            Session.lock()
            content.removeAllViews()
            lastFocusTag = null
            startActivity(Intent(this, ProfilePickerActivity::class.java))
            return
        }
        // Re-read every time so apps installed from Google Play show up right away.
        render(profile)
    }

    /** BlidOS running inside a profile's own Android user (its own apps, data and Google account). */
    private fun resumeInOwnUser() {
        val profile = ProfileProvider.profileForUser(this, users.myUserId)
        if (profile == null) {
            content.removeAllViews()
            content.addView(hint("This profile was removed. Switch back to choose another one."))
            addRow("Settings", listOf(switchTile("")))
            return
        }
        if (!SetupActivity.isProfileSetupDone(this)) {
            content.removeAllViews()
            startActivity(Intent(this, SetupActivity::class.java)
                .putExtra(SetupActivity.EXTRA_DEVICE, false)
                .putExtra(SetupActivity.EXTRA_NAME, profile.name))
            return
        }
        if (profile.isKids) KidsPolicy.apply(this, profile, users)
        render(profile)
    }

    override fun onPause() {
        currentFocus?.tag?.let { lastFocusTag = it }
        super.onPause()
    }

    // A launcher has nowhere to go "back" to.
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean =
        keyCode == KeyEvent.KEYCODE_BACK || super.onKeyDown(keyCode, event)

    private fun render(profile: Profile) {
        content.removeAllViews()
        defaultFocus = null
        content.addView(topBar(profile))

        if (profile.isOwner && !profile.hasPin && store.all().size > 1) {
            content.addView(hint("Tip: lock your Owner profile with a PIN (Settings row, Profiles) so others can't open it."))
        }

        val apps = AppRepository.load(this)
        val playStore = apps.firstOrNull { it.packageName == AppRepository.PLAY_STORE }
        val others = apps.filter { it.packageName != AppRepository.PLAY_STORE }

        if (profile.isKids) {
            val allowed = others.filter { it.packageName in profile.allowedApps && it.packageName !in AppRepository.ADULT_ONLY }
            if (allowed.isEmpty()) {
                content.addView(hint("No apps yet. Ask a grown-up to choose apps for this profile."))
            } else {
                addRow("Apps", allowed.map(::appTile))
            }
        } else {
            addRow("Apps", listOf(playStoreTile(playStore)) + others.map(::appTile))
        }
        addRow("Settings", settingsTiles(profile))

        val target = lastFocusTag?.let { content.findViewWithTag<View>(it) } ?: defaultFocus
        target?.requestFocus()
    }

    private fun topBar(profile: Profile) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(56), 0, dp(64), dp(8))
        clipChildren = false
        clipToPadding = false

        val chip = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            isFocusable = true
            isClickable = true
            tag = "chip"
            setPadding(dp(8), dp(6), dp(22), dp(6))
            background = tileBackground(Color.TRANSPARENT, dp(32))
            addView(avatar(profile, 44))
            addView(label(profile.name, 22f, bold = true).apply { setPadding(dp(14), 0, 0, 0) })
            setOnClickListener { switchProfile() }
            focusZoom(1.05f)
        }
        addView(chip)
        addView(View(context), LinearLayout.LayoutParams(0, 1, 1f))
        addView(label("BlidOS", 16f, Palette.TEXT_DIM, bold = true).apply { setPadding(0, 0, dp(24), 0) })
        addView(TextClock(context).apply {
            format12Hour = "h:mm"
            format24Hour = "HH:mm"
            setTextColor(Color.WHITE)
            textSize = 26f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        })
    }

    private fun hint(text: String) = label(text, 16f, Palette.TEXT_DIM).apply {
        setPadding(dp(64), dp(16), dp(64), 0)
    }

    private fun addRow(title: String, tiles: List<View>) {
        if (tiles.isEmpty()) return
        if (defaultFocus == null) defaultFocus = tiles.first()
        content.addView(label(title, 20f, Palette.TEXT_DIM, bold = true).apply {
            setPadding(dp(64), dp(28), dp(64), dp(4))
        })
        val strip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(60), dp(14), dp(60), dp(14))
            clipChildren = false
            clipToPadding = false
        }
        tiles.forEach { strip.addView(it, LinearLayout.LayoutParams(dp(208), dp(118)).apply { marginEnd = dp(20) }) }
        content.addView(HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            clipChildren = false
            clipToPadding = false
            addView(strip)
        })
    }

    private fun appTile(app: AppEntry): View = FrameLayout(this).apply {
        isFocusable = true
        isClickable = true
        tag = "app:${app.packageName}"
        contentDescription = app.label
        setPadding(dp(4), dp(4), dp(4), dp(4))
        background = tileBackground(Palette.SURFACE)
        if (app.banner != null) {
            addView(ImageView(context).apply {
                setImageDrawable(app.banner)
                scaleType = ImageView.ScaleType.FIT_CENTER
            }, FrameLayout.LayoutParams(MATCH, MATCH))
        } else {
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                addView(ImageView(context).apply { setImageDrawable(app.icon) }, LinearLayout.LayoutParams(dp(48), dp(48)))
                addView(label(app.label, 14f).apply {
                    gravity = Gravity.CENTER
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(dp(8), dp(8), dp(8), 0)
                })
            }, FrameLayout.LayoutParams(MATCH, MATCH))
        }
        setOnClickListener { AppRepository.launch(this@HomeActivity, app) }
        focusZoom()
    }

    private fun actionTile(
        title: String,
        subtitle: String,
        iconRes: Int,
        color: Int,
        tag: String,
        onClick: () -> Unit,
    ): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_VERTICAL
        isFocusable = true
        isClickable = true
        this.tag = tag
        setPadding(dp(18), dp(14), dp(18), dp(14))
        background = tileBackground(color)
        addView(ImageView(context).apply {
            setImageResource(iconRes)
            setColorFilter(Color.WHITE)
        }, LinearLayout.LayoutParams(dp(32), dp(32)))
        addView(label(title, 17f, bold = true).apply {
            setPadding(0, dp(8), 0, 0)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        addView(label(subtitle, 13f, Palette.TEXT_DIM).apply {
            this.tag = "$tag:sub"
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        setOnClickListener { onClick() }
        focusZoom()
    }

    private fun playStoreTile(playStore: AppEntry?): View =
        if (playStore != null) {
            actionTile("Google Play", "Get more apps", R.drawable.ic_play, Palette.PLAY_GREEN, "playstore") {
                AppRepository.launch(this, playStore)
            }
        } else {
            actionTile("Google Play", "Not available", R.drawable.ic_play, Palette.SURFACE, "playstore") {
                AlertDialog.Builder(this, DIALOG_THEME)
                    .setTitle("Google Play isn't on this TV")
                    .setMessage(
                        "Google Play comes with Google-certified Android TV and Google TV devices. " +
                            "Install BlidOS on one of those to download apps from the Play Store."
                    )
                    .setPositiveButton("OK", null)
                    .show()
            }
        }

    private fun settingsTiles(profile: Profile): List<View> {
        val tiles = mutableListOf<View>()
        if (!profile.isKids) {
            tiles += actionTile("Wi-Fi", wifiSummary(), R.drawable.ic_wifi, Palette.SURFACE, "wifi") {
                startActivity(Intent(this, WifiActivity::class.java))
            }
            tiles += actionTile("Bluetooth", bluetoothSummary(), R.drawable.ic_bluetooth, Palette.SURFACE, "bt") {
                startActivity(Intent(this, BluetoothActivity::class.java))
            }
        }
        if (!profile.isKids || googleAccounts().isNotEmpty()) {
            tiles += actionTile("Google account", googleAccounts().firstOrNull() ?: "Not signed in",
                R.drawable.ic_person, Palette.SURFACE, "google") { openGoogleAccount() }
        }
        tiles += switchTile(profile.name)
        if (profile.isOwner && users.isSystemUser) {
            tiles += actionTile("Profiles", "PINs and Kids mode", R.drawable.ic_lock, Palette.SURFACE, "profiles") {
                startActivity(Intent(this, ProfilesActivity::class.java))
            }
        }
        if (!profile.isKids) {
            tiles += actionTile("Settings", "Sound, display, apps and more", R.drawable.ic_tune, Palette.SURFACE, "settings") {
                startActivity(Intent(this, SettingsActivity::class.java))
            }
        }
        return tiles
    }

    private fun switchTile(name: String) =
        actionTile("Switch profile", if (name.isEmpty()) "Choose a profile" else "Signed in as $name",
            R.drawable.ic_person, Palette.SURFACE, "switch") { switchProfile() }

    private fun switchProfile() {
        lastFocusTag = null
        if (!users.isSystemUser) {
            // Back to Android user 0, where the profile picker and PINs live.
            ProfileProvider.lockOwnerSession(this)
            if (!users.switchTo(0)) toast("Couldn't switch profiles")
            return
        }
        Session.lock()
        startActivity(Intent(this, ProfilePickerActivity::class.java))
    }

    private fun googleAccounts(): List<String> =
        try {
            AccountManager.get(this).getAccountsByType("com.google").map { it.name }
        } catch (_: Exception) {
            emptyList()
        }

    private fun openGoogleAccount() {
        if (googleAccounts().isNotEmpty()) {
            startActivity(Intent(this, SettingsActivity::class.java))
            return
        }
        try {
            AccountManager.get(this).addAccount("com.google", null, null, null, this, null, null)
        } catch (_: Exception) {
            toast("Google sign-in isn't available on this TV")
        }
    }

    private fun updateStatus() {
        content.findViewWithTag<TextView>("wifi:sub")?.text = wifiSummary()
        content.findViewWithTag<TextView>("bt:sub")?.text = bluetoothSummary()
    }

    private fun wifiSummary(): String {
        val cm = getSystemService(ConnectivityManager::class.java)
        val caps = cm?.getNetworkCapabilities(cm.activeNetwork)
        return when {
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true -> "Using Ethernet"
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true -> "Connected"
            applicationContext.getSystemService(WifiManager::class.java)?.isWifiEnabled == true -> "Not connected"
            else -> "Off"
        }
    }

    private fun bluetoothSummary(): String {
        val adapter = getSystemService(BluetoothManager::class.java)?.adapter ?: return "Not available"
        return if (adapter.isEnabled) "On" else "Off"
    }
}
