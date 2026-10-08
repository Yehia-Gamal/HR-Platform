import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// 0658: مأمورية انقضى يومها دون إنهاء يغلقها النظام — ليست «أُنجزت»، ولصاحبها
// كتابة تقريرها خلال 14 يومًا (submit_my_mission_report).
void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  final now = DateTime.now().toUtc();
  final yesterday = now.subtract(const Duration(days: 1));

  MobileRequestDetail missionDetail({String? report, DateTime? autoClosedAt}) =>
      MobileRequestDetail.fromJson({
        'id': 'req-mission-1',
        'requestNumber': 77,
        'requestType': 'mission',
        'employeeId': 'emp-owner',
        'employeeName': 'موظف ميداني',
        'employeeCode': 'EMP-77',
        'title': 'مأمورية زيارة أسر',
        'reason': 'زيارة ميدانية',
        'status': 'approved',
        'workflowStatus': 'completed',
        'payload': {
          'startDate': yesterday.toIso8601String().substring(0, 10),
          'endDate': yesterday.toIso8601String().substring(0, 10),
          'location': 'القرية',
        },
        'createdAt': yesterday.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'canDecide': false,
        'canCancel': false,
        'canResubmit': false,
        'steps': [],
        'attachments': [],
        'conflicts': [],
        'decisionMode': 'DIRECT',
        'decisionOnBehalfOfExecutive': false,
        'missionExecution': {
          'id': 'exec-1',
          'status': 'completed',
          'startedAt': yesterday.toIso8601String(),
          'endedAt': yesterday.add(const Duration(hours: 8)).toIso8601String(),
          'report': report ?? MobileMissionExecution.autoClosedReport,
          'outcome': null,
          'autoClosedAt': (autoClosedAt ?? now).toIso8601String(),
        },
      });

  Future<void> pumpDetail(
    WidgetTester tester,
    MobileRequestDetail detail, {
    required String viewer,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accessContextProvider.overrideWith(
            (ref) async => AccessContext.fromJson({
              'userId': 'user-$viewer',
              'employeeId': viewer,
              'displayName': 'مستخدم',
              'roles': ['employee'],
            }),
          ),
          mobileRequestDetailProvider('req-mission-1').overrideWith(
            (ref) async => detail,
          ),
        ],
        child: const MaterialApp(
          home: MobileRequestDetailPage(requestId: 'req-mission-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.text('تنفيذ المأمورية');
    await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets('صاحبها يرى أنها أُغلقت تلقائيًا وزر كتابة التقرير', (tester) async {
    await pumpDetail(tester, missionDetail(), viewer: 'emp-owner');

    expect(find.text('أغلق النظام المأمورية لانقضاء يومها دون إنهاء'), findsOneWidget);
    expect(find.text('أُنجزت المأمورية وقُدِّم التقرير'), findsNothing);
    expect(find.text('كتابة تقرير المأمورية'), findsOneWidget);
    // نص الإغلاق الآلي لا يُعرض كأنه «تقرير التنفيذ»
    expect(find.text(MobileMissionExecution.autoClosedReport), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('المدير يرى الحالة بلا زر', (tester) async {
    await pumpDetail(tester, missionDetail(), viewer: 'emp-manager');

    expect(find.text('أغلق النظام المأمورية لانقضاء يومها دون إنهاء'), findsOneWidget);
    expect(find.text('لم يسجّل الموظف إنهاءها وتقريرها في يومها.'), findsOneWidget);
    expect(find.text('كتابة تقرير المأمورية'), findsNothing);
  });

  testWidgets('بعد كتابة التقرير: يظهر التقرير ويمكن تعديله ضمن المهلة', (tester) async {
    await pumpDetail(
      tester,
      missionDetail(report: 'زرت الأسر الثلاث وسلّمت المساعدات'),
      viewer: 'emp-owner',
    );

    expect(find.text('أُغلقت المأمورية تلقائيًا وكُتب تقريرها لاحقًا'), findsOneWidget);
    expect(find.text('زرت الأسر الثلاث وسلّمت المساعدات'), findsOneWidget);
    expect(find.text('تعديل التقرير'), findsOneWidget);
  });

  testWidgets('بعد انقضاء 14 يومًا لا زر', (tester) async {
    await pumpDetail(
      tester,
      missionDetail(autoClosedAt: now.subtract(const Duration(days: 15))),
      viewer: 'emp-owner',
    );

    expect(find.text('انتهت مهلة كتابة التقرير.'), findsOneWidget);
    expect(find.text('كتابة تقرير المأمورية'), findsNothing);
  });
}
