package org.ahlashabab.ahla_shabab_management_os

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
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
                    // أغلق شاشة Kotlin الكاملة إن كانت لا تزال مفتوحة —
                    // يمنع تداخل شاشتين (native + Flutter overlay).
                    LocationRequestFullActivity.dismissIfActive()
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
                "isIgnoringBatteryOptimization" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestIgnoreBatteryOptimization" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                        val intent = Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
