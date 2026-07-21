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
      // صفحات الإشعارات الإضافية
      'dispute_detail' => const MobileDisputesPage(),
      'task_detail' => const MobileTasksPage(),
      'attendance_detail' => const MobileAttendanceServicesPage(),
      _ => const Scaffold(
        body: Center(child: Text('نوع الإجراء غير مدعوم في التطبيق.')),
      ),
    };
