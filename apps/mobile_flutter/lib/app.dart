import 'package:ahla_shabab_management_os/core/theme/app_theme.dart';
import 'package:ahla_shabab_management_os/core/widgets/connectivity_banner.dart';
import 'package:ahla_shabab_management_os/features/workspaces/app_gate.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_deep_link_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AppGate()),
    GoRoute(
      path: '/action/:kind/:actionId',
      builder: (context, state) => MobileActionDeepLinkPage(
        kind: state.pathParameters['kind'] ?? '',
        actionId: state.pathParameters['actionId'] ?? '',
        notificationId: state.uri.queryParameters['notification_id'],
      ),
    ),
  ],
);

class AhlaShababApp extends StatelessWidget {
  const AhlaShababApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'أحلى شباب Management OS',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
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
