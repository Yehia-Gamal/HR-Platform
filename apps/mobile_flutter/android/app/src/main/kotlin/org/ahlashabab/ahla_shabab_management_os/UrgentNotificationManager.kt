package org.ahlashabab.ahla_shabab_management_os

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

/** Native notification path used before a Flutter engine or Dart isolate exists. */
object UrgentNotificationManager {
    const val CHANNEL_ID = "urgent_location_v6"
    private const val CHANNEL_NAME = "طلبات الموقع العاجلة"
    private const val CHANNEL_DESCRIPTION =
        "إشعارات طلب الموقع الفوري — صوت عالي متكرر واهتزاز وشاشة كاملة"

    const val GENERAL_CHANNEL_ID = "general_notifications_v2"
    private const val GENERAL_CHANNEL_NAME = "الإشعارات والتنبيهات العامة"
    private const val GENERAL_CHANNEL_DESCRIPTION =
        "إشعارات القرارات، طلبات الموافقة، الغرامات الفورية، والإعلانات الإدارية"

    private val LEGACY_CHANNEL_IDS = listOf(
        "urgent_location_v5",
        "urgent_location_v4",
        "urgent_location_v3",
    )
    private const val VERIFIED_ACTION_BASE =
        "https://ahla-shabab-management-os.vercel.app/action/live_location_request/"

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        // حذف القنوات القديمة — Android لا يرفع أهمية قناة موجودة.
        for (legacyId in LEGACY_CHANNEL_IDS) {
            manager.deleteNotificationChannel(legacyId)
        }

        // 1. إنشاء قناة طلبات الموقع العاجلة (شاشة كاملة + إنذار)
        val existingUrgent = manager.getNotificationChannel(CHANNEL_ID)
        if (existingUrgent == null || existingUrgent.importance < NotificationManager.IMPORTANCE_MAX) {
            if (existingUrgent != null) manager.deleteNotificationChannel(CHANNEL_ID)
            val sound = Uri.parse(
                "android.resource://${context.packageName}/${R.raw.urgent_notification}",
            )
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val urgentChannel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_MAX,
            ).apply {
                description = CHANNEL_DESCRIPTION
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 300, 800, 300, 800, 300, 800)
                setSound(sound, audioAttributes)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
                setShowBadge(true)
            }
            manager.createNotificationChannel(urgentChannel)
        }

        // 2. إنشاء قناة الإشعارات والتنبيهات العامة (صوت النظام القياسي)
        val existingGeneral = manager.getNotificationChannel(GENERAL_CHANNEL_ID)
        if (existingGeneral == null) {
            val generalSound = android.media.RingtoneManager.getDefaultUri(
                android.media.RingtoneManager.TYPE_NOTIFICATION,
            )
            val generalAudioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val generalChannel = NotificationChannel(
                GENERAL_CHANNEL_ID,
                GENERAL_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = GENERAL_CHANNEL_DESCRIPTION
                enableVibration(true)
                setSound(generalSound, generalAudioAttributes)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(true)
            }
            manager.createNotificationChannel(generalChannel)
        }
    }

    fun notificationId(requestId: String): Int =
        requestId.hashCode().and(Int.MAX_VALUE).coerceAtLeast(1)

    /**
     * @param forForegroundService true when the alarm service owns a MediaPlayer
     *   for the sound — the notification itself should be silent to avoid double
     *   audio overlap. false for the fallback path where no MediaPlayer exists
     *   and the notification must carry FLAG_INSISTENT to ring on its own.
     */
    fun buildNotification(
        context: Context,
        requestId: String,
        notificationId: String?,
        title: String,
        body: String,
        forForegroundService: Boolean = false,
    ): Notification {
        require(requestId.isNotBlank()) { "requestId is required" }
        createChannel(context)

        val deepLink = Uri.parse("$VERIFIED_ACTION_BASE$requestId")
            .buildUpon()
            .apply {
                if (!notificationId.isNullOrBlank()) {
                    appendQueryParameter("notification_id", notificationId)
                }
            }
            .build()
        val fullScreenIntent = Intent(context, LocationRequestFullActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = deepLink
            putExtra(LocationRequestFullActivity.EXTRA_REQUEST_ID, requestId)
            putExtra(LocationRequestFullActivity.EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(LocationRequestFullActivity.EXTRA_TITLE, title)
            putExtra(LocationRequestFullActivity.EXTRA_BODY, body)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId(requestId),
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val sound = Uri.parse(
            "android.resource://${context.packageName}/${R.raw.urgent_notification}",
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setPriority(Notification.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(pendingIntent, true)
            .setContentIntent(pendingIntent)
            .addAction(R.drawable.ic_notification, "فتح وإرسال الموقع", pendingIntent)

        if (forForegroundService) {
            // MediaPlayer handles the looping alarm sound — suppress the
            // notification's own alert to avoid double audio overlap.
            builder.setOnlyAlertOnce(true)
        } else {
            // Fallback path (no service / no MediaPlayer). The notification
            // itself must carry the sound + FLAG_INSISTENT so it rings.
            builder.setOnlyAlertOnce(false)
                .setSound(sound)
                .setVibrate(longArrayOf(0, 800, 300, 800, 300, 800, 300, 800))
        }

        val notification = builder.build()

        // FLAG_NO_CLEAR prevents swipe-dismiss. FLAG_INSISTENT is only added
        // for the fallback (non-service) path to repeat the notification sound.
        notification.flags = notification.flags or Notification.FLAG_NO_CLEAR
        if (!forForegroundService) {
            notification.flags = notification.flags or Notification.FLAG_INSISTENT
        }
        return notification
    }

    /** Fallback when Android refuses to start the foreground alarm service. */
    fun show(
        context: Context,
        requestId: String,
        notificationId: String?,
        title: String,
        body: String,
    ) {
        if (requestId.isBlank()) return
        val notification = buildNotification(
            context,
            requestId,
            notificationId,
            title,
            body,
        )

        context.getSystemService(NotificationManager::class.java)
            .notify(notificationId(requestId), notification)
    }
}
