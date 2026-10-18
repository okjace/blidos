package com.blidos.launcher.ui

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.os.Bundle
import android.text.InputFilter
import android.view.Gravity
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import com.blidos.launcher.Session
import com.blidos.launcher.data.Profile
import com.blidos.launcher.data.ProfileStore
import com.blidos.launcher.data.UserControl

/** Owner-only screen for adding profiles, setting PINs and setting up Kids profiles. */
class ProfilesActivity : Activity() {
    private lateinit var store: ProfileStore
    private lateinit var users: UserControl
    private lateinit var row: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = ProfileStore(this)
        users = UserControl(this)
        if (!users.isSystemUser || Session.profileId?.let(store::get)?.isOwner != true) {
            finish()
            return
        }

        val body = screen("Profiles")
        body.addView(label(
            "Choose a profile to rename it, lock it with a PIN, or turn it into a Kids profile " +
                "that can only open the apps you pick." +
                if (users.isAvailable) " Every profile has its own apps, data and Google account." else "",
            17f, Palette.TEXT_DIM,
        ).apply { setPadding(0, dp(8), 0, dp(24)) })

        row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(16), 0, dp(16))
            clipChildren = false
            clipToPadding = false
        }
        body.addView(HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            clipChildren = false
            addView(row)
        })
        render()
    }

    private fun render() {
        val focusedIndex = row.indexOfChild(row.focusedChild).coerceAtLeast(0)
        row.removeAllViews()
        store.all().forEach { profile -> row.addView(profileCard(profile, profile.caption()) { showOptions(profile.id) }) }
        if (store.canAdd()) row.addView(addCard())
        row.getChildAt(focusedIndex.coerceAtMost(row.childCount - 1))?.requestFocus()
    }

    private fun addCard() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        isFocusable = true
        isClickable = true
        setPadding(dp(16), dp(20), dp(16), dp(20))
        background = tileBackground(Color.TRANSPARENT, dp(20))
        addView(label("+", 48f, bold = true).apply {
            gravity = Gravity.CENTER
            background = tileBackground(Palette.SURFACE_HI, dp(52))
        }, LinearLayout.LayoutParams(dp(104), dp(104)))
        addView(label("Add profile", 20f, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(14), 0, 0)
        })
        setOnClickListener {
            promptName("New profile", "") { name ->
                if (users.isAvailable) {
                    // A real Android user, so the profile gets its own apps, data and Google account.
                    val userId = users.createUser(name)
                    if (userId == null) {
                        toast("Couldn't create $name")
                        return@promptName
                    }
                    store.add(name, userId)
                } else {
                    store.add(name)
                }
                render()
            }
        }
        focusZoom(1.1f)
        layoutParams = LinearLayout.LayoutParams(dp(180), WRAP).apply {
            marginStart = dp(12)
            marginEnd = dp(12)
        }
    }

    private fun showOptions(id: String) {
        val profile = store.get(id) ?: return
        val actions = mutableListOf<Pair<String, () -> Unit>>()

        actions += "Rename" to {
            promptName("Rename profile", profile.name) { name ->
                store.edit(id) { it.copy(name = name) }
                profile.userId?.let { users.setUserName(it, name) }
                render()
            }
        }
        if (profile.hasPin) {
            actions += "Change PIN" to { setPin(profile) }
            actions += "Remove PIN" to {
                store.clearPin(id)
                toast("PIN removed")
                render()
            }
        } else {
            actions += "Set PIN" to { setPin(profile) }
        }
        if (!profile.isOwner) {
            actions += (if (profile.isKids) "Turn off Kids mode" else "Turn on Kids mode") to {
                store.edit(id) { it.copy(isKids = !it.isKids) }
                profile.userId?.let { userId ->
                    UserControl.KIDS_RESTRICTIONS.forEach { users.setRestriction(userId, it, !profile.isKids) }
                }
                render()
                if (!profile.isKids) chooseApps(id)
            }
        }
        if (profile.isKids) actions += "Choose allowed apps" to { chooseApps(id) }
        actions += "Change color" to {
            store.edit(id) { it.copy(colorIndex = (it.colorIndex + 1) % Palette.profileColors.size) }
            render()
        }
        if (!profile.isOwner) actions += "Delete profile" to { confirmDelete(profile) }

        AlertDialog.Builder(this, DIALOG_THEME)
            .setTitle(profile.name)
            .setItems(actions.map { it.first }.toTypedArray()) { _, which -> actions[which].second() }
            .show()
    }

    private fun setPin(profile: Profile) {
        PinDialog(this, "New PIN", "Pick 4 digits for ${profile.name}") { first ->
            PinDialog(this, "Confirm PIN", "Enter the same 4 digits again") { second ->
                if (second != first) {
                    "Those didn't match. Try again, or press Back to start over."
                } else {
                    store.setPin(profile.id, second)
                    toast("PIN saved for ${profile.name}")
                    render()
                    null
                }
            }.show()
            null
        }.show()
    }

    private fun chooseApps(id: String) {
        val profile = store.get(id) ?: return
        // Kids never get the Play Store or system settings (which can factory-reset the TV).
        val apps = AppRepository.load(this).filter { it.packageName !in AppRepository.ADULT_ONLY }
        val checked = BooleanArray(apps.size) { apps[it].packageName in profile.allowedApps }
        AlertDialog.Builder(this, DIALOG_THEME)
            .setTitle("Apps ${profile.name} can open")
            .setMultiChoiceItems(apps.map { it.label }.toTypedArray(), checked) { _, which, isChecked ->
                checked[which] = isChecked
            }
            .setPositiveButton("Save") { _, _ ->
                val allowed = apps.filterIndexed { i, _ -> checked[i] }.map { it.packageName }.toSet()
                store.edit(id) { it.copy(allowedApps = allowed) }
                toast("Saved ${allowed.size} apps")
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun confirmDelete(profile: Profile) {
        AlertDialog.Builder(this, DIALOG_THEME)
            .setTitle("Delete ${profile.name}?")
            .setMessage(
                if (profile.userId != null) "This deletes ${profile.name}'s apps, data and Google account from this TV."
                else "This removes the profile and its settings."
            )
            .setPositiveButton("Delete") { _, _ ->
                profile.userId?.let { if (!users.removeUser(it)) toast("Couldn't remove all of ${profile.name}'s data") }
                store.delete(profile.id)
                render()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun promptName(title: String, initial: String, onDone: (String) -> Unit) {
        val input = EditText(this).apply {
            setText(initial)
            setSingleLine()
            filters = arrayOf(InputFilter.LengthFilter(20))
            setSelection(text.length)
        }
        val wrapper = FrameLayout(this).apply {
            setPadding(dp(24), dp(8), dp(24), 0)
            addView(input)
        }
        AlertDialog.Builder(this, DIALOG_THEME)
            .setTitle(title)
            .setView(wrapper)
            .setPositiveButton("Save") { _, _ ->
                val name = input.text.toString().trim()
                if (name.isNotEmpty()) onDone(name)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
}
