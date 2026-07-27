package org.ahlashabab.ahla_shabab_management_os

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.app.Activity

/**
 * شاشة كاملة تظهر فوق شاشة القفل وخارج التطبيق عند ورود طلب موقع عاجل.
 * تعمل كمنبه: صوت عالٍ متكرر + اهتزاز مستمر حتى يتفاعل المستخدم.
 * عند الضغط على "أرسل موقعي" → يفتح Flutter مع deep link.
 */
class LocationRequestFullActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // إظهار فوق شاشة القفل + تشغيل الشاشة
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        } else {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            km.requestDismissKeyguard(this, null)
        }

        val requestId = intent.getStringExtra(EXTRA_REQUEST_ID) ?: ""
        val notifId = intent.getStringExtra(EXTRA_NOTIFICATION_ID)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "طلب موقع عاجل من الإدارة"
        val body = intent.getStringExtra(EXTRA_BODY)
            ?: "المدير التنفيذي يطلب التحقق من موقعك الآن"

        // Keep the native foreground alarm alive even if Android recreated this screen.
        UrgentAlarmService.start(this, requestId, notifId, title, body)

        // ── بناء الواجهة ──────────────────────────────────────────────
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF140008.toInt())
            setPadding(60, 80, 60, 60)
        }

        // أيقونة تحذير
        val warningBar = TextView(this).apply {
            text = "⚠  طلب موقع عاجل من الإدارة"
            textSize = 16f
            setTextColor(0xFFFFFFFF.toInt())
            setBackgroundColor(0xFFB71C1C.toInt())
            gravity = Gravity.CENTER
            setPadding(20, 28, 20, 28)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        val warningParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        )
        root.addView(warningBar, warningParams)

        // عنوان
        val titleView = TextView(this).apply {
            text = title
            textSize = 28f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(0, 80, 0, 20)
        }
        root.addView(titleView)

        // وصف
        val bodyView = TextView(this).apply {
            text = body
            textSize = 17f
            setTextColor(0xB3FFFFFF.toInt())
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 60)
            setLineSpacing(8f, 1f)
        }
        root.addView(bodyView)

        // زر إرسال الموقع
        val sendButton = Button(this).apply {
            text = "◀  أرسل موقعي الآن"
            textSize = 20f
            setTextColor(0xFFFFFFFF.toInt())
            setBackgroundColor(0xFFE53935.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(40, 40, 40, 40)
            setOnClickListener { onSend(requestId, notifId) }
        }
        val sendParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { setMargins(0, 0, 0, 30) }
        root.addView(sendButton, sendParams)

        // زر رفض
        val rejectButton = Button(this).apply {
            text = "رفض الطلب"
            textSize = 16f
            setTextColor(0x60FFFFFF.toInt())
            setBackgroundColor(0x00000000)
            setPadding(40, 30, 40, 30)
            setOnClickListener { onReject(requestId, notifId) }
        }
        root.addView(rejectButton)

        val scroll = ScrollView(this).apply {
            setBackgroundColor(0xFF140008.toInt())
            addView(root)
        }
        setContentView(scroll)

    }

    private fun onSend(requestId: String, notifId: String?) {
        // Stop the alarm BEFORE navigating to Flutter.
        UrgentAlarmService.stop(this, requestId)

        // فتح Flutter مع deep link لشاشة طلب الموقع
        val deepLink = Uri.parse(
            "https://ahla-shabab-management-os.vercel.app/action/live_location_request/$requestId"
        ).buildUpon().apply {
            if (!notifId.isNullOrBlank()) {
                appendQueryParameter("notification_id", notifId)
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
        finish()
    }

    private fun onReject(requestId: String, notifId: String?) {
        // Stop the alarm BEFORE navigating to Flutter.
        UrgentAlarmService.stop(this, requestId)

        // فتح Flutter مع deep link — الشاشة ستعرض حالة الرفض
        val deepLink = Uri.parse(
            "https://ahla-shabab-management-os.vercel.app/action/live_location_request/$requestId"
        ).buildUpon().apply {
            appendQueryParameter("action", "reject")
            if (!notifId.isNullOrBlank()) {
                appendQueryParameter("notification_id", notifId)
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
        finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        recreate()
    }

    override fun onBackPressed() {
        // منع الخروج بزر الرجوع — يجب التفاعل مع الطلب
    }

    companion object {
        const val EXTRA_REQUEST_ID = "request_id"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
    }
}
