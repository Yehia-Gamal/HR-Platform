package org.ahlashabab.ahla_shabab_management_os

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioFocusRequest
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
 * It keeps a partial wake lock, loops the alarm sound, vibrates, and owns an
 * ongoing full-screen notification until the employee responds OR the safety
 * timeout fires.
 *
 * V18: No longer modifies the global system volume. Uses MediaPlayer volume +
 * USAGE_ALARM audio attributes + IMPORTANCE_MAX channel to play loudly without
 * touching the user's settings. Adds a 5-minute safety timeout so the alarm
 * self-stops if the process survives but the user never interacts.
 */
class UrgentAlarmService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var activeNotificationId: Int? = null
    private val handler = Handler(Looper.getMainLooper())
    private val safetyTimeout = Runnable {
        Log.w(TAG, "Safety timeout reached — auto-stopping alarm")
        stopAlarmAndService()
    }

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

        // Reset the safety timeout on every new start command.
        handler.removeCallbacks(safetyTimeout)
        handler.postDelayed(safetyTimeout, ALARM_TIMEOUT_MS)

        return START_REDELIVER_INTENT
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:urgent-location-alarm",
        ).apply {
            setReferenceCounted(false)
            // Timeout matches the alarm safety timeout + 30s grace period.
            acquire(ALARM_TIMEOUT_MS + 30_000L)
        }
    }

    private fun startRepeatingAlarm() {
        val manager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager = manager
        requestAlarmAudioFocus(manager)

        // ── V18: NO global volume modification ──
        // We rely on USAGE_ALARM audio attributes + MediaPlayer.setVolume(1f, 1f)
        // + IMPORTANCE_MAX notification channel. This is loud enough without
        // touching the user's global STREAM_ALARM volume, which would persist
        // across crashes/kills and annoy the user.

        if (mediaPlayer?.isPlaying != true) {
            val soundUri = android.net.Uri.parse(
                "android.resource://$packageName/${R.raw.urgent_notification}",
            )
            try {
                mediaPlayer = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
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
                    AudioAttributes.Builder()
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

        runCatching { mediaPlayer?.stop() }
        mediaPlayer?.release()
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null

        audioManager?.let { manager ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let(manager::abandonAudioFocusRequest)
            }
            // V18: No volume restoration needed — we never change global volume.
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

        fun start(
            context: Context,
            requestId: String,
            notificationId: String?,
            title: String,
            body: String,
        ): Boolean {
            if (requestId.isBlank()) return false
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
         * V18 one-time migration: the old alarm code would set STREAM_ALARM to
         * max and only restore it in onDestroy(). If the process was killed, the
         * volume stayed at max forever. This checks SharedPreferences for a
         * saved original volume and restores it, then clears the key so it only
         * runs once.
         */
        private fun restoreStuckVolumeIfNeeded(context: Context) {
            val prefs = context.getSharedPreferences("urgent_alarm_prefs", Context.MODE_PRIVATE)
            val savedVolume = prefs.getInt("stuck_original_alarm_volume", -1)
            if (savedVolume >= 0) {
                try {
                    val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val currentVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
                    val maxVolume = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                    // Only restore if volume is still at max (meaning it was stuck).
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
