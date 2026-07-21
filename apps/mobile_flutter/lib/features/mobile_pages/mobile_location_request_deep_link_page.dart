import 'dart:async';

import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/location_incoming_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileLocationRequestDeepLinkPage extends ConsumerStatefulWidget {
  const MobileLocationRequestDeepLinkPage({required this.requestId, super.key});

  final String requestId;

  @override
  ConsumerState<MobileLocationRequestDeepLinkPage> createState() =>
      _MobileLocationRequestDeepLinkPageState();
}

class _MobileLocationRequestDeepLinkPageState
    extends ConsumerState<MobileLocationRequestDeepLinkPage> {
  Timer? _timer;
  bool _timedOut = false;

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
        appBar: AppBar(title: const Text('طلب التحقق من الموقع')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_empty, size: 48),
                SizedBox(height: 12),
                Text(
                  'استغرق تحميل الطلب وقتاً طويلاً.',
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

    final request = ref.watch(locationRequestByIdProvider(widget.requestId));
    final access = ref.watch(accessContextProvider).value;
    return request.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('طلب التحقق من الموقع')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 44),
                const SizedBox(height: 12),
                const Text(
                  'الطلب غير متاح أو لا تملك صلاحية فتحه.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(
                    locationRequestByIdProvider(widget.requestId),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (item) {
        _timer?.cancel();
        if (item.status == 'pending') {
          return LocationIncomingOverlay(
            request: item,
            employeeId: access?.employeeId,
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('طلب التحقق من الموقع')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fact_check_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    switch (item.status) {
                      'active' || 'accepted' => 'الطلب قيد التنفيذ.',
                      'completed' => 'تم إكمال هذا الطلب.',
                      'rejected' => 'تم رفض هذا الطلب.',
                      _ => 'انتهت صلاحية هذا الطلب.',
                    },
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
