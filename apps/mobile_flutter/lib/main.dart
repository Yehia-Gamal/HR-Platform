import 'dart:async';

import 'package:ahla_shabab_management_os/app.dart';
import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:ahla_shabab_management_os/core/observability/crash_reporter.dart';
import 'package:ahla_shabab_management_os/core/security/secure_session_storage.dart';
import 'package:ahla_shabab_management_os/core/theme/theme_mode_controller.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // رصد الأخطاء العالمي — يُرسل لـ observability_events عبر edge function
  setupGlobalErrorHandlers();

  ErrorWidget.builder = (_) => const Material(
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'تعذر عرض هذه الصفحة. أعد المحاولة.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
  try {
    final initialThemeMode = await loadSavedThemeMode();
    AppConfig.validate();
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

    // ربط مراقب الأخطاء بالعميل بعد تهيئة Supabase
    CrashReporter.instance.initialize(Supabase.instance.client);

    // Firebase/FCM: آمن عند غياب Google Play Services (محاكيات، أجهزة بدون GMS).
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      final push = PushService((token, platform) async {
        final client = Supabase.instance.client;
        if (client.auth.currentSession == null) return;
        await client.rpc<dynamic>(
          'upsert_my_push_token',
          params: {'p_fcm_token': token, 'p_platform': platform},
        );
      });
      unawaited(push.initialize());
      Supabase.instance.client.auth.onAuthStateChange.listen((event) {
        if (event.session == null) return;
        unawaited(
          FirebaseMessaging.instance
              .getToken()
              .then((token) async {
                if (token == null) return;
                final platform = defaultTargetPlatform == TargetPlatform.iOS
                    ? 'ios'
                    : 'android';
                await Supabase.instance.client.rpc<dynamic>(
                  'upsert_my_push_token',
                  params: {'p_fcm_token': token, 'p_platform': platform},
                );
              })
              .catchError((Object error) {
                if (kDebugMode) {
                  debugPrint('Post-login FCM registration failed: $error');
                }
                unawaited(
                  CrashReporter.instance.captureError(error, null, context: 'fcm_token_registration'),
                );
              }),
        );
      });
    } catch (e, st) {
      // FCM غير متوفر على هذا الجهاز — يستمر التطبيق بدون إشعارات.
      if (kDebugMode) {
        debugPrint('FCM setup failed: $e');
      }
      unawaited(
        CrashReporter.instance.captureError(e, st, context: 'fcm_setup'),
      );
    }

    runApp(
      ProviderScope(
        overrides: [
          themeModeProvider.overrideWith(
            () => ThemeModeController(initialMode: initialThemeMode),
          ),
        ],
        child: const AhlaShababApp(),
      ),
    );
  } on Object catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('Application initialization failed: $error\n$stackTrace');
    }
    // لا يمكننا استخدام CrashReporter هنا لأن Supabase لم يُهيّأ بعد
    // لكن PlatformDispatcher.onError (المُعرف في setupGlobalErrorHandlers) سيلتقطه
    runApp(
      const ConfigurationErrorApp(
        message:
            'تعذر تشغيل التطبيق لأن إعداد الإصدار غير مكتمل. تواصل مع مسؤول النظام.',
      ),
    );
  }
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_suggest_outlined, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'إعداد التطبيق غير مكتمل',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
