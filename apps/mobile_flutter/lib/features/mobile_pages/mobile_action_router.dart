import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_correction_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/kpi_evaluation_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_services_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_daily_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_feed_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_location_request_deep_link_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_tasks_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
import 'package:flutter/material.dart';

/// مسار مباشر فوري لجميع أنواع الإشعارات المعروفة في التطبيق.
///
/// بدلاً من استدعاء RPC للخادم أثناء وقوف المستخدم على شاشة «جاري فتح الإشعار...»
/// ثم فتح الشاشة (استدعاءان متتاليان ومهلة تصل لـ 30 ثانية)، نفتح الصفحة فوراً
/// لأن كل صفحة من صفحات الموبايل تجلب بياناتها وتتحقق من صلاحية المستخدم
/// داخلياً بنفسها بطريقة سلسة.
Widget? getDirectActionPage({
  required String kind,
  required String actionId,
  String? action,
}) {
  final canonical = canonicalNotificationEntityType(kind) ?? kind;
  return switch (canonical) {
    'request' || 'request_decision' => MobileRequestDetailPage(
        requestId: actionId,
        initialAction: action,
      ),
    'kpi' || 'kpi_evaluation' => KpiEvaluationDetailPage(
        evaluationId: actionId,
      ),
    'attendance_correction' || 'attendance_corrections' =>
      AttendanceCorrectionDetailPage(
        correctionId: actionId,
      ),
    'instant_penalty' ||
    'instant_penalties' ||
    'penalty' ||
    'finance' ||
    'fellowship' ||
    'fellowship_fund' =>
      MyInstantPenaltiesPage(
        highlightId:
            actionId.isEmpty || actionId == 'default' ? null : actionId,
      ),
    'daily_report' ||
    'daily_reports' ||
    'daily_report_like' ||
    'daily_report_comment' =>
      const MobileDailyReportsPage(),
    'live_location_request' ||
    'live_location' ||
    'location_request' ||
    'location' =>
      MobileLocationRequestDeepLinkPage(
        requestId: actionId,
        action: action,
      ),
    'task' || 'tasks' => MobileTasksPage(
        highlightId: actionId.isEmpty ? null : actionId,
      ),
    'announcement' || 'announcements' => MobileFeedDetailPage(
        kind: 'announcement',
        itemId: actionId,
      ),
    'decision' || 'decisions' => MobileFeedDetailPage(
        kind: 'decision',
        itemId: actionId,
      ),
    'dispute' || 'dispute_case' => MobileFeedDetailPage(
        kind: 'dispute',
        itemId: actionId,
      ),
    'attendance' ||
    'attendance_daily' ||
    'attendance_event' ||
    'punch_reminder' ||
    'attendance_alert' =>
      MobileAttendanceServicesPage(
        highlightId: actionId.isEmpty ? null : actionId,
      ),
    'device' || 'employee_device' || 'devices' =>
      const PasskeyDevicesPage(),
    _ => null,
  };
}

/// [initialAction] يأتي من أزرار إشعار القرار (approve/reject) — يفتح
/// ورقة القرار في صفحة الطلب جاهزة للتأكيد بدل التنفيذ الصامت.
Widget mobilePageForActionTarget(
  MobileActionTarget target, {
  String? initialAction,
}) => switch (target.mobileRoute) {
  'request_detail' => MobileRequestDetailPage(
    requestId: target.recordId,
    initialAction: initialAction,
  ),
  'kpi_form' => KpiEvaluationDetailPage(evaluationId: target.recordId),
  'feed_detail' => MobileFeedDetailPage(
    kind: target.kind,
    itemId: target.recordId,
  ),
  'live_location_request' => MobileLocationRequestDeepLinkPage(
    requestId: target.recordId,
  ),
  'task_detail' => MobileTasksPage(highlightId: target.recordId),
  'attendance_correction' ||
  'attendance_correction_detail' => AttendanceCorrectionDetailPage(
    correctionId: target.recordId,
  ),
  'attendance_detail' => MobileAttendanceServicesPage(
    highlightId: target.recordId,
  ),
  'instant_penalty' ||
  'instant_penalties' ||
  'penalty' => MyInstantPenaltiesPage(
    highlightId: target.recordId.isEmpty || target.recordId == 'default'
        ? null
        : target.recordId,
  ),
  'daily_report' ||
  'daily_reports' => const MobileDailyReportsPage(),
  'device' ||
  'employee_device' ||
  'passkey_device' => const PasskeyDevicesPage(),
  'fellowship_fund' ||
  'fellowship' => const MyInstantPenaltiesPage(),
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
                Icon(
                  Icons.notifications_off_outlined,
                  size: 52,
                  color: colors.onSurfaceVariant,
                ),
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
