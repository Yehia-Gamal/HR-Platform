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
    const val CHANNEL_ID = "urgent_location_v4"
    private const val CHANNEL_NAME = "طلبات الموقع العاجلة"
    private const val CHANNEL_DESCRIPTION =
        "إشعارات طلب الموقع الفوري — صوت واهتزاز وشاشة كاملة"
    private const val VERIFIED_ACTION_BASE =
        "https://ahla-shabab-management-os.vercel.app/action/live_location_request/"

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

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
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = CHANNEL_DESCRIPTION
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 800)
            setSound(sound, audioAttributes)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    fun show(
        context: Context,
        requestId: String,
        notificationId: String?,
        title: String,
        body: String,
    ) {
        if (requestId.isBlank()) return
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
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            requestId.hashCode(),
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
            .setAutoCancel(true)
            .setTimeoutAfter(5 * 60 * 1000L)
            .setFullScreenIntent(pendingIntent, true)
            .setContentIntent(pendingIntent)
            .setSound(sound)
            .setVibrate(longArrayOf(0, 500, 200, 500, 200, 800))
            .build()

        context.getSystemService(NotificationManager::class.java)
            .notify(requestId.hashCode(), notification)
    }
}
