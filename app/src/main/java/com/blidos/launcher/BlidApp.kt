package com.blidos.launcher

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import com.blidos.launcher.data.ProfileProvider
import com.blidos.launcher.data.UserControl
import com.blidos.launcher.ui.registerSystemReceiver

/** Who is signed in right now. Kept only in memory, so a restart always asks again. */
object Session {
    @Volatile
    var profileId: String? = null

    fun lock() {
        profileId = null
    }
}

class BlidApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Turning the TV off signs the current profile out.
        registerSystemReceiver(object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                Session.lock()
                // In a profile's own Android user, go back to the picker in user 0.
                val users = UserControl(context)
                if (!users.isSystemUser && users.isAvailable && users.currentUserId() == users.myUserId) {
                    ProfileProvider.lockOwnerSession(context)
                    users.switchTo(0)
                }
            }
        }, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }
}
