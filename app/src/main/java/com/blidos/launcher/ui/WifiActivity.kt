package com.blidos.launcher.ui

import android.Manifest
import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.ScanResult
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/** Lists nearby Wi-Fi networks and joins them. */
@SuppressLint("MissingPermission")
class WifiActivity : Activity() {
    private lateinit var wifi: WifiManager
    private lateinit var status: TextView
    private lateinit var toggle: TextView
    private lateinit var list: LinearLayout

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = refresh()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wifi = applicationContext.getSystemService(WifiManager::class.java)

        val body = screen("Wi-Fi")
        status = label("", 18f, Palette.TEXT_DIM).apply { setPadding(0, dp(8), 0, 0) }
        body.addView(status)
        toggle = pillButton("") { toggleWifi() }
        body.addView(buttonRow(
            toggle,
            pillButton("Scan again") { scan() },
        ))
        body.addView(sectionHeader("Networks"))
        list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            clipChildren = false
            clipToPadding = false
        }
        body.addView(list)

        if (!hasLocation()) requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), REQ_LOCATION)
        toggle.requestFocus()
    }

    override fun onStart() {
        super.onStart()
        registerSystemReceiver(receiver, IntentFilter().apply {
            addAction(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
            addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION)
            addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
        })
        refresh()
        scan()
    }

    override fun onStop() {
        unregisterReceiver(receiver)
        super.onStop()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        refresh()
        scan()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_ADD_NETWORK && resultCode == RESULT_OK) toast("Network saved. Connecting…")
    }

    private fun hasLocation() =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    private fun scan() {
        if (wifi.isWifiEnabled && hasLocation()) wifi.startScan()
    }

    private fun refresh() {
        val enabled = wifi.isWifiEnabled
        val current = currentSsid()
        status.text = when {
            !enabled -> "Wi-Fi is off"
            current != null -> "Connected to $current"
            else -> "Not connected"
        }
        toggle.text = if (enabled) "Turn off" else "Turn on"

        list.removeAllViews()
        if (!enabled) {
            list.addView(label("Turn on Wi-Fi to see networks.", 16f, Palette.TEXT_DIM))
            return
        }
        if (!hasLocation()) {
            list.addView(label("Android needs location access to list nearby networks.", 16f, Palette.TEXT_DIM))
            list.addView(buttonRow(pillButton("Allow access") {
                requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), REQ_LOCATION)
            }))
            return
        }

        val networks = wifi.scanResults
            .filter { ssidOf(it).isNotBlank() }
            .groupBy { ssidOf(it) }
            .map { (_, results) -> results.maxBy { it.level } }
            .sortedWith(compareByDescending<ScanResult> { ssidOf(it) == current }.thenByDescending { it.level })

        if (networks.isEmpty()) {
            list.addView(label("Looking for networks…", 16f, Palette.TEXT_DIM))
            return
        }
        networks.forEach { result ->
            val ssid = ssidOf(result)
            val detail = listOfNotNull(
                if (ssid == current) "Connected" else null,
                signalLabel(result.level),
                if (isSecured(result)) "Secured" else "Open",
            ).joinToString(" · ")
            list.addView(listRow(ssid, detail) { onNetworkChosen(result, ssid == current) })
        }
    }

    private fun onNetworkChosen(result: ScanResult, isCurrent: Boolean) {
        val ssid = ssidOf(result)
        val caps = result.capabilities
        when {
            isCurrent -> AlertDialog.Builder(this, DIALOG_THEME)
                .setTitle(ssid)
                .setMessage("Connected · ${signalLabel(result.level)} signal")
                .setPositiveButton("Forget network") { _, _ -> forgetCurrent(ssid) }
                .setNeutralButton("Disconnect") { _, _ ->
                    @Suppress("DEPRECATION")
                    wifi.disconnect()
                }
                .setNegativeButton("Close", null)
                .show()

            // Rare on home networks: work/school (EAP) and very old (WEP) Wi-Fi.
            "EAP" in caps || "WEP" in caps -> AlertDialog.Builder(this, DIALOG_THEME)
                .setTitle(ssid)
                .setMessage("This is a work, school or very old type of network. BlidOS can't join it yet.")
                .setPositiveButton("Use advanced Wi-Fi settings") { _, _ -> openSettings(Settings.ACTION_WIFI_SETTINGS) }
                .setNegativeButton("Cancel", null)
                .show()

            isSecured(result) -> askPassword(ssid) { password ->
                connect(ssid, password, isWpa3Only = "SAE" in caps && "PSK" !in caps)
            }

            else -> connect(ssid, null, isWpa3Only = false)
        }
    }

    private fun askPassword(ssid: String, onDone: (String) -> Unit) {
        val input = EditText(this).apply {
            hint = "Password"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            setSingleLine()
        }
        AlertDialog.Builder(this, DIALOG_THEME)
            .setTitle("Join $ssid")
            .setView(FrameLayout(this).apply {
                setPadding(dp(24), dp(8), dp(24), 0)
                addView(input)
            })
            .setPositiveButton("Connect") { _, _ ->
                val password = input.text.toString()
                if (password.length >= 8) onDone(password) else toast("Wi-Fi passwords are at least 8 characters")
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun connect(ssid: String, password: String?, isWpa3Only: Boolean) {
        // As a system app (the BlidOS PC image) BlidOS joins networks itself.
        if (connectDirect(ssid, password, isWpa3Only)) return
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> connectWithSystemPrompt(ssid, password, isWpa3Only)
            Build.VERSION.SDK_INT == Build.VERSION_CODES.Q -> addSuggestion(ssid, suggestion(ssid, password, isWpa3Only))
            else -> toast("Couldn't add that network")
        }
    }

    /** Android 11+ for regular apps: the system asks the user to confirm, then saves and joins the network. */
    @TargetApi(Build.VERSION_CODES.R)
    private fun connectWithSystemPrompt(ssid: String, password: String?, isWpa3Only: Boolean) {
        val network = suggestion(ssid, password, isWpa3Only)
        val intent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS)
            .putParcelableArrayListExtra(Settings.EXTRA_WIFI_NETWORK_LIST, arrayListOf(network))
        try {
            startActivityForResult(intent, REQ_ADD_NETWORK)
        } catch (_: ActivityNotFoundException) {
            addSuggestion(ssid, network)
        }
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun suggestion(ssid: String, password: String?, isWpa3Only: Boolean): WifiNetworkSuggestion =
        WifiNetworkSuggestion.Builder().setSsid(ssid).apply {
            when {
                password == null -> Unit
                isWpa3Only -> setWpa3Passphrase(password)
                else -> setWpa2Passphrase(password)
            }
        }.build()

    @TargetApi(Build.VERSION_CODES.Q)
    private fun addSuggestion(ssid: String, network: WifiNetworkSuggestion) {
        val status = wifi.addNetworkSuggestions(listOf(network))
        if (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
            toast("Saved. The TV will join $ssid shortly.")
        } else {
            toast("Couldn't save that network")
        }
    }

    /** Saves and joins a network directly. Works for system apps and on Android 9 and older. */
    @Suppress("DEPRECATION")
    private fun connectDirect(ssid: String, password: String?, isWpa3Only: Boolean): Boolean {
        val config = WifiConfiguration().apply {
            SSID = "\"$ssid\""
            when {
                password == null -> allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                isWpa3Only && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                    setSecurityParams(WifiConfiguration.SECURITY_TYPE_SAE)
                    preSharedKey = "\"$password\""
                }
                else -> preSharedKey = "\"$password\""
            }
        }
        val id = try {
            wifi.addNetwork(config)
        } catch (_: SecurityException) {
            -1
        }
        if (id == -1) return false
        wifi.disconnect()
        wifi.enableNetwork(id, true)
        wifi.reconnect()
        toast("Connecting to $ssid…")
        return true
    }

    @Suppress("DEPRECATION")
    private fun forgetCurrent(ssid: String) {
        val id = wifi.connectionInfo?.networkId ?: -1
        if (id != -1 && wifi.removeNetwork(id)) {
            toast("Forgot $ssid")
            refresh()
        } else {
            toast("Couldn't forget $ssid")
        }
    }

    private fun toggleWifi() {
        val target = !wifi.isWifiEnabled
        @Suppress("DEPRECATION")
        val changed = try {
            wifi.setWifiEnabled(target)
        } catch (_: SecurityException) {
            false
        }
        // Regular apps on Android 10+ aren't allowed to switch Wi-Fi; the system panel does it.
        if (!changed) openSettings(Settings.Panel.ACTION_WIFI, Settings.ACTION_WIFI_SETTINGS)
    }

    private fun currentSsid(): String? {
        @Suppress("DEPRECATION")
        val info = wifi.connectionInfo ?: return null
        if (info.networkId == -1) return null
        val ssid = info.ssid?.removeSurrounding("\"") ?: return null
        return ssid.takeIf { it.isNotBlank() && it != "<unknown ssid>" }
    }

    @Suppress("DEPRECATION")
    private fun ssidOf(result: ScanResult): String = result.SSID.orEmpty()

    private fun isSecured(result: ScanResult) =
        listOf("WPA", "WEP", "SAE", "PSK", "EAP").any { it in result.capabilities }

    private fun signalLabel(rssi: Int) = when {
        rssi >= -55 -> "Excellent"
        rssi >= -67 -> "Good"
        rssi >= -78 -> "Fair"
        else -> "Weak"
    }

    companion object {
        private const val REQ_LOCATION = 1
        private const val REQ_ADD_NETWORK = 2
    }
}
