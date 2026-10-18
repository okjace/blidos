package com.blidos.launcher.ui

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import com.blidos.launcher.data.SystemControl

/** Pairs remotes, game controllers, keyboards, headphones and speakers. */
@SuppressLint("MissingPermission")
class BluetoothActivity : Activity() {
    private var adapter: BluetoothAdapter? = null
    private val found = LinkedHashMap<String, BluetoothDevice>()

    private lateinit var status: TextView
    private lateinit var toggle: TextView
    private lateinit var scanButton: TextView
    private lateinit var buttons: View
    private lateinit var paired: LinearLayout
    private lateinit var available: LinearLayout

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device = intent.device()
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> device?.let { found[it.address] = it }
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                    if (state == BluetoothDevice.BOND_BONDED && device != null) toast("Paired with ${nameOf(device)}")
                }
            }
            refresh()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        adapter = getSystemService(BluetoothManager::class.java)?.adapter

        val body = screen("Bluetooth")
        status = label("", 18f, Palette.TEXT_DIM).apply { setPadding(0, dp(8), 0, 0) }
        body.addView(status)
        toggle = pillButton("") { toggleBluetooth() }
        scanButton = pillButton("") { toggleScan() }
        buttons = buttonRow(
            toggle,
            scanButton,
        )
        body.addView(buttons)
        body.addView(label(
            "To add a remote, game controller or headphones, put it in pairing mode, then choose Pair new device.",
            15f, Palette.TEXT_DIM,
        ).apply { setPadding(0, dp(8), 0, 0) })

        body.addView(sectionHeader("Paired devices"))
        paired = column()
        body.addView(paired)
        body.addView(sectionHeader("Available devices"))
        available = column()
        body.addView(available)

        if (!hasPermissions()) requestPermissions(requiredPermissions(), REQ_PERMISSIONS)
        toggle.requestFocus()
    }

    override fun onStart() {
        super.onStart()
        registerSystemReceiver(receiver, IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        })
        refresh()
    }

    override fun onStop() {
        unregisterReceiver(receiver)
        if (hasPermissions()) adapter?.cancelDiscovery()
        super.onStop()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        refresh()
    }

    private fun column() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        clipChildren = false
        clipToPadding = false
    }

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun hasPermissions() =
        requiredPermissions().all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun refresh() {
        paired.removeAllViews()
        available.removeAllViews()

        val bt = adapter
        if (bt == null) {
            status.text = "This TV doesn't have Bluetooth."
            buttons.visibility = View.GONE
            return
        }
        if (!hasPermissions()) {
            status.text = "Allow Bluetooth access to manage devices."
            toggle.text = "Allow access"
            toggle.setOnClickListener { requestPermissions(requiredPermissions(), REQ_PERMISSIONS) }
            scanButton.visibility = View.GONE
            return
        }
        toggle.setOnClickListener { toggleBluetooth() }

        val on = bt.isEnabled
        status.text = when {
            !on -> "Bluetooth is off"
            bt.isDiscovering -> "Bluetooth is on · searching for devices…"
            else -> "Bluetooth is on"
        }
        toggle.text = if (on) "Turn off" else "Turn on"
        scanButton.visibility = if (on) View.VISIBLE else View.GONE
        scanButton.text = if (bt.isDiscovering) "Stop searching" else "Pair new device"
        if (!on) return

        val bonded = bt.bondedDevices.orEmpty()
        if (bonded.isEmpty()) paired.addView(label("No paired devices yet.", 16f, Palette.TEXT_DIM))
        bonded.sortedBy { nameOf(it).lowercase() }.forEach { device ->
            paired.addView(listRow(nameOf(device), "${kindOf(device)} · Paired") { showPaired(device) })
        }

        val nearby = found.values.filter { it.bondState != BluetoothDevice.BOND_BONDED }
        if (nearby.isEmpty()) {
            val hint = if (bt.isDiscovering) "Searching…" else "Choose Pair new device to search."
            available.addView(label(hint, 16f, Palette.TEXT_DIM))
        }
        nearby.forEach { device ->
            val state = if (device.bondState == BluetoothDevice.BOND_BONDING) "Pairing…" else "Select to pair"
            available.addView(listRow(nameOf(device), "${kindOf(device)} · $state") { pair(device) })
        }
    }

    private fun toggleBluetooth() {
        val bt = adapter ?: return
        // System apps (the BlidOS PC image) can switch Bluetooth directly.
        @Suppress("DEPRECATION")
        val changed = try {
            if (bt.isEnabled) bt.disable() else bt.enable()
        } catch (_: SecurityException) {
            false
        }
        if (changed) return
        if (!bt.isEnabled) {
            startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
        } else {
            // Regular apps on Android 13+ aren't allowed to turn Bluetooth off.
            openSettings(Settings.ACTION_BLUETOOTH_SETTINGS)
        }
    }

    private fun toggleScan() {
        val bt = adapter ?: return
        if (bt.isDiscovering) {
            bt.cancelDiscovery()
        } else {
            found.clear()
            if (!bt.startDiscovery()) toast("Couldn't start searching")
        }
        refresh()
    }

    private fun pair(device: BluetoothDevice) {
        adapter?.cancelDiscovery()
        if (device.createBond()) {
            toast("Pairing with ${nameOf(device)}. Follow any prompts on screen.")
        } else {
            toast("Couldn't pair with ${nameOf(device)}")
        }
        refresh()
    }

    private fun showPaired(device: BluetoothDevice) {
        AlertDialog.Builder(this, DIALOG_THEME)
            .setTitle(nameOf(device))
            .setMessage("${kindOf(device)} · ${device.address}")
            .setPositiveButton("Forget device") { _, _ ->
                if (SystemControl(this).forgetDevice(device)) {
                    toast("Forgot ${nameOf(device)}")
                    refresh()
                } else {
                    toast("Couldn't forget ${nameOf(device)}")
                }
            }
            .setNegativeButton("Close", null)
            .show()
    }

    private fun nameOf(device: BluetoothDevice): String =
        try {
            device.name?.takeIf { it.isNotBlank() } ?: device.address
        } catch (_: SecurityException) {
            device.address
        }

    private fun kindOf(device: BluetoothDevice): String = when (device.bluetoothClass?.majorDeviceClass) {
        BluetoothClass.Device.Major.AUDIO_VIDEO -> "Audio"
        BluetoothClass.Device.Major.PERIPHERAL -> "Remote or controller"
        BluetoothClass.Device.Major.PHONE -> "Phone"
        BluetoothClass.Device.Major.COMPUTER -> "Computer"
        else -> "Device"
    }

    private fun Intent.device(): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    companion object {
        private const val REQ_PERMISSIONS = 1
    }
}
