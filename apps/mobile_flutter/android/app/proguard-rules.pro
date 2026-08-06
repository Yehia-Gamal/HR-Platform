# Flutter/Supabase/Firebase ProGuard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.firebase.** { *; }
-keep class io.supabase.** { *; }
-keep class org.jetbrains.kotlin.** { *; }
-dontwarn javax.annotation.**
-dontwarn sun.misc.Unsafe
-keepattributes Signature
-keepattributes *Annotation*

# Flutter Play Store deferred components — suppress missing Play Core classes
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# P1-CRITICAL: keep the app's own Kotlin classes so `AndroidManifest.xml`
# can still resolve them after minification. The manifest references
# `UrgentLocationMessagingService`, `UrgentAlarmService`,
# `LocationRequestFullActivity`, `MainActivity`, and `AhlaShababApplication`
# by fully-qualified name — R8/ProGuard renames those classes and breaks
# background FCM delivery (the phone never wakes for a live-location request).
-keep class org.ahlashabab.ahla_shabab_management_os.** { *; }
