package org.ahlashabab.ahla_shabab_management_os

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var deepLinkEvents: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // قناة لإرسال deep links البدئية والجديدة إلى Flutter.
        // يحلّ مشكلة الشاشة السوداء: عندما يضغط المستخدم على إشعار (بصمة/موقع/طلب)
        // والـتطبيق مغلق، يصل intent إلى onCreate لكن GoRouter لا يلتقطه تلقائياً.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ahlashabab/deep_links",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deepLinkEvents = events
                // إرسال أي deep link مُعلَّق عند بدء الـ listen — يغطي Cold Start
                // من notification بعد أن يبني Flutter الشجرة.
                val pending = consumePendingDeepLink()
                if (pending != null) events?.success(pending)
            }
            override fun onCancel(arguments: Any?) {
                deepLinkEvents = null
            }
        })

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

    /**
     * Capture deep links delivered via ACTION_VIEW (custom scheme أو HTTPS).
     * يُستدعى عند Cold Start وعند warm start عبر onNewIntent (singleTop).
     * هذا يحلّ مشكلة "الشاشة السوداء" عند الضغط على إشعار والتطبيق في الخلفية/مغلق.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureDeepLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureDeepLink(intent)
    }

    private fun captureDeepLink(incoming: Intent?) {
        if (incoming?.action != Intent.ACTION_VIEW) return
        val uri = incoming.data ?: return
        val scheme = uri.scheme ?: return
        val isKnown = when (scheme) {
            "ahlashabab" -> true
            "https" -> uri.host == "ahla-shabab-management-os.vercel.app"
            else -> false
        }
        if (!isKnown) return
        val link = uri.toString()
        if (deepLinkEvents != null) {
            deepLinkEvents?.success(link)
        } else {
            pendingDeepLink = link
        }
    }

    private companion object {
        // deep link مُخزّن مؤقتاً عند بدء التطبيق قبل أن يبدأ Flutter بالاستماع.
        @Volatile
        private var pendingDeepLink: String? = null

        private fun consumePendingDeepLink(): String? {
            val link = pendingDeepLink
            pendingDeepLink = null
            return link
        }
    }
}
