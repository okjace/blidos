package com.blidos.launcher.ui

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Build
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.blidos.launcher.data.Profile
import kotlin.math.roundToInt

object Palette {
    val profileColors = intArrayOf(
        0xFF4F7CFF.toInt(), 0xFFFF6B6B.toInt(), 0xFF2EC4B6.toInt(),
        0xFFFFB627.toInt(), 0xFF9B5DE5.toInt(), 0xFF00BBF9.toInt(),
    )
    const val BG_TOP = 0xFF16203A.toInt()
    const val BG_BOTTOM = 0xFF05070D.toInt()
    const val SURFACE = 0xFF1C2333.toInt()
    const val SURFACE_HI = 0xFF2A3348.toInt()
    const val PLAY_GREEN = 0xFF01875F.toInt()
    const val TEXT = Color.WHITE
    const val TEXT_DIM = 0xB3FFFFFF.toInt()
    const val ERROR = 0xFFFF6B6B.toInt()
}

const val DIALOG_THEME = android.R.style.Theme_DeviceDefault_Dialog_Alert
const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT

fun Context.dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()

fun Context.toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()

fun Context.label(text: CharSequence, sizeSp: Float, color: Int = Palette.TEXT, bold: Boolean = false) =
    TextView(this).apply {
        this.text = text
        setTextColor(color)
        textSize = sizeSp
        if (bold) typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

/** Rounded fill that gets a white outline when focused with the remote. */
fun Context.tileBackground(fill: Int, radius: Int = dp(14)): Drawable {
    fun shape(outlined: Boolean) = GradientDrawable().apply {
        setColor(fill)
        cornerRadius = radius.toFloat()
        if (outlined) setStroke(dp(3), Color.WHITE)
    }
    return StateListDrawable().apply {
        addState(intArrayOf(android.R.attr.state_focused), shape(true))
        addState(intArrayOf(android.R.attr.state_pressed), shape(true))
        addState(intArrayOf(), shape(false))
    }
}

fun Context.screenBackground(): Drawable =
    GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(Palette.BG_TOP, Palette.BG_BOTTOM))

fun View.focusZoom(scale: Float = 1.08f) {
    val lift = context.dp(8).toFloat()
    setOnFocusChangeListener { v, hasFocus ->
        v.animate()
            .scaleX(if (hasFocus) scale else 1f)
            .scaleY(if (hasFocus) scale else 1f)
            .translationZ(if (hasFocus) lift else 0f)
            .setDuration(140)
            .start()
    }
}

fun Context.pillButton(text: String, onClick: () -> Unit): TextView = label(text, 16f, bold = true).apply {
    gravity = Gravity.CENTER
    isFocusable = true
    isClickable = true
    setPadding(dp(24), dp(12), dp(24), dp(12))
    background = tileBackground(Palette.SURFACE_HI, dp(28))
    setOnClickListener { onClick() }
    focusZoom(1.05f)
}

fun Context.buttonRow(vararg buttons: View): LinearLayout = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    setPadding(0, dp(20), 0, dp(8))
    clipChildren = false
    clipToPadding = false
    buttons.forEach { addView(it, LinearLayout.LayoutParams(WRAP, WRAP).apply { marginEnd = dp(16) }) }
}

fun Context.sectionHeader(text: String) =
    label(text, 20f, Palette.TEXT_DIM, bold = true).apply { setPadding(0, dp(28), 0, dp(10)) }

fun Context.listRow(title: String, detail: String, onClick: () -> Unit): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    isFocusable = true
    isClickable = true
    setPadding(dp(24), dp(16), dp(24), dp(16))
    background = tileBackground(Palette.SURFACE, dp(12))
    addView(label(title, 18f, bold = true).apply {
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
    }, LinearLayout.LayoutParams(0, WRAP, 1f))
    addView(label(detail, 15f, Palette.TEXT_DIM).apply { setPadding(dp(16), 0, 0, 0) })
    setOnClickListener { onClick() }
    focusZoom(1.02f)
    layoutParams = LinearLayout.LayoutParams(MATCH, WRAP).apply { bottomMargin = dp(10) }
}

/** Full-screen scrolling page with a big title. Returns the column to add content to. */
fun Activity.screen(title: String): LinearLayout {
    val body = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(64), dp(40), dp(64), dp(40))
        clipChildren = false
        clipToPadding = false
    }
    body.addView(label(title, 34f, bold = true))
    setContentView(ScrollView(this).apply {
        background = screenBackground()
        isFillViewport = true
        clipChildren = false
        addView(body)
    })
    return body
}

fun profileColor(profile: Profile): Int =
    Palette.profileColors[profile.colorIndex.mod(Palette.profileColors.size)]

fun Profile.caption(): String? = listOfNotNull(
    if (isOwner) "Owner" else null,
    if (isKids) "Kids" else null,
    if (hasPin) "PIN locked" else null,
).joinToString(" · ").ifEmpty { null }

fun Context.avatar(profile: Profile, sizeDp: Int): View = FrameLayout(this).apply {
    background = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(profileColor(profile))
    }
    addView(
        label(profile.name.take(1).uppercase(), sizeDp * 0.42f, bold = true).apply { gravity = Gravity.CENTER },
        FrameLayout.LayoutParams(MATCH, MATCH),
    )
    layoutParams = LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp))
}

fun Context.profileCard(profile: Profile, caption: String?, onClick: () -> Unit): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    gravity = Gravity.CENTER_HORIZONTAL
    isFocusable = true
    isClickable = true
    setPadding(dp(16), dp(20), dp(16), dp(20))
    background = tileBackground(Color.TRANSPARENT, dp(20))
    addView(avatar(profile, 104))
    addView(label(profile.name, 20f, bold = true).apply {
        gravity = Gravity.CENTER
        setPadding(0, dp(14), 0, 0)
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
    })
    caption?.let { addView(label(it, 14f, Palette.TEXT_DIM).apply { gravity = Gravity.CENTER }) }
    setOnClickListener { onClick() }
    focusZoom(1.1f)
    layoutParams = LinearLayout.LayoutParams(dp(180), WRAP).apply {
        marginStart = dp(12)
        marginEnd = dp(12)
    }
}

/** Opens the first system settings screen this TV supports. */
fun Context.openSettings(vararg actions: String) {
    for (action in actions) {
        try {
            startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (_: ActivityNotFoundException) {
        }
    }
    toast("That settings screen isn't available on this TV")
}

/** For broadcasts that only the system can send (Wi-Fi, Bluetooth, screen off). */
fun Context.registerSystemReceiver(receiver: BroadcastReceiver, filter: IntentFilter) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
    } else {
        registerReceiver(receiver, filter)
    }
}
