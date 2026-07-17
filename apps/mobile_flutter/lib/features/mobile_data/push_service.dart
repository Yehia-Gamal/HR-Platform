import 'dart:async';

import 'package:ahla_shabab_management_os/app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// خدمة الإشعارات العاجلة: FCM + إشعار محلي بشاشة كاملة لطلب الموقع.
///
/// آمنة عند غياب إعداد Firebase (google-services.json / GoogleService-Info.plist):
/// تتخطى التهيئة بهدوء بدل إسقاط التطبيق، ويبقى بقية التطبيق يعمل.
///
/// قناة urgent_location تُطلب فيها أعلى أهمية + صوت + اهتزاز + fullScreenIntent
/// (على أندرويد؛ يظهر فوق شاشة القفل عند سماح النظام). لا تحايل على قيود النظام.
class PushService {
  PushService(this._registerToken);

  /// callback لتسجيل رمز FCM في الخادم (upsert_my_push_token).
  final Future<void> Function(String token, String platform) _registerToken;

  static final AndroidNotificationChannel _urgentChannel =
      AndroidNotificationChannel(
    'urgent_location_v3',
    'طلبات الموقع العاجلة',
    description: 'إشعارات طلب الموقع الفوري من الإدارة — مع صوت واهتزاز قوي',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('urgent_notification'),
    vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
    } catch (error) {
      // Firebase غير مُعدّ لهذا الـ build — تخطٍّ آمن.
      if (kDebugMode) {
        debugPrint('Push disabled (Firebase not configured): $error');
      }
      return;
    }

    // تهيئة الإشعارات المحلية + قناة العاجل.
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _route(payload);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_urgentChannel);

    // صلاحية الإشعارات (Android 13+ / iOS).
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // تسجيل الرمز + متابعة تجديده.
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _safeRegister(token);
    FirebaseMessaging.instance.onTokenRefresh.listen(_safeRegister);

    // رسائل المقدمة → إشعار محلي عاجل (لأن FCM لا يعرض إشعارًا في المقدمة).
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // فتح التطبيق من إشعار (خلفية).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final link = message.data['deepLink'];
      if (link is String && link.isNotEmpty) _route(link);
    });

    // فتح التطبيق من حالة الإنهاء التام.
    final initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    final link = initialMessage?.data['deepLink'];
    if (link is String && link.isNotEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 400), () => _route(link));
    }

    _ready = true;
  }

  Future<void> _safeRegister(String token) async {
    try {
      final platform = defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android';
      await _registerToken(token, platform);
    } catch (error) {
      if (kDebugMode) debugPrint('FCM token registration failed: $error');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final isUrgent = data['fullScreenIntent'] == 'true' ||
        data['kind'] == 'live_location_request';
    final title = data['title'] ?? message.notification?.title ?? 'إشعار';
    final body = data['body'] ?? message.notification?.body ?? '';
    final deepLink = data['deepLink'] as String? ?? '';

    final androidDetails = AndroidNotificationDetails(
      _urgentChannel.id,
      _urgentChannel.name,
      channelDescription: _urgentChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: isUrgent,
      category: AndroidNotificationCategory.call,
      playSound: true,
      enableVibration: true,
      sound: isUrgent
          ? const RawResourceAndroidNotificationSound('urgent_notification')
          : null,
      vibrationPattern:
          isUrgent ? Int64List.fromList([0, 500, 200, 500]) : null,
      visibility: NotificationVisibility.public,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: isUrgent
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
    );

    await _local.show(
      message.hashCode,
      title,
      body,
      details,
      payload: deepLink,
    );
  }

  void _route(String deepLink) {
    // ahlashabab://action/live_location_request/:id → /action/:kind/:id
    try {
      final uri = Uri.parse(deepLink);
      final segments = uri.pathSegments;
      // يدعم الشكلين: ahlashabab://action/kind/id  و  /action/kind/id
      final parts = deepLink.contains('://')
          ? [uri.host, ...segments]
          : segments;
      final idx = parts.indexOf('action');
      if (idx >= 0 && parts.length >= idx + 3) {
        final kind = parts[idx + 1];
        final id = parts[idx + 2];
        appRouter.go('/action/$kind/$id');
      }
    } catch (_) {
      // تجاهل روابط غير صالحة.
    }
  }
}

/// معالج رسائل الخلفية (يجب أن يكون دالة عليا top-level).
/// يُستدعى عندما يكون التطبيق في الخلفية أو مغلقاً تماماً.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();

    final data = message.data;
    final title = data['title'] ?? message.notification?.title ?? 'طلب موقع عاجل';
    final body  = data['body']  ?? message.notification?.body  ?? 'الإدارة تطلب التحقق من موقعك الآن';
    final isUrgent = data['kind'] == 'live_location_request' ||
                     data['fullScreenIntent'] == 'true';

    const channel = AndroidNotificationChannel(
      'urgent_location_v3',
      'طلبات الموقع العاجلة',
      description: 'إشعارات طلب الموقع الفوري من الإدارة',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final plugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await plugin.initialize(initSettings);
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await plugin.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: isUrgent,
          category: AndroidNotificationCategory.call,
          playSound: true,
          enableVibration: true,
          sound: isUrgent
              ? const RawResourceAndroidNotificationSound('urgent_notification')
              : null,
          vibrationPattern:
              isUrgent ? Int64List.fromList([0, 500, 200, 500]) : null,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: isUrgent
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
      payload: data['deepLink'] as String? ?? '',
    );
  } catch (_) {
    // تجاهل أي خطأ في معالج الخلفية لمنع كراش التطبيق.
  }
}
