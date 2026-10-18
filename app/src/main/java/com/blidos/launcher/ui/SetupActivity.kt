package com.blidos.launcher.ui

import android.accounts.AccountManager
import android.accounts.OperationCanceledException
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Bundle
import android.text.InputFilter
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.blidos.launcher.R
import com.blidos.launcher.Session
import com.blidos.launcher.data.ProfileStore
import com.blidos.launcher.data.SystemControl
import com.blidos.launcher.data.UserControl

/**
 * BlidOS's own setup, in place of the tablet setup wizard.
 *
 * Device setup (first boot, Android user 0): welcome, network, your profile and PIN, Google account,
 * other people who use the TV, done.
 * Profile setup (first time a profile's own Android user starts): welcome, Google account, done.
 */
class SetupActivity : Activity() {
    private lateinit var store: ProfileStore
    private lateinit var users: UserControl
    private lateinit var body: LinearLayout
    private var deviceSetup = true
    private var profileName = ""
    private var step = 0
    private val steps = mutableListOf<() -> Unit>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = ProfileStore(this)
        users = UserControl(this)
        deviceSetup = intent.getBooleanExtra(EXTRA_DEVICE, true)
        profileName = intent.getStringExtra(EXTRA_NAME).orEmpty()

        body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(96), dp(48), dp(96), dp(48))
            clipChildren = false
            clipToPadding = false
        }
        setContentView(FrameLayout(this).apply {
            background = screenBackground()
            addView(body, FrameLayout.LayoutParams(MATCH, MATCH))
        })

        if (deviceSetup) {
            steps += ::welcomeStep
            steps += ::networkStep
            steps += ::ownerStep
            steps += ::googleStep
            if (users.isAvailable) steps += ::familyStep
            steps += ::doneStep
        } else {
            steps += ::profileWelcomeStep
            steps += ::googleStep
            steps += ::doneStep
        }
        show(0)
    }

    override fun onResume() {
        super.onResume()
        // Coming back from the Wi-Fi screen or Google sign-in: refresh what the step shows.
        if (steps.isNotEmpty()) show(step)
    }

    // Back goes to the previous step; it can't leave setup.
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (step > 0) show(step - 1)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun show(index: Int) {
        step = index.coerceIn(0, steps.lastIndex)
        body.removeAllViews()
        steps[step]()
    }

    private fun next() = show(step + 1)

    // ---- Steps ----

    private fun welcomeStep() {
        logo()
        title("Welcome to BlidOS")
        text("Let's get your TV ready. It only takes a minute.")
        buttons(pillButton("Get started") { next() })
    }

    private fun networkStep() {
        title("Connect to the internet")
        val status = networkStatus()
        text(status ?: "You need internet for Google Play and streaming apps.")
        if (status == null) {
            buttons(
                pillButton("Choose a Wi-Fi network") { startActivity(Intent(this, WifiActivity::class.java)) },
                pillButton("Skip for now") { next() },
            )
        } else {
            buttons(
                pillButton("Continue") { next() },
                pillButton("Change Wi-Fi") { startActivity(Intent(this, WifiActivity::class.java)) },
            )
        }
    }

    private fun ownerStep() {
        val owner = store.owner()
        title("Your profile")
        text("This is the main profile. It can add people, set PINs and manage the TV.")
        val name = nameField(if (owner.name == "Owner") "" else owner.name, "Your name")
        val pinState = text(if (store.owner().hasPin) "PIN is set." else "Add a PIN so nobody else can open your profile.")
        lateinit var pinButton: TextView
        pinButton = pillButton(if (owner.hasPin) "Change PIN" else "Add a PIN") {
            setPin(owner.id) {
                pinState.text = "PIN is set."
                pinButton.text = "Change PIN"
            }
        }
        buttons(
            pillButton("Continue") {
                val typed = name.text.toString().trim().ifEmpty { "Owner" }
                store.edit(owner.id) { it.copy(name = typed) }
                if (users.isAvailable) users.setUserName(0, typed)
                next()
            },
            pinButton,
        )
        name.requestFocus()
    }

    private fun googleStep() {
        title("Google account")
        val accounts = googleAccounts()
        if (accounts.isNotEmpty()) {
            text("Signed in as ${accounts.joinToString()}.")
            text("Your apps, purchases and settings from Google come with you.", dim = true)
            buttons(pillButton("Continue") { next() }, pillButton("Add another account") { addGoogleAccount() })
        } else {
            text(
                if (deviceSetup) "Sign in to download apps from Google Play."
                else "Sign in with your own Google account. Your apps and data stay separate from other profiles."
            )
            buttons(pillButton("Sign in with Google") { addGoogleAccount() }, pillButton("Skip for now") { next() })
        }
    }

    private fun familyStep() {
        title("Who else watches?")
        text("Each person gets their own apps, Google account and settings. Kids profiles only see apps you pick.")
        val others = store.all().filterNot { it.isOwner }
        if (others.isNotEmpty()) {
            text(others.joinToString { if (it.isKids) "${it.name} (Kids)" else it.name }, dim = true)
        }
        buttons(
            pillButton(if (others.isEmpty()) "Done for now" else "Continue") { next() },
            pillButton("Add a person") { addPerson(kids = false) },
            pillButton("Add a kid") { addPerson(kids = true) },
        )
    }

    private fun profileWelcomeStep() {
        logo()
        title("Hi, ${profileName.ifEmpty { "there" }}!")
        text("This is your own space on the TV: your apps, your Google account and your settings.")
        buttons(pillButton("Get started") { next() })
    }

    private fun doneStep() {
        logo()
        title("You're all set")
        text(
            if (deviceSetup) "You can add people, PINs and Kids profiles anytime from Settings, Profiles."
            else "Enjoy! Press Switch profile on the home screen when you're done."
        )
        buttons(pillButton("Start watching") { finishSetup() })
    }

    // ---- Actions ----

    private fun finishSetup() {
        users.markSetupComplete(wholeDevice = deviceSetup)
        SystemControl(this).disableScreensaver()
        if (deviceSetup) {
            store.isSetupDone = true
            if (users.isAvailable) users.hideSystemUserSwitcher()
            Session.profileId = store.owner().id
        } else {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(KEY_PROFILE_DONE, true).apply()
        }
        finish()
    }

    private fun addPerson(kids: Boolean) {
        if (!store.canAdd()) {
            toast("You can have up to ${ProfileStore.MAX_PROFILES} profiles")
            return
        }
        promptForName(if (kids) "Kid's name" else "Their name") { name ->
            val userId = users.createUser(name)
            if (userId == null) {
                toast("Couldn't add $name")
                return@promptForName
            }
            val profile = store.add(name, userId)
            if (kids) {
                store.edit(profile.id) { it.copy(isKids = true) }
                UserControl.KIDS_RESTRICTIONS.forEach { users.setRestriction(userId, it, true) }
            }
            show(step)
        }
    }

    private fun setPin(profileId: String, onSaved: () -> Unit) {
        PinDialog(this, "New PIN", "Pick 4 digits") { first ->
            PinDialog(this, "Confirm PIN", "Enter the same 4 digits again") { second ->
                if (second != first) {
                    "Those didn't match. Try again, or press Back to start over."
                } else {
                    store.setPin(profileId, second)
                    onSaved()
                    null
                }
            }.show()
            null
        }.show()
    }

    private fun addGoogleAccount() {
        try {
            AccountManager.get(this).addAccount(GOOGLE, null, null, null, this, { future ->
                try {
                    future.result
                } catch (_: OperationCanceledException) {
                } catch (e: Exception) {
                    toast("Couldn't sign in: ${e.message ?: "try again"}")
                }
                show(step)
            }, null)
        } catch (_: Exception) {
            AlertDialog.Builder(this, DIALOG_THEME)
                .setTitle("Google sign-in isn't available")
                .setMessage("This TV doesn't have Google Play services. You can skip this step.")
                .setPositiveButton("OK", null)
                .show()
        }
    }

    private fun googleAccounts(): List<String> =
        try {
            AccountManager.get(this).getAccountsByType(GOOGLE).map { it.name }
        } catch (_: Exception) {
            emptyList()
        }

    private fun networkStatus(): String? {
        val cm = getSystemService(ConnectivityManager::class.java)
        val caps = cm?.getNetworkCapabilities(cm.activeNetwork) ?: return null
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Connected with Ethernet."
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Connected to Wi-Fi."
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> "Connected to the internet."
            else -> null
        }
    }

    // ---- Layout helpers ----

    private fun logo() {
        body.addView(ImageView(this).apply { setImageResource(R.drawable.ic_launcher) },
            LinearLayout.LayoutParams(dp(112), dp(112)).apply { bottomMargin = dp(24) })
    }

    private fun title(text: String) {
        body.addView(label(text, 40f, bold = true).apply { gravity = Gravity.CENTER })
    }

    private fun text(text: String, dim: Boolean = false): TextView =
        label(text, 19f, if (dim) Palette.TEXT_DIM else Palette.TEXT).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(14), 0, 0)
            maxWidth = dp(760)
        }.also { body.addView(it) }

    private fun buttons(vararg views: View) {
        val row = buttonRow(*views).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(36), 0, 0)
        }
        body.addView(row)
        views.first().requestFocus()
    }

    private fun nameField(initial: String, hint: String): EditText =
        EditText(this).apply {
            setText(initial)
            this.hint = hint
            setSingleLine()
            textSize = 22f
            setTextColor(Palette.TEXT)
            setHintTextColor(Palette.TEXT_DIM)
            filters = arrayOf(InputFilter.LengthFilter(20))
            gravity = Gravity.CENTER
        }.also { body.addView(it, LinearLayout.LayoutParams(dp(420), WRAP).apply { topMargin = dp(24) }) }

    private fun promptForName(title: String, onDone: (String) -> Unit) {
        val input = EditText(this).apply {
            setSingleLine()
            filters = arrayOf(InputFilter.LengthFilter(20))
        }
        AlertDialog.Builder(this, DIALOG_THEME)
            .setTitle(title)
            .setView(FrameLayout(this).apply {
                setPadding(dp(24), dp(8), dp(24), 0)
                addView(input)
            })
            .setPositiveButton("Add") { _, _ ->
                input.text.toString().trim().takeIf { it.isNotEmpty() }?.let(onDone)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    companion object {
        const val EXTRA_DEVICE = "device"
        const val EXTRA_NAME = "name"
        private const val GOOGLE = "com.google"
        private const val PREFS = "profile_setup"
        private const val KEY_PROFILE_DONE = "done"

        /** Has this profile's own Android user been through its first-run setup? */
        fun isProfileSetupDone(activity: Activity) =
            activity.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(KEY_PROFILE_DONE, false)
    }
}
