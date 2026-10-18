package com.blidos.launcher.ui

import android.animation.ObjectAnimator
import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.blidos.launcher.data.ProfileStore

/**
 * On-screen number pad for entering a 4-digit PIN with the remote's D-pad
 * (or its number keys, if it has them).
 *
 * [onSubmit] gets the PIN and returns null to accept it and close, or an error message to show.
 */
class PinDialog(
    context: Context,
    private val title: String,
    private val subtitle: String? = null,
    private val onSubmit: (String) -> String?,
) : Dialog(context, android.R.style.Theme_DeviceDefault_Dialog_NoActionBar) {

    private val entered = StringBuilder()
    private val dots = mutableListOf<View>()
    private lateinit var error: TextView
    private lateinit var panel: LinearLayout
    private var submitting = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val ctx = context

        panel = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(ctx.dp(40), ctx.dp(32), ctx.dp(40), ctx.dp(32))
            background = GradientDrawable().apply {
                setColor(Palette.SURFACE)
                cornerRadius = ctx.dp(20).toFloat()
            }
            clipChildren = false
            clipToPadding = false
        }
        panel.addView(ctx.label(title, 24f, bold = true).apply { gravity = Gravity.CENTER })
        subtitle?.let {
            panel.addView(ctx.label(it, 15f, Palette.TEXT_DIM).apply {
                gravity = Gravity.CENTER
                setPadding(0, ctx.dp(6), 0, 0)
            })
        }

        val dotRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, ctx.dp(24), 0, ctx.dp(8))
        }
        repeat(ProfileStore.PIN_LENGTH) {
            val dot = View(ctx)
            dots += dot
            dotRow.addView(dot, LinearLayout.LayoutParams(ctx.dp(18), ctx.dp(18)).apply {
                marginStart = ctx.dp(10)
                marginEnd = ctx.dp(10)
            })
        }
        panel.addView(dotRow)

        error = ctx.label("", 14f, Palette.ERROR).apply {
            gravity = Gravity.CENTER
            minHeight = ctx.dp(22)
        }
        panel.addView(error)

        val grid = GridLayout(ctx).apply {
            columnCount = 3
            setPadding(0, ctx.dp(12), 0, 0)
            clipChildren = false
            clipToPadding = false
        }
        listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "Clear", "0", "Delete").forEach { key ->
            val button = ctx.label(key, if (key.length == 1) 24f else 15f, bold = true).apply {
                gravity = Gravity.CENTER
                isFocusable = true
                isClickable = true
                background = ctx.tileBackground(Palette.SURFACE_HI, ctx.dp(12))
                setOnClickListener { press(key) }
                focusZoom(1.08f)
            }
            val cell = GridLayout.spec(GridLayout.UNDEFINED, GridLayout.FILL)
            grid.addView(button, GridLayout.LayoutParams(cell, cell).apply {
                width = ctx.dp(92)
                height = ctx.dp(60)
                setMargins(ctx.dp(6), ctx.dp(6), ctx.dp(6), ctx.dp(6))
            })
        }
        panel.addView(grid)

        setContentView(panel)
        window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        updateDots()

        setOnKeyListener { _, keyCode, event ->
            if (event.action != KeyEvent.ACTION_DOWN) return@setOnKeyListener false
            when (keyCode) {
                in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> press((keyCode - KeyEvent.KEYCODE_0).toString())
                in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9 -> press((keyCode - KeyEvent.KEYCODE_NUMPAD_0).toString())
                KeyEvent.KEYCODE_DEL -> press("Delete")
                else -> return@setOnKeyListener false
            }
            true
        }
        grid.getChildAt(4).requestFocus()
    }

    private fun press(key: String) {
        if (submitting) return
        when (key) {
            "Clear" -> entered.clear()
            "Delete" -> if (entered.isNotEmpty()) entered.deleteCharAt(entered.length - 1)
            else -> if (entered.length < ProfileStore.PIN_LENGTH) entered.append(key)
        }
        error.text = ""
        updateDots()
        if (entered.length == ProfileStore.PIN_LENGTH) {
            submitting = true
            // Short pause so the last dot fills in before we check.
            panel.postDelayed({ submit() }, 150)
        }
    }

    private fun submit() {
        val message = onSubmit(entered.toString())
        submitting = false
        if (message == null) {
            dismiss()
            return
        }
        entered.clear()
        updateDots()
        error.text = message
        ObjectAnimator.ofFloat(panel, "translationX", 0f, 24f, -24f, 14f, -14f, 0f)
            .setDuration(320)
            .start()
    }

    private fun updateDots() {
        dots.forEachIndexed { i, dot ->
            dot.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                if (i < entered.length) setColor(Color.WHITE) else setStroke(context.dp(2), Color.WHITE)
            }
        }
    }
}
