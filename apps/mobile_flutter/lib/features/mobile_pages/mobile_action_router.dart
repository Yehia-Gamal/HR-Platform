import 'package:ahla_shabab_management_os/app.dart';
import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_project_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_correction_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/kpi_evaluation_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_services_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_daily_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_feed_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_location_request_deep_link_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_notifications_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
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
    'request' || 'request_decision' || 'requests' =>
      actionId.isEmpty || actionId == 'default'
          ? const MobileRequestsPage()
          : MobileRequestDetailPage(
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
    'daily_report_comment' ||
    'report' ||
    'reports' =>
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
        highlightId:
            actionId.isEmpty || actionId == 'default' ? null : actionId,
      ),
    'announcement' || 'announcements' => MobileFeedDetailPage(
        kind: 'announcement',
        itemId: actionId,
      ),
    'decision' || 'decisions' => MobileFeedDetailPage(
        kind: 'decision',
        itemId: actionId,
      ),
    'dispute' || 'dispute_case' || 'disputes' => MobileFeedDetailPage(
        kind: 'dispute',
        itemId: actionId,
      ),
    'attendance' ||
    'attendance_daily' ||
    'attendance_event' ||
    'punch_reminder' ||
    'attendance_alert' ||
    'attendance_services' =>
      MobileAttendanceServicesPage(
        highlightId:
            actionId.isEmpty || actionId == 'default' ? null : actionId,
      ),
    'device' || 'employee_device' || 'devices' =>
      const PasskeyDevicesPage(),
    'association_project' ||
    'association_projects' ||
    'projects' ||
    'project' =>
      actionId.isEmpty || actionId == 'default'
          ? const MobileNotificationsPage()
          : AssociationProjectDetailPage(projectId: actionId),
    'notification' || 'notifications' => const MobileNotificationsPage(),
    _ => null,
  };
}

/// [initialAction] يأتي من أزرار إشعار القرار (approve/reject) — يفتح
/// ورقة القرار في صفحة الطلب جاهزة للتأكيد بدل التنفيذ الصامت.
Widget mobilePageForActionTarget(
  MobileActionTarget target, {
  String? initialAction,
}) {
  final page = switch (target.mobileRoute) {
    'request_detail' => MobileRequestDetailPage(
        requestId: target.recordId,
        initialAction: initialAction,
      ),
    'requests' ||
    'request' ||
    'request_list' ||
    'my_requests' ||
    'team_requests' =>
      target.recordId.isEmpty || target.recordId == 'default'
          ? const MobileRequestsPage()
          : MobileRequestDetailPage(
              requestId: target.recordId,
              initialAction: initialAction,
            ),
    'kpi_form' || 'kpi' || 'kpi_evaluation' =>
      KpiEvaluationDetailPage(evaluationId: target.recordId),
    'feed_detail' => MobileFeedDetailPage(
        kind: target.kind,
        itemId: target.recordId,
      ),
    'dispute_detail' || 'dispute' || 'dispute_case' => MobileFeedDetailPage(
        kind: 'dispute',
        itemId: target.recordId,
      ),
    'announcement' || 'announcements' => MobileFeedDetailPage(
        kind: 'announcement',
        itemId: target.recordId,
      ),
    'decision' || 'decisions' => MobileFeedDetailPage(
        kind: 'decision',
        itemId: target.recordId,
      ),
    'recognition' || 'recognitions' => MobileFeedDetailPage(
        kind: 'recognition',
        itemId: target.recordId,
      ),
    'live_location_request' || 'live_location' || 'location' =>
      MobileLocationRequestDeepLinkPage(
        requestId: target.recordId,
      ),
    'task_detail' || 'task' || 'tasks' => MobileTasksPage(
        highlightId: target.recordId.isEmpty || target.recordId == 'default'
            ? null
            : target.recordId,
      ),
    'attendance_correction' ||
    'attendance_correction_detail' ||
    'attendance_corrections' =>
      AttendanceCorrectionDetailPage(
        correctionId: target.recordId,
      ),
    'attendance_detail' ||
    'attendance' ||
    'attendance_services' ||
    'attendance_page' ||
    'attendance_history' ||
    'attendance_event' ||
    'punch_reminder' ||
    'attendance_alert' =>
      MobileAttendanceServicesPage(
        highlightId: target.recordId.isEmpty || target.recordId == 'default'
            ? null
            : target.recordId,
      ),
    'instant_penalty' ||
    'instant_penalties' ||
    'penalty' ||
    'finance' =>
      MyInstantPenaltiesPage(
        highlightId: target.recordId.isEmpty || target.recordId == 'default'
            ? null
            : target.recordId,
      ),
    'daily_report' ||
    'daily_reports' ||
    'report' ||
    'reports' =>
      const MobileDailyReportsPage(),
    'device' ||
    'employee_device' ||
    'passkey_device' ||
    'devices' =>
      const PasskeyDevicesPage(),
    'fellowship_fund' || 'fellowship' => const MyInstantPenaltiesPage(),
    'association_project' ||
    'association_projects' ||
    'project' ||
    'projects' ||
    'project_detail' =>
      target.recordId.isEmpty || target.recordId == 'default'
          ? const MobileNotificationsPage()
          : AssociationProjectDetailPage(projectId: target.recordId),
    'notification' || 'notifications' => const MobileNotificationsPage(),
    _ => null,
  };

  if (page != null) return page;

  // محاولة إنقاذ ذكية قبل شاشة عدم الدعم: فحص kind و recordId عبر getDirectActionPage
  final directFallback = getDirectActionPage(
    kind: target.kind,
    actionId: target.recordId,
    action: initialAction,
  );
  if (directFallback != null) return directFallback;

  return UnsupportedActionPage(target: target);
}

/// شاشة آمنة مع خيارات تفاعلية فورية بدل طريق مسدود.
class UnsupportedActionPage extends StatelessWidget {
  const UnsupportedActionPage({this.target, super.key});

  final MobileActionTarget? target;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('فتح الإشعار'),
        actions: [
          IconButton(
            tooltip: 'الرئيسية',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => appRouter.go('/'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notifications_active_outlined,
                    size: 48,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'تفاصيل الإشعار متاحة في مركز الإشعارات',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'لم يتم العثور على شاشة مخصصة لهذا الرابط مباشرة، يمكنك استعراض التفاصيل الكاملة من قائمة الإشعارات أو التوجه للرئيسية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.6,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MobileNotificationsPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('عرض قائمة الإشعارات'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => appRouter.go('/'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('العودة للرئيسية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
