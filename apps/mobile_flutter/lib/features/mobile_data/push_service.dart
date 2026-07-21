import 'dart:async';

import 'package:ahla_shabab_management_os/app.dart';
import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:ahla_shabab_management_os/core/security/secure_session_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// خدمة الإشعارات العاجلة: FCM + إشعار محلي بشاشة كاملة لطلب الموقع.
///
/// آمنة عند غياب إعداد Firebase (google-services.json / GoogleService-Info.plist):
/// تتخطى التهيئة بهدوء بدل إسقاط التطبيق، ويبقى بقية التطبيق يعمل.
///
/// قناة طلبات الموقع تستخدم أعلى أهمية مع صوت واهتزاز وشاشة كاملة.
/// قناة v4: صوت مخصص + اهتزاز قوي + شاشة كاملة على شاشة القفل.
class PushService {
  PushService(this._registerToken);

  /// callback لتسجيل رمز FCM في الخادم (upsert_my_push_token).
  final Future<void> Function(String token, String platform) _registerToken;

  static const String urgentChannelId = 'urgent_location_v4';
  static const String urgentChannelName = 'طلبات الموقع العاجلة';
  static const String urgentChannelDesc =
      'إشعارات طلب الموقع الفوري من الإدارة — مع صوت واهتزاز قوي وشاشة كاملة';

  static final AndroidNotificationChannel _urgentChannel =
      AndroidNotificationChannel(
        urgentChannelId,
        urgentChannelName,
        description: urgentChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('urgent_notification'),
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      );

  static const _platform = MethodChannel('com.ahlashabab/urgent_notification');

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
    } catch (error) {
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
        if (payload != null && payload.isNotEmpty) {
          _local.cancel(_stableNotificationId(payload));
          _route(payload);
        }
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_urgentChannel);

    // Android 14+ requires the user to allow full-screen intents explicitly.
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestFullScreenIntentPermission();

    // إنشاء القناة على مستوى النظام عبر Kotlin لضمان توفرها قبل Dart.
    try {
      await _platform.invokeMethod('createNotificationChannel');
    } catch (_) {
      // في حالة فشل الاتصال بالقناة، تكمل بالقناة المحلية فقط.
    }

    // A native token refresh can happen while Dart is not running. Consume the
    // stored value on the next process start, in addition to getToken below.
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final pendingToken = await _platform.invokeMethod<String>(
          'consumePendingFcmToken',
        );
        if (pendingToken != null && pendingToken.isNotEmpty) {
          await _safeRegister(pendingToken);
        }
      } catch (_) {
        // Older platform builds simply continue with Firebase.getToken().
      }
    }

    // صلاحية الإشعارات (Android 13+ / iOS).
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (kDebugMode) {
      debugPrint('Notification permission: ${settings.authorizationStatus}');
    }

    // تسجيل الرمز + متابعة تجديده.
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _safeRegister(token);
    } else if (kDebugMode) {
      debugPrint('FCM token is null — device may not support GMS.');
    }
    FirebaseMessaging.instance.onTokenRefresh.listen(_safeRegister);

    // رسائل المقدمة → إشعار محلي عاجل.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // فتح التطبيق من إشعار (خلفية).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(_markPushDelivery(message, 'opened'));
      final link = message.data['deepLink'];
      if (link is String && link.isNotEmpty) {
        _local.cancel(_stableNotificationId(link));
        _route(link);
      }
    });

    // فتح التطبيق من حالة الإنهاء التام.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      unawaited(_markPushDelivery(initialMessage, 'opened'));
    }
    final link = initialMessage?.data['deepLink'];
    if (link is String && link.isNotEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        _local.cancel(_stableNotificationId(link));
        _route(link);
      });
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
    unawaited(_markPushDelivery(message, 'delivered'));
    final data = message.data;
    final isUrgent =
        data['fullScreenIntent'] == 'true' ||
        data['kind'] == 'live_location_request';
    final title = data['title'] ?? message.notification?.title ?? 'إشعار';
    final body = data['body'] ?? message.notification?.body ?? '';
    final deepLink = data['deepLink'] as String? ?? '';
    final requestId = data['requestId'] as String? ?? '';
    final notificationId = data['notificationId'] as String? ?? '';
    final notificationKey = deepLink.isNotEmpty
        ? deepLink
        : requestId.isNotEmpty
        ? requestId
        : data['entityId'] as String? ?? '';

    // للطلبات العاجلة: استدعاء Handler أصلي يفتح LocationRequestFullActivity
    if (isUrgent && requestId.isNotEmpty) {
      try {
        await _platform.invokeMethod('showUrgentNotification', {
          'requestId': requestId,
          'notificationId': notificationId,
          'title': title,
          'body': body,
        });
        return;
      } catch (_) {
        // fallback to flutter_local_notifications
      }
    }

    final androidDetails = AndroidNotificationDetails(
      _urgentChannel.id,
      _urgentChannel.name,
      channelDescription: _urgentChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: isUrgent,
      category: isUrgent
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      playSound: true,
      enableVibration: true,
      sound: isUrgent
          ? const RawResourceAndroidNotificationSound('urgent_notification')
          : null,
      vibrationPattern: isUrgent
          ? Int64List.fromList([0, 500, 200, 500])
          : null,
      visibility: NotificationVisibility.public,
      timeoutAfter: 5 * 60 * 1000,
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
      _stableNotificationId(notificationKey),
      title,
      body,
      details,
      payload: deepLink,
    );
  }

  void _route(String deepLink) {
    try {
      final uri = Uri.parse(deepLink);
      final segments = uri.pathSegments;
      final parts = deepLink.contains('://')
          ? [uri.host, ...segments]
          : segments;
      final idx = parts.indexOf('action');
      if (idx >= 0 && parts.length >= idx + 3) {
        final kind = parts[idx + 1];
        final id = parts[idx + 2];
        appRouter.go('/action/$kind/$id');
      } else if (deepLink.startsWith('/')) {
        appRouter.go(deepLink);
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
    final title =
        data['title'] ?? message.notification?.title ?? 'طلب موقع عاجل';
    final body =
        data['body'] ??
        message.notification?.body ??
        'الإدارة تطلب التحقق من موقعك الآن';
    final isUrgent =
        data['kind'] == 'live_location_request' ||
        data['fullScreenIntent'] == 'true';
    final requestId = data['requestId'] as String? ?? '';

    unawaited(_markPushDelivery(message, 'delivered'));

    // Android's native FirebaseMessagingService owns urgent presentation so
    // it works without booting Flutter. Avoid a duplicate Dart notification.
    if (isUrgent && defaultTargetPlatform == TargetPlatform.android) return;

    final channel = AndroidNotificationChannel(
      PushService.urgentChannelId,
      PushService.urgentChannelName,
      description: PushService.urgentChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound('urgent_notification'),
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
    );

    final plugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await plugin.initialize(initSettings);
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    final deepLink = data['deepLink'] as String? ?? '';
    final notificationKey = deepLink.isNotEmpty
        ? deepLink
        : requestId.isNotEmpty
        ? requestId
        : data['entityId'] as String? ?? '';

    await plugin.show(
      _stableNotificationId(notificationKey),
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
          category: isUrgent
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.reminder,
          playSound: true,
          enableVibration: true,
          sound: isUrgent
              ? const RawResourceAndroidNotificationSound('urgent_notification')
              : null,
          vibrationPattern: isUrgent
              ? Int64List.fromList([0, 500, 200, 500])
              : null,
          visibility: NotificationVisibility.public,
          timeoutAfter: 5 * 60 * 1000,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: isUrgent
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
      payload: deepLink,
    );
  } catch (_) {
    // تجاهل أي خطأ في معالج الخلفية لمنع كراش التطبيق.
  }
}

Future<void> _markPushDelivery(RemoteMessage message, String status) async {
  final notificationId = message.data['notificationId'] as String?;
  if (notificationId == null || notificationId.isEmpty) return;
  try {
    SupabaseClient client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      final projectRef = Uri.parse(AppConfig.supabaseUrl).host.split('.').first;
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureSessionStorage(
            persistSessionKey: 'sb-$projectRef-auth-token',
          ),
          pkceAsyncStorage: SecurePkceStorage(),
        ),
      );
      client = Supabase.instance.client;
    }
    if (client.auth.currentSession == null) return;
    await client.rpc<void>(
      'mark_my_notification_delivery',
      params: {'p_notification_id': notificationId, 'p_status': status},
    );
  } catch (error) {
    if (kDebugMode) debugPrint('Push delivery acknowledgement failed: $error');
  }
}

/// Stable positive 31-bit FNV-1a identifier. A redelivery for one request
/// replaces the same notification, while separate request UUIDs stay separate.
int _stableNotificationId(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}
