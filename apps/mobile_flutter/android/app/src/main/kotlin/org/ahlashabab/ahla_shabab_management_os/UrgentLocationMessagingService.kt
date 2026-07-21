package org.ahlashabab.ahla_shabab_management_os

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/** Handles urgent location FCM messages without waiting for a Dart isolate. */
class UrgentLocationMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val urgent = data["kind"] == "live_location_request" ||
            data["fullScreenIntent"] == "true"
        if (!urgent) {
            super.onMessageReceived(message)
            return
        }

        UrgentNotificationManager.show(
            context = this,
            requestId = data["requestId"].orEmpty(),
            notificationId = data["notificationId"],
            title = data["title"] ?: message.notification?.title ?: "طلب موقع عاجل",
            body = data["body"]
                ?: message.notification?.body
                ?: "الإدارة تطلب التحقق من موقعك الآن",
        )
    }

    override fun onNewToken(token: String) {
        getSharedPreferences(PUSH_PREFERENCES, MODE_PRIVATE)
            .edit()
            .putString(PENDING_TOKEN, token)
            .apply()
        super.onNewToken(token)
    }

    companion object {
        const val PUSH_PREFERENCES = "native_push_state"
        const val PENDING_TOKEN = "pending_fcm_token"
    }
}
