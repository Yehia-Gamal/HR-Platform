package org.ahlashabab.ahla_shabab_management_os

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

/**
 * Full-screen Activity launched by full-screen intent notification.
 * Shows the location request overlay immediately, even over the lock screen.
 */
class LocationRequestFullActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Show over lock screen on Android < 10
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        } else {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            km.requestDismissKeyguard(this, null)
        }

        super.onCreate(savedInstanceState)

        // Forward the deep link to Flutter
        val requestId = intent.getStringExtra(EXTRA_REQUEST_ID)
        if (requestId != null) {
            val notificationId = intent.getStringExtra(EXTRA_NOTIFICATION_ID)
            val deepLink = android.net.Uri.parse(
                "https://ahla-shabab-management-os.vercel.app/action/live_location_request/$requestId",
            ).buildUpon().apply {
                if (!notificationId.isNullOrBlank()) {
                    appendQueryParameter("notification_id", notificationId)
                }
            }.build()
            val flutterIntent = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = deepLink
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            startActivity(flutterIntent)
        }
        finish()
    }

    companion object {
        const val EXTRA_REQUEST_ID = "request_id"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
    }
}
