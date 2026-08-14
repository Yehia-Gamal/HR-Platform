import 'dart:async';

import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/core/theme/app_theme.dart';
import 'package:ahla_shabab_management_os/core/theme/theme_mode_controller.dart';
import 'package:ahla_shabab_management_os/core/widgets/connectivity_banner.dart';
import 'package:ahla_shabab_management_os/features/workspaces/app_gate.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_deep_link_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AppGate()),
    GoRoute(
      path: '/action/:kind/:actionId',
      builder: (context, state) => MobileActionDeepLinkPage(
        kind: state.pathParameters['kind'] ?? '',
        actionId: state.pathParameters['actionId'] ?? '',
        notificationId: state.uri.queryParameters['notification_id'],
        action: state.uri.queryParameters['action'],
      ),
    ),
  ],
);

/// قناة الاستماع لـ deep links القادمة من native (ACTION_VIEW intents).
/// تحلّ مشكلة "الشاشة السوداء": عندما يضغط المستخدم على إشعار والتطبيق مغلق،
/// يصل intent إلى MainActivity ونمرّره عبر EventChannel إلى GoRouter.
const EventChannel _deepLinkEvents = EventChannel('com.ahlashabab/deep_links');

class AhlaShababApp extends ConsumerStatefulWidget {
  const AhlaShababApp({super.key});

  @override
  ConsumerState<AhlaShababApp> createState() => _AhlaShababAppState();
}

class _AhlaShababAppState extends ConsumerState<AhlaShababApp> {
  StreamSubscription<dynamic>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _listenToNativeDeepLinks();
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  void _listenToNativeDeepLinks() {
    _deepLinkSub = _deepLinkEvents.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! String || raw.isEmpty) return;
        final route = resolveRouteFromDeepLink(raw);
        try {
          // '/' هو fallback آمن يعرض عتبة الجلسة بدل الشاشة السوداء.
          appRouter.go(route);
        } catch (e) {
          if (kDebugMode) debugPrint('Native deep link routing failed: $e');
        }
      },
      onError: (Object err) {
        if (kDebugMode) debugPrint('Deep link stream error: $err');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'أحلى شباب Management OS',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Column(
        children: [
          const ConnectivityBanner(),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}
