package org.ahlashabab.ahla_shabab_management_os

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.AudioAttributes as AudioAttr
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Foreground alarm for urgent location requests.
 *
 * FCM may arrive while Flutter is stopped, so the alarm is entirely native.
 * It keeps a partial wake lock, loops the alarm sound, vibrates, blinks the
 * camera flash, and owns an ongoing full-screen notification until the
 * employee responds OR the safety timeout fires.
 *
 * V19: Adds camera flash/torch blinking + maximises STREAM_ALARM volume
 * (with safe save/restore via SharedPreferences so a killed process can
 * restore on next start). This makes the alarm impossible to miss.
 */
class UrgentAlarmService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var activeNotificationId: Int? = null
    private val handler = Handler(Looper.getMainLooper())
    private var cameraManager: CameraManager? = null
    private var flashCameraId: String? = null
    private var flashOn = false
    private var originalAlarmVolume = -1
    private val safetyTimeout = Runnable {
        Log.w(TAG, "Safety timeout reached — auto-stopping alarm")
        stopAlarmAndService()
    }

    private val flashBlinker = Runnable { toggleFlash() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopAlarmAndService()
            return START_NOT_STICKY
        }

        val requestId = intent?.getStringExtra(EXTRA_REQUEST_ID).orEmpty()
        if (requestId.isBlank()) {
            stopAlarmAndService()
            return START_NOT_STICKY
        }

        val notificationId = intent?.getStringExtra(EXTRA_NOTIFICATION_ID)
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "طلب موقع عاجل من الإدارة"
        val body = intent?.getStringExtra(EXTRA_BODY)
            ?: "الإدارة تطلب التحقق من موقعك وإرساله الآن"
        val systemNotificationId = UrgentNotificationManager.notificationId(requestId)

        activeNotificationId
            ?.takeIf { it != systemNotificationId }
            ?.let { getSystemService(NotificationManager::class.java).cancel(it) }
        activeNotificationId = systemNotificationId

        val notification = UrgentNotificationManager.buildNotification(
            context = this,
            requestId = requestId,
            notificationId = notificationId,
            title = title,
            body = body,
            forForegroundService = true,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                systemNotificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(systemNotificationId, notification)
        }

        acquireWakeLock()
        startRepeatingAlarm()
        startFlashBlinking()

        // Reset the safety timeout on every new start command.
        handler.removeCallbacks(safetyTimeout)
        handler.postDelayed(safetyTimeout, ALARM_TIMEOUT_MS)

        // V25: START_NOT_STICKY بدل START_REDELIVER_INTENT — قتل النظام
        // للخدمة لا يجب أن يعيد تسليم نفس الـ intent ويعيد الرنين بعد أن
        // تفاعل المستخدم مع الطلب.
        return START_NOT_STICKY
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:urgent-location-alarm",
        ).apply {
            setReferenceCounted(false)
            acquire(ALARM_TIMEOUT_MS + 30_000L)
        }
    }

    // ── Camera flash blinking ──────────────────────────────────────────
    // Uses Camera2 torch mode to blink the flash in sync with the alarm
    // pattern: 800ms on, 250ms off, repeating.
    private fun startFlashBlinking() {
        try {
            cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            flashCameraId = cameraManager?.cameraIdList?.firstOrNull { id ->
                cameraManager?.getCameraCharacteristics(id)
                    ?.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
            if (flashCameraId != null) {
                handler.post(flashBlinker)
            } else {
                Log.i(TAG, "No camera with flash — skipping torch blink")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Flash blink init failed", e)
        }
    }

    private fun toggleFlash() {
        val cm = cameraManager ?: return
        val id = flashCameraId ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm.setTorchMode(id, flashOn)
            } else {
                @Suppress("DEPRECATION")
                cm.setTorchMode(id, true)
            }
            flashOn = !flashOn
            // Blink pattern: 800ms on, 250ms off — matches vibration rhythm.
            handler.postDelayed(flashBlinker, if (flashOn) 800L else 250L)
        } catch (e: Exception) {
            // Camera may be in use by another app — stop trying.
            Log.w(TAG, "Flash toggle failed (camera busy?)", e)
            flashOn = false
        }
    }

    private fun stopFlashBlinking() {
        handler.removeCallbacks(flashBlinker)
        // Ensure flash is OFF.
        val cm = cameraManager ?: return
        val id = flashCameraId ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm.setTorchMode(id, false)
            }
        } catch (_: Exception) {
            // Camera may already be released.
        }
        flashOn = false
        cameraManager = null
        flashCameraId = null
    }

    // ── Alarm sound + volume ───────────────────────────────────────────
    private fun startRepeatingAlarm() {
        val manager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager = manager
        requestAlarmAudioFocus(manager)

        // V19: Maximise STREAM_ALARM volume so the alarm is as loud as possible.
        // Save the original to SharedPreferences so we can restore it even
        // if the process is killed (restoreStuckVolumeIfNeeded on next start).
        val maxVolume = manager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        originalAlarmVolume = manager.getStreamVolume(AudioManager.STREAM_ALARM)
        if (originalAlarmVolume < maxVolume) {
            getSharedPreferences("urgent_alarm_prefs", Context.MODE_PRIVATE)
                .edit()
                .putInt("stuck_original_alarm_volume", originalAlarmVolume)
                .apply()
        }
        try {
            manager.setStreamVolume(
                AudioManager.STREAM_ALARM,
                maxVolume,
                0, // no UI sound
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not set alarm volume to max (Do Not Disturb?)", e)
        }

        if (mediaPlayer?.isPlaying != true) {
            val soundUri = android.net.Uri.parse(
                "android.resource://$packageName/${R.raw.urgent_notification}",
            )
            try {
                mediaPlayer = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttr.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    setDataSource(this@UrgentAlarmService, soundUri)
                    setVolume(1f, 1f)
                    isLooping = true
                    prepare()
                    start()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start MediaPlayer — alarm will be silent", e)
                mediaPlayer?.release()
                mediaPlayer = null
            }
        }

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val managerService =
                getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            managerService.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 800, 250, 800, 250, 800, 250, 800, 900)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun requestAlarmAudioFocus(manager: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(
                    AudioAttr.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .setOnAudioFocusChangeListener { }
                .build()
            audioFocusRequest = request
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                { },
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
            )
        }
    }

    private fun stopAlarmAndService() {
        // Release alarm resources FIRST, then remove the foreground notification.
        releaseResources()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        activeNotificationId?.let {
            getSystemService(NotificationManager::class.java).cancel(it)
        }
        stopSelf()
    }

    private fun releaseResources() {
        handler.removeCallbacks(safetyTimeout)
        handler.removeCallbacks(flashBlinker)

        stopFlashBlinking()

        runCatching { mediaPlayer?.stop() }
        mediaPlayer?.release()
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null

        audioManager?.let { manager ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let(manager::abandonAudioFocusRequest)
            }
            // V19: Restore the original alarm volume we boosted.
            if (originalAlarmVolume >= 0) {
                try {
                    manager.setStreamVolume(
                        AudioManager.STREAM_ALARM,
                        originalAlarmVolume,
                        0,
                    )
                } catch (_: Exception) {
                    // DND or other restriction — best effort.
                }
                getSharedPreferences("urgent_alarm_prefs", Context.MODE_PRIVATE)
                    .edit()
                    .remove("stuck_original_alarm_volume")
                    .apply()
            }
        }
        audioFocusRequest = null
        audioManager = null

        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    override fun onDestroy() {
        releaseResources()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "UrgentAlarmService"
        private const val ACTION_START =
            "org.ahlashabab.ahla_shabab_management_os.action.START_URGENT_ALARM"
        private const val ACTION_STOP =
            "org.ahlashabab.ahla_shabab_management_os.action.STOP_URGENT_ALARM"
        private const val EXTRA_REQUEST_ID = "request_id"
        private const val EXTRA_NOTIFICATION_ID = "notification_id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"

        /** Maximum alarm duration before auto-stop (5 minutes). */
        private const val ALARM_TIMEOUT_MS = 5L * 60 * 1000

        private const val PREFS_NAME = "urgent_alarm_prefs"
        private const val HANDLED_PREFIX = "handled_"

        /**
         * V25: هل سبق أن ردّ المستخدم على هذا الطلب (قبول/إرسال/رفض)؟
         * أي FCM متأخر أو مكرر أو إعادة إطلاق للشاشة الكاملة بعد الرد
         * يتجاهل الرنين تماماً.
         */
        fun isHandled(context: Context, requestId: String): Boolean {
            if (requestId.isBlank()) return false
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(HANDLED_PREFIX + requestId, false)
        }

        /**
         * V25: يوسّم الطلب كمُعالَج نهائياً (يُستدعى من Flutter بعد نجاح
         * الرد/الإرسال) — يوقف الخدمة ويُزيل الإشعار ويمنع أي رنين لاحق
         * لنفس الطلب حتى لو أُعيد تسليم FCM.
         */
        fun markHandled(context: Context, requestId: String) {
            if (requestId.isBlank()) return
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(HANDLED_PREFIX + requestId, true)
                .apply()
            stop(context, requestId)
        }

        fun start(
            context: Context,
            requestId: String,
            notificationId: String?,
            title: String,
            body: String,
        ): Boolean {
            if (requestId.isBlank()) return false
            // V25: لا نعيد الرنين لطلب سبق أن ردّ عليه المستخدم — يقطع
            // حلقة FCM المكرر/المتأخر ويمنع إعادة فتح الشاشة الكاملة.
            if (isHandled(context, requestId)) {
                stop(context, requestId)
                return false
            }
            // One-time cleanup: restore any globally-stuck volume from older versions.
            restoreStuckVolumeIfNeeded(context)

            val intent = Intent(context, UrgentAlarmService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_REQUEST_ID, requestId)
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            return try {
                ContextCompat.startForegroundService(context, intent)
                true
            } catch (_: RuntimeException) {
                UrgentNotificationManager.show(
                    context,
                    requestId,
                    notificationId,
                    title,
                    body,
                )
                false
            }
        }

        fun stop(context: Context, requestId: String? = null) {
            context.stopService(Intent(context, UrgentAlarmService::class.java))
            if (!requestId.isNullOrBlank()) {
                context.getSystemService(NotificationManager::class.java)
                    .cancel(UrgentNotificationManager.notificationId(requestId))
            }
        }

        /**
         * One-time migration: if the process was killed while the alarm was
         * active, the STREAM_ALARM volume stayed at max. This restores it.
         */
        private fun restoreStuckVolumeIfNeeded(context: Context) {
            val prefs = context.getSharedPreferences("urgent_alarm_prefs", Context.MODE_PRIVATE)
            val savedVolume = prefs.getInt("stuck_original_alarm_volume", -1)
            if (savedVolume >= 0) {
                try {
                    val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val currentVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
                    val maxVolume = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                    if (currentVolume >= maxVolume && savedVolume < maxVolume) {
                        am.setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0)
                        Log.i(TAG, "Restored stuck alarm volume from $currentVolume to $savedVolume")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to restore stuck volume", e)
                }
                prefs.edit().remove("stuck_original_alarm_volume").apply()
            }
        }
    }
}
