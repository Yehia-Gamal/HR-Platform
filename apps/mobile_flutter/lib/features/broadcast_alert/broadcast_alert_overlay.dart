import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ahla_shabab_management_os/features/broadcast_alert/broadcast_alert_provider.dart';

/// غطاء تنبيه شامل: عند وجود تنبيه نشط يغطي الشاشة بأكملها بوميض أحمر/أبيض
/// متناوب مع الرسالة وزر صمت. يُركَّب حول محتوى التطبيق كله في app.dart.
class BroadcastAlertOverlay extends ConsumerStatefulWidget {
  const BroadcastAlertOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BroadcastAlertOverlay> createState() =>
      _BroadcastAlertOverlayState();
}

class _BroadcastAlertOverlayState extends ConsumerState<BroadcastAlertOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  Timer? _expiryTimer;

  @override
  void dispose() {
    _flash.dispose();
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleExpiry(BroadcastAlert alert) {
    _expiryTimer?.cancel();
    final remaining = alert.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      ref.read(broadcastAlertProvider.notifier).dismiss();
      return;
    }
    _expiryTimer = Timer(remaining, () {
      if (mounted) ref.read(broadcastAlertProvider.notifier).dismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final alert = ref.watch(broadcastAlertProvider);
    syncTorchWithAlert(ref, alert);

    if (alert == null) {
      _expiryTimer?.cancel();
      return widget.child;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleExpiry(alert);
    });

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: FadeTransition(
            opacity: const AlwaysStoppedAnimation<double>(1),
            child: AnimatedBuilder(
              animation: _flash,
              builder: (context, _) => Material(
                color: _flash.value < 0.5
                    ? const Color(0xFFB71C1C)
                    : Colors.white,
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notification_important_rounded,
                        size: 72,
                        color: _flash.value < 0.5 ? Colors.white : Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'تنبيه عاجل',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color:
                                _flash.value < 0.5 ? Colors.white : Colors.red,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          alert.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.6,
                            color:
                                _flash.value < 0.5 ? Colors.white : Colors.red,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: () => ref
                            .read(broadcastAlertProvider.notifier)
                            .dismiss(),
                        icon: const Icon(Icons.notifications_off_outlined),
                        label: const Text('حسنًا، تم الاطلاع'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}