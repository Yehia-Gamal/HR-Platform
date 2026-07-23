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
    private val LEGACY_CHANNEL_IDS = listOf(
        "urgent_location_v5",
        "urgent_location_v4",
        "urgent_location_v3",
    )
    private const val VERIFIED_ACTION_BASE =
        "https://ahla-shabab-management-os.vercel.app/action/live_location_request/"

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)

        // حذف القنوات القديمة — Android لا يرفع أهمية قناة موجودة.
        for (legacyId in LEGACY_CHANNEL_IDS) {
            manager.deleteNotificationChannel(legacyId)
        }

        // إذا القناة الحالية موجودة بأهمية أقل من MAX، احذفها وأعد إنشاءها.
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) {
            if (existing.importance >= NotificationManager.IMPORTANCE_MAX) return
            manager.deleteNotificationChannel(CHANNEL_ID)
        }

        val sound = Uri.parse(
            "android.resource://${context.packageName}/${R.raw.urgent_notification}",
        )
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
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
        manager.createNotificationChannel(channel)
    }

    fun notificationId(requestId: String): Int =
        requestId.hashCode().and(Int.MAX_VALUE).coerceAtLeast(1)

    fun buildNotification(
        context: Context,
        requestId: String,
        notificationId: String?,
        title: String,
        body: String,
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
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setPriority(Notification.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(false)
            .setFullScreenIntent(pendingIntent, true)
            .setContentIntent(pendingIntent)
            .addAction(R.drawable.ic_notification, "فتح وإرسال الموقع", pendingIntent)
            .setSound(sound)
            .setVibrate(longArrayOf(0, 800, 300, 800, 300, 800, 300, 800))
            .build()

        notification.flags = notification.flags or
            Notification.FLAG_INSISTENT or
            Notification.FLAG_NO_CLEAR
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
