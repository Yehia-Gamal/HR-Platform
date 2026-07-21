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
