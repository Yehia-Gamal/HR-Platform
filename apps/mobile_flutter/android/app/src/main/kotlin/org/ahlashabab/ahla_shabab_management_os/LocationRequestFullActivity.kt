package org.ahlashabab.ahla_shabab_management_os

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.animation.ObjectAnimator
import java.lang.ref.WeakReference

/**
 * شاشة كاملة تظهر فوق شاشة القفل وخارج التطبيق عند ورود طلب موقع عاجل.
 * تعمل كمنبه: صوت عالٍ متكرر + اهتزاز مستمر + وميض فلاش حتى يتفاعل المستخدم.
 *
 * V20: إعادة تصميم الواجهة لتطابق شاشة Flutter الداخلية ([LocationIncomingOverlay])
 * المستخدمة عندما يكون التطبيق في المقدمة — خلفية حمراء داكنة، أيقونة موقع نابضة،
 * زر إرسال أحمر بزوايا دائرية، وزر رفض بإطار خافت. أُزيل وميض الشاشة الكامل
 * (تبديل الخلفية) الذي كان يبدو غير منسّق، واستُبدل بنبض ناعم على الأيقونة.
 *
 * عند الضغط على "أرسل موقعي" → يفتح Flutter مع deep link.
 */
class LocationRequestFullActivity : Activity() {

    private var iconFrame: FrameLayout? = null
    private var pulseAnimator: ObjectAnimator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = WeakReference(this)

        // منع زر الرجوع على Android 13+ — enableOnBackInvokedCallback="true"
        // يجعل onBackPressed() كود ميت، لازم نسجل callback جديد.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) {
                // فارغ عمداً — المستخدم لازم يتفاعل مع أزرار إرسال/رفض.
            }
        }

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
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "طلب تحقق من الموقع"
        val body = intent.getStringExtra(EXTRA_BODY)
            ?: "الإدارة تطلب التحقق من موقعك الآن"

        // V25: إذا سبق أن ردّ المستخدم على هذا الطلب (قبول/إرسال/رفض) —
        // لا نعيد الرنين ولا نعيد فتح الشاشة الكاملة حتى لو أُعيد تسليم
        // نفس الـ intent (FCM مكرر / إعادة إنشاء من النظام).
        if (requestId.isNotEmpty() && UrgentAlarmService.isHandled(this, requestId)) {
            UrgentAlarmService.stop(this, requestId)
            finish()
            return
        }

        // Keep the native foreground alarm alive even if Android recreated this screen.
        UrgentAlarmService.start(this, requestId, notifId, title, body)

        setContentView(buildUi(title, body, requestId, notifId))
        startPulse()
    }

    private fun buildUi(
        title: String,
        body: String,
        requestId: String,
        notifId: String?,
    ): ScrollView {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF140008.toInt())
        }

        // ── حقل الطوارئ العلوي ───────────────────────────────────────────
        val warningBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xFFB71C1C.toInt())
            setPadding(20, 12, 20, 12)
        }
        val warningText = TextView(this).apply {
            text = "⚠   طلب موقع عاجل من الإدارة"
            textSize = 14f
            setTextColor(0xFFFFFFFF.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        warningBar.addView(warningText)
        root.addView(
            warningBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        // ── المحتوى الرئيسي ─────────────────────────────────────────────
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(28, 44, 28, 36)
        }

        // أيقونة موقع نابضة داخل حلقة
        iconFrame = FrameLayout(this).apply {
            setBackgroundResource(R.drawable.bg_urgent_circle)
            val icon = ImageView(this@LocationRequestFullActivity).apply {
                setImageResource(R.drawable.ic_location_pulse)
            }
            addView(
                icon,
                FrameLayout.LayoutParams(
                    130,
                    130,
                    Gravity.CENTER,
                ),
            )
        }
        content.addView(
            iconFrame,
            LinearLayout.LayoutParams(170, 170),
        )

        // العنوان
        val titleView = TextView(this).apply {
            text = title
            textSize = 26f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(0, 40, 0, 12)
        }
        content.addView(titleView, matchWrap())

        // الوصف
        val bodyView = TextView(this).apply {
            text = body
            textSize = 16f
            setTextColor(0xB3FFFFFF.toInt())
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 18)
            setLineSpacing(8f, 1f)
        }
        content.addView(bodyView, matchWrap())

        // شارة وضع الطلب (لقطة موقع فورية)
        val chip = TextView(this).apply {
            text = "لقطة موقع فورية"
            textSize = 14f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            setBackgroundResource(R.drawable.bg_urgent_chip)
            setPadding(22, 11, 22, 11)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        content.addView(chip, matchWrap())

        root.addView(
            content,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        // ── أزرار الاستجابة ─────────────────────────────────────────────
        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 0, 24, 32)
        }

        val sendButton = TextView(this).apply {
            text = "أرسل موقعي الآن"
            textSize = 19f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setBackgroundResource(R.drawable.bg_urgent_send_button)
            setPadding(0, 20, 0, 20)
            isClickable = true
            isFocusable = true
            setOnClickListener { onSend(requestId, notifId) }
        }
        buttons.addView(sendButton, matchWrap().apply { setMargins(0, 0, 0, 14) })

        val rejectButton = TextView(this).apply {
            text = "رفض الطلب"
            textSize = 16f
            setTextColor(0x60FFFFFF.toInt())
            gravity = Gravity.CENTER
            setBackgroundResource(R.drawable.bg_urgent_reject_button)
            setPadding(0, 15, 0, 15)
            isClickable = true
            isFocusable = true
            setOnClickListener { onReject(requestId, notifId) }
        }
        buttons.addView(rejectButton, matchWrap())

        root.addView(
            buttons,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        return ScrollView(this).apply {
            setBackgroundColor(0xFF140008.toInt())
            addView(root)
        }
    }

    private fun matchWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
    )

    /** نبض ناعم على أيقونة الموقع (مقياس حلقة متذبذب) بدل وميض الشاشة القوي. */
    private fun startPulse() {
        val frame = iconFrame ?: return
        pulseAnimator = ObjectAnimator.ofFloat(frame, View.SCALE_X, 1f, 1.12f).apply {
            duration = 700
            repeatMode = ObjectAnimator.REVERSE
            repeatCount = ObjectAnimator.INFINITE
            interpolator = OvershootInterpolator(1.2f)
            start()
        }
        // لا ننبض المحور X فقط — نطابق المقياس على المحورين معاً عبر الاعتماد على
        // Evaluation. أسهل نمط ثابت: نبض X/Y معاً.
        ObjectAnimator.ofFloat(frame, View.SCALE_Y, 1f, 1.12f).apply {
            duration = 700
            repeatMode = ObjectAnimator.REVERSE
            repeatCount = ObjectAnimator.INFINITE
            interpolator = OvershootInterpolator(1.2f)
            start()
        }
    }

    private fun stopPulse() {
        pulseAnimator?.cancel()
        pulseAnimator = null
    }

    private fun onSend(requestId: String, notifId: String?) {
        stopPulse()
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
        stopPulse()
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
        // V25: لا نعيد إنشاء الشاشة (التي تعيد تشغيل المنبه) لطلب سبق
        // معالجته — أغلقها فوراً.
        val requestId = intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty()
        if (requestId.isNotEmpty() && UrgentAlarmService.isHandled(this, requestId)) {
            UrgentAlarmService.stop(this, requestId)
            finish()
        } else {
            recreate()
        }
    }

    override fun onDestroy() {
        stopPulse()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // منع الخروج بزر الرجوع — يجب التفاعل مع الطلب.
    }

    companion object {
        const val EXTRA_REQUEST_ID = "request_id"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        /**
         * Weak reference to the currently-visible instance.
         * Used by [dismissIfActive] so the Flutter overlay can close this
         * native screen when it takes over the urgent-request flow.
         */
        private var activeInstance: java.lang.ref.WeakReference<LocationRequestFullActivity>? = null

        /** Finish the activity if it's still alive — called from the MethodChannel. */
        fun dismissIfActive() {
            activeInstance?.get()?.finish()
            activeInstance = null
        }
    }
}
