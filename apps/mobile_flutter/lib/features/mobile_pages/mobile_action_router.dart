import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/kpi_evaluation_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_services_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_disputes_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_feed_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_tasks_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_location_request_deep_link_page.dart';
import 'package:flutter/material.dart';

Widget mobilePageForActionTarget(MobileActionTarget target) =>
    switch (target.mobileRoute) {
      'request_detail' => MobileRequestDetailPage(requestId: target.recordId),
      'kpi_form' => KpiEvaluationDetailPage(evaluationId: target.recordId),
      'feed_detail' => MobileFeedDetailPage(
        kind: target.kind,
        itemId: target.recordId,
      ),
      'live_location_request' => MobileLocationRequestDeepLinkPage(
        requestId: target.recordId,
      ),
      'dispute_detail' => MobileDisputesPage(highlightId: target.recordId),
      'task_detail' => MobileTasksPage(highlightId: target.recordId),
      'attendance_detail' =>
        MobileAttendanceServicesPage(highlightId: target.recordId),
      _ => const UnsupportedActionPage(),
    };

/// شاشة آمنة لنوع إجراء غير معروف — بدل Scaffold شبه فارغ كان يبدو كصفحة بيضاء.
class UnsupportedActionPage extends StatelessWidget {
  const UnsupportedActionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('فتح الإشعار')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_off_outlined, size: 52, color: colors.onSurfaceVariant),
                const SizedBox(height: 14),
                Text(
                  'نوع هذا الإشعار غير مدعوم في التطبيق.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'يمكنك متابعة التفاصيل من قائمة الإشعارات أو من لوحة الإدارة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('العودة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
