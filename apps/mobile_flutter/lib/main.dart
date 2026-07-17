import 'dart:async';

import 'package:ahla_shabab_management_os/app.dart';
import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppConfig.validate();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );

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
    } catch (_) {
      // FCM غير متوفر على هذا الجهاز — يستمر التطبيق بدون إشعارات.
    }

    runApp(const ProviderScope(child: AhlaShababApp()));
  } on Object catch (error) {
    runApp(ConfigurationErrorApp(message: error.toString()));
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
