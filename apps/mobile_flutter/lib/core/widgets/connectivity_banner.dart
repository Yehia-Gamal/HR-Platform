import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';

/// شريط يظهر أعلى أو أسفل الشاشة عند فقدان الاتصال.
/// يختفي تلقائياً عند عودة الاتصال.
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectivityProvider);

    if (state == ConnectivityState.online) return const SizedBox.shrink();

    final (color, icon, text) = switch (state) {
      ConnectivityState.offline => (
        Colors.red.shade700,
        Icons.wifi_off_rounded,
        'لا يوجد اتصال بالإنترنت',
      ),
      ConnectivityState.reconnecting => (
        Colors.orange.shade700,
        Icons.sync_rounded,
        'جارٍ إعادة الاتصال...',
      ),
      ConnectivityState.serverUnavailable => (
        Colors.amber.shade800,
        Icons.cloud_off_rounded,
        'الخادم غير متاح حالياً',
      ),
      _ => (Colors.green, Icons.wifi_rounded, ''),
    };

    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      offset: state == ConnectivityState.online
          ? const Offset(0, -1)
          : Offset.zero,
      child: Material(
        color: color,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
