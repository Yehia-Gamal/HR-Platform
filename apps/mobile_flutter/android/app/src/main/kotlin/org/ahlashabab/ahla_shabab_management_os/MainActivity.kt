package org.ahlashabab.ahla_shabab_management_os

import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ahlashabab/urgent_notification",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "createNotificationChannel" -> {
                    UrgentNotificationManager.createChannel(this)
                    result.success(true)
                }
                "showUrgentNotification" -> {
                    val started = UrgentAlarmService.start(
                        context = this,
                        requestId = call.argument<String>("requestId").orEmpty(),
                        notificationId = call.argument<String>("notificationId"),
                        title = call.argument<String>("title") ?: "طلب موقع عاجل",
                        body = call.argument<String>("body")
                            ?: "الإدارة تطلب التحقق من موقعك الآن",
                    )
                    result.success(started)
                }
                "stopUrgentNotification" -> {
                    UrgentAlarmService.stop(
                        context = this,
                        requestId = call.argument<String>("requestId"),
                    )
                    result.success(true)
                }
                "consumePendingFcmToken" -> {
                    val preferences = getSharedPreferences(
                        UrgentLocationMessagingService.PUSH_PREFERENCES,
                        Context.MODE_PRIVATE,
                    )
                    val token = preferences.getString(
                        UrgentLocationMessagingService.PENDING_TOKEN,
                        null,
                    )
                    if (token != null) {
                        preferences.edit()
                            .remove(UrgentLocationMessagingService.PENDING_TOKEN)
                            .apply()
                    }
                    result.success(token)
                }
                else -> result.notImplemented()
            }
        }
    }
}
