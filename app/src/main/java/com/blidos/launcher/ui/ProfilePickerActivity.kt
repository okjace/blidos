package com.blidos.launcher.ui

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import com.blidos.launcher.Session
import com.blidos.launcher.data.PinCheck
import com.blidos.launcher.data.Profile
import com.blidos.launcher.data.ProfileStore
import com.blidos.launcher.data.UserControl

/** "Who's watching?" screen. The only way past it is picking a profile (and entering its PIN). */
class ProfilePickerActivity : Activity() {
    private lateinit var store: ProfileStore
    private lateinit var row: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = ProfileStore(this)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = screenBackground()
            clipChildren = false
        }
        root.addView(label("Who's watching?", 40f, bold = true).apply { gravity = Gravity.CENTER })
        root.addView(label("Choose your profile", 18f, Palette.TEXT_DIM).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, dp(36))
        })
        row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(32), dp(16), dp(32), dp(16))
            clipChildren = false
            clipToPadding = false
        }
        root.addView(HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            clipChildren = false
            addView(row)
        }, LinearLayout.LayoutParams(WRAP, WRAP))
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        row.removeAllViews()
        store.all().forEach { profile ->
            row.addView(profileCard(profile, if (profile.hasPin) "PIN locked" else null) { select(profile) })
        }
        row.getChildAt(0)?.requestFocus()
    }

    private fun select(profile: Profile) {
        if (!profile.hasPin) {
            enter(profile)
            return
        }
        PinDialog(this, "Enter PIN", profile.name) { pin ->
            when (val result = store.checkPin(profile.id, pin)) {
                PinCheck.Ok -> {
                    enter(profile)
                    null
                }
                is PinCheck.Wrong ->
                    "Wrong PIN. ${result.attemptsLeft} ${if (result.attemptsLeft == 1) "try" else "tries"} left."
                is PinCheck.LockedOut -> "Too many tries. Wait ${result.seconds} seconds."
            }
        }.show()
    }

    private fun enter(profile: Profile) {
        val userId = profile.userId
        val users = UserControl(this)
        if (userId != null && userId != 0 && users.isAvailable) {
            // The profile has its own Android user: its own apps, data and Google account.
            // The picker stays here (locked) for when they switch back.
            if (!users.switchTo(userId)) toast("Couldn't open ${profile.name}")
            return
        }
        Session.profileId = profile.id
        finish()
    }

    // Back can't skip the profile screen.
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean =
        keyCode == KeyEvent.KEYCODE_BACK || super.onKeyDown(keyCode, event)
}
