import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/push_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/location_incoming_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileLocationRequestDeepLinkPage extends ConsumerStatefulWidget {
  const MobileLocationRequestDeepLinkPage({
    required this.requestId,
    this.action,
    super.key,
  });

  final String requestId;

  /// V25: معامل action من الـ deep link — 'reject' يعني أن المستخدم ضغط
  /// "رفض الطلب" في شاشة Kotlin الكاملة، فيُرفض الطلب فعلياً هنا.
  final String? action;

  @override
  ConsumerState<MobileLocationRequestDeepLinkPage> createState() =>
      _MobileLocationRequestDeepLinkPageState();
}

class _MobileLocationRequestDeepLinkPageState
    extends ConsumerState<MobileLocationRequestDeepLinkPage> {
  /// V25: هل يتم تنفيذ الرفض التلقائي الآن؟ (لمنع التكرار أثناء إعادة البناء)
  bool _autoRejecting = false;

  void _scheduleAutoReject() {
    if (_autoRejecting) return;
    _autoRejecting = true;
    Future<void>.microtask(() async {
      try {
        await ref
            .read(mobileCommandsProvider)
            .respondLocation(widget.requestId, false);
        // V25: وسّم الطلب كمعالَج نهائياً فيمنع أي رنين لاحق لنفس الطلب.
        await PushService.markRequestHandled(widget.requestId);
      } catch (_) {
        // فشل الرفض — يبقى الطلب pending وتُعرض شاشة الاستجابة العادية.
      }
      if (!mounted) return;
      setState(() => _autoRejecting = false);
      ref.invalidate(locationRequestByIdProvider(widget.requestId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(locationRequestByIdProvider(widget.requestId));
    final access = ref.watch(accessContextProvider).value;
    return request.when(
      // لا مؤقت مهلة ثابت — المزوّد يحمل timeout=15s خاصاً به، فيتوقف على
      // spinner أثناء التحميل المشروع (إقلاع بطيء) ثم يعرض إعادة المحاولة
      // عند الفشل، بدل شاشة مهلة بيضاء ميتة.
      loading: () => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('جاري فتح الطلب...'),
            ],
          ),
        ),
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
        if (item.status == 'pending') {
          // V25: الرفض التلقائي القادم من شاشة Kotlin — يُنفَّذ مرة واحدة
          // ثم يعيد بناء الشاشة لتعرض حالة "تم رفض هذا الطلب".
          if (widget.action == 'reject') {
            _scheduleAutoReject();
            if (_autoRejecting) {
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('جاري رفض الطلب...'),
                    ],
                  ),
                ),
              );
            }
          }
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
