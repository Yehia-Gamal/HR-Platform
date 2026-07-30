import 'package:ahla_shabab_management_os/app.dart';
import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/push_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// TODO: حزم مطلوبة في pubspec.yaml (مضافة مسبقاً):
//   firebase_core, firebase_messaging, flutter_local_notifications
//
// TODO: إعداد المنصة:
//   Android → android/app/google-services.json  (من Firebase Console)
//   iOS     → ios/Runner/GoogleService-Info.plist (من Firebase Console)
//   iOS     → ios/Runner/Info.plist:
//       <key>UIBackgroundModes</key>
//       <array><string>fetch</string><string>remote-notification</string></array>
//       <key>FirebaseAppDelegateProxyEnabled</key>
//       <false/>
//
//   Android → AndroidManifest.xml:
//       <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
//       <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
//       <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
// ---------------------------------------------------------------------------

/// خدمة الإشعارات الرئيسية — واجهة عليا تُغلّف [PushService] وتوفر:
///
/// 1. تهيئة FCM + الإشعارات المحلية.
/// 2. طلب صلاحية الإشعارات + حفظ الإذن.
/// 3. الحصول على رمز FCM الحالي وتسجيله في Supabase.
/// 4. معالجة الرسائل (مقدمة / خلفية / إنهاء).
/// 5. إظهار إشعار محلي عند وصول رسالة في المقدمة.
/// 6. توجيه الضغط على الإشعار إلى الشاشة المناسبة عبر GoRouter.
///
/// آمنة عند غياب إعداد Firebase — تتخطى التهيئة بهدوء.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  PushService? _pushService;
  bool _initialized = false;
  String? _currentToken;

  /// هل الخدمة جاهزة للعمل (Firebase مُهيّأ + الصلاحية ممنوحة)؟
  bool get isReady => _initialized;

  /// رمز FCM الحالي (قد يكون null إذا لم يُهيّأ Firebase أو الجهاز بدون GMS).
  String? get currentToken => _currentToken;

  // -----------------------------------------------------------------------
  // تهيئة
  // -----------------------------------------------------------------------

  /// تهيئة الخدمة الكاملة: Firebase + إشعارات محلية + FCM.
  ///
  /// يُستدعى مرة واحدة من `main.dart` بعد `Supabase.initialize()`.
  /// تمرر [registerToken] كـ callback لتسجيل الرمز في الخادم.
  ///
  /// ```dart
  /// await NotificationService.instance.initialize(
  ///   registerToken: (token, platform) async {
  ///     await supabaseClient.rpc('upsert_my_push_token', params: {
  ///       'p_fcm_token': token,
  ///       'p_platform': platform,
  ///     });
  ///   },
  /// );
  /// ```
  Future<void> initialize({
    required Future<void> Function(String token, String platform)
        registerToken,
  }) async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[NotificationService] Firebase غير مُعدّ: $error');
      }
      return;
    }

    // تسجيل معالج الخلفية (يجب أن يكون top-level).
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    // إنشاء PushService الذي يدير الدورة الكاملة.
    _pushService = PushService(registerToken);
    await _pushService!.initialize();

    // حفظ الرمز الحالي.
    _currentToken = await _safeGetToken();

    // متابعة تجديد الرمز.
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _currentToken = token;
    });

    _initialized = true;
    if (kDebugMode) {
      final preview = _currentToken != null && _currentToken!.length > 12
          ? '${_currentToken!.substring(0, 12)}...'
          : _currentToken ?? 'null';
      debugPrint('[NotificationService] جاهز — token: $preview');
    }
  }

  // -----------------------------------------------------------------------
  // صلاحيات
  // -----------------------------------------------------------------------

  /// يطلب صلاحية الإشعارات من المستخدم.
  ///
  /// يعود بـ `true` إذا منح المستخدم الصلاحية، `false` إذا رفض.
  /// على Android 12 وما دون يعود بـ `true` دائماً (لا يحتاج إذن).
  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: true,
        criticalAlert: false,
        provisional: false,
      );
      final granted = settings.authorizationStatus ==
          AuthorizationStatus.authorized;
      if (kDebugMode) {
        debugPrint(
          '[NotificationService] صلاحية الإشعارات: '
          '${granted ? "ممنوحة" : "مرفوضة"}',
        );
      }
      return granted;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[NotificationService] خطأ في طلب الصلاحية: $error');
      }
      return false;
    }
  }

  /// هل صلاحية الإشعارات ممنوحة حالياً؟
  Future<bool> isPermissionGranted() async {
    if (!_initialized) return false;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // رمز FCM
  // -----------------------------------------------------------------------

  /// يعيد رمز FCM الحالي.
  ///
  /// يحاول الحصول على رمز جديد إذا كان الرمز المحفوظ فارغاً.
  Future<String?> getToken() async {
    if (!_initialized) return null;
    _currentToken ??= await _safeGetToken();
    return _currentToken;
  }

  /// يسجّل رمز FCM الحالي في Supabase يدوياً.
  ///
  /// مفيد بعد تسجيل الدخول لضمان وصول الإشعارات فوراً.
  Future<void> registerCurrentToken() async {
    final token = await getToken();
    if (token == null) return;
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) return;
      await client.rpc<dynamic>(
        'upsert_my_push_token',
        params: {'p_fcm_token': token, 'p_platform': platform},
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[NotificationService] فشل تسجيل الرمز: $error');
      }
    }
  }

  // -----------------------------------------------------------------------
  // إشعار محلي يدوي
  // -----------------------------------------------------------------------

  /// يعرض إشعاراً محلياً يدوياً (بدون FCM).
  ///
  /// مفيد لعرض تذكيرات محلية أو تنبيهات من منطق التطبيق.
  Future<void> showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
    bool urgent = false,
  }) async {
    final plugin = FlutterLocalNotificationsPlugin();
    final route = resolveNotificationRouteFromData(data);

    final androidDetails = AndroidNotificationDetails(
      urgent ? PushService.urgentChannelId : 'general_v1',
      urgent ? PushService.urgentChannelName : 'إشعارات عامة',
      channelDescription: urgent
          ? PushService.urgentChannelDesc
          : 'الإشعارات والتنبيهات العامة',
      importance: urgent ? Importance.max : Importance.high,
      priority: urgent ? Priority.max : Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      timeoutAfter: urgent ? 5 * 60 * 1000 : null,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: urgent
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
    );

    await plugin.show(
      _stableId(route.isNotEmpty ? route : title),
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: route,
    );
  }

  // -----------------------------------------------------------------------
  // توجيه يدوي
  // -----------------------------------------------------------------------

  /// يوجّه إلى الشاشة المناسبة بناءً على بيانات الإشعار.
  ///
  /// يستخدم [resolveNotificationRouteFromData] للتحويل ثم [appRouter.go].
  void navigateFromNotificationData(Map<String, dynamic> data) {
    final route = resolveNotificationRouteFromData(data);
    if (route.isNotEmpty) {
      appRouter.go(route);
    }
  }

  // -----------------------------------------------------------------------
  // إعفاء البطارية
  // -----------------------------------------------------------------------

  /// هل التطبيق معفى من تحسين البطارية؟ (Android فقط)
  Future<bool?> isBatteryOptimizationExempt() =>
      PushService.isBatteryOptimizationExempt();

  /// يطلب إعفاء من تحسين البطارية (Samsung / Xiaomi تقتل العملية في الخلفية).
  Future<void> requestBatteryExemption() =>
      PushService.requestBatteryOptimizationExemption();

  // -----------------------------------------------------------------------
  // مساعدات داخلية
  // -----------------------------------------------------------------------

  Future<String?> _safeGetToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  /// معرّف ثابت إيجابي 31-بت (FNV-1a) — نسخة مكررة عن PushService.
  static int _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
