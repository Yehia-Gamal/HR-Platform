import 'dart:async';

import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/login_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileActionDeepLinkPage extends ConsumerWidget {
  const MobileActionDeepLinkPage({
    required this.kind,
    required this.actionId,
    this.notificationId,
    super.key,
  });
  final String kind;
  final String actionId;
  final String? notificationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) =>
          Scaffold(body: Center(child: Text(humanizeError(error)))),
      data: (value) {
        if (value == null) return const LoginPage();
        if (notificationId case final id? when id.isNotEmpty) {
          ref.watch(markNotificationOpenedProvider(id));
        }
        final item = MobileActionItem(
          id: actionId,
          kind: kind,
          title: '',
          subtitle: null,
          priority: 'normal',
          status: '',
          dueAt: null,
        );
        final target = ref.watch(mobileActionTargetProvider(item));
        return target.when(
          loading: () => _TimeoutWrapper(
            child: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, _) => Scaffold(
            appBar: AppBar(title: const Text('فتح الإجراء')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(humanizeError(error), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('العودة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          data: mobilePageForActionTarget,
        );
      },
    );
  }
}

/// Shows a timeout error if the deep link takes too long to resolve.
class _TimeoutWrapper extends StatefulWidget {
  const _TimeoutWrapper({required this.child});
  final Widget child;
  @override
  State<_TimeoutWrapper> createState() => _TimeoutWrapperState();
}

class _TimeoutWrapperState extends State<_TimeoutWrapper> {
  bool _timedOut = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_timedOut) {
      return Scaffold(
        appBar: AppBar(title: const Text('فتح الإجراء')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_empty, size: 48),
                SizedBox(height: 12),
                Text(
                  'استغرق تحميل الإجراء وقتاً طويلاً.',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 4),
                Text(
                  'تحقق من الاتصال بالإنترنت وأعد المحاولة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
