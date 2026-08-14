import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/login_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_location_request_deep_link_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// هل نوع الإجراء من طلبات الموقع (location / location_request / live_location
/// / live_location_request)؟ هذه الأنواع تُوجَّه مباشرة لشاشة الإرسال بدل المرور
/// عبر RPC تحليل إضافي — لأن شاشة الموقع تجلب الطلب بالمعرّف في استدعاء واحد
/// بنفس سياسة الوصول، فالخطوة الوسيطة كانت تزيد زمن الفتح وتتسبب بشاشة المهلة.
bool _isLocationKind(String kind) => switch (kind) {
  'location' || 'location_request' || 'live_location' || 'live_location_request' => true,
  _ => false,
};

class MobileActionDeepLinkPage extends ConsumerWidget {
  const MobileActionDeepLinkPage({
    required this.kind,
    required this.actionId,
    this.notificationId,
    this.action,
    super.key,
  });
  final String kind;
  final String actionId;
  final String? notificationId;

  /// V25: معامل action من الـ deep link (مثل action=reject من شاشة Kotlin).
  final String? action;

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

        // مسار سريع لطلبات الموقع: تُفتح شاشة الإرسال مباشرة بمعرّف الطلب
        // (استدعاء واحد يجلب الطلب بنفس التخويل). يمنع الشاشة البيضاء الناتجة
        // عن استدعاءَي RPC متتاليين أثناء إقلاع التطبيق البطيء.
        if (_isLocationKind(kind)) {
          return MobileLocationRequestDeepLinkPage(
            requestId: actionId,
            action: action,
          );
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
          // لا مؤقت مهلة ثابت هنا: المزوّد يحمل timeout=15s خاصاً به، فيتوقّف
          // على spinner أثناء التحميل المشروع ثم يعرض إعادة المحاولة عند الفشل
          // — بدل إظهار شاشة مهلة بيضاء ميتة.
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
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
