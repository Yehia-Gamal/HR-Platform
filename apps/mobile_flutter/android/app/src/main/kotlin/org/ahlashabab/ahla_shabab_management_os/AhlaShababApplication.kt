package org.ahlashabab.ahla_shabab_management_os

import android.app.Application

/**
 * V2-embedding Application.
 *
 * Why the change: the legacy v1 `io.flutter.app.FlutterApplication` was only
 * retained by Flutter's Gradle plugin for backward compatibility. On v2
 * embeddings, `FlutterApplication` does nothing extra beyond calling
 * `FlutterMain.startInitialization(this)` — work that modern Flutter engine
 * v2 plugin already does in the generated `GeneratedPluginRegistrant`. What
 * matters for us is that the Application's `onCreate()` runs *before* any
 * manifest-declared Service or Activity is created, so the urgent
 * notification channel exists by the time FCM cold-starts the process with
 * an urgent data-only high-priority message while Flutter is not running.
 *
 * The companion ProGuard rule
 *   -keep class org.ahlashabab.ahla_shabab_management_os.** { *; }
 * (added in android/app/proguard-rules.pro) prevents R8 from renaming this
 * class so the manifest reference `android:name=".AhlaShababApplication"`
 * continues to resolve after minification.
 */
class AhlaShababApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Create the urgent notification channel eagerly so that the very
        // first FCM cold-start — before any MethodChannel handler exists —
        // can post a full-screen notification onto a channel the system
        // already knows about. Without this, Android 12+ would silently
        // downgrade the heads-up urgency to a passive card.
        UrgentNotificationManager.createChannel(this)
    }
}
