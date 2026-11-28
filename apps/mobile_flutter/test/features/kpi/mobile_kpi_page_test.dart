import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  final access = AccessContext.fromJson({
    'employeeId': 'me',
    'permissions': ['performance.kpi.self_assess'],
    'workspaces': ['manager'],
  });

  MobileKpiEvaluation evaluation(
    String employeeId, {
    required String stage,
    required String status,
    String? relation,
  }) => MobileKpiEvaluation.fromJson({
    'id': employeeId,
    'employeeId': employeeId,
    'employeeName': employeeId == 'me' ? 'موظف الاختبار' : 'موظف الفريق',
    'periodMonth': '2026-08-01',
    'currentStage': stage,
    'workflowStatus': status,
    'relation': relation,
  });

  Future<void> pump(
    WidgetTester tester,
    MobileKpiEvaluation mine, {
    required bool locked,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accessContextProvider.overrideWith((ref) async => access),
          mobileKpiProvider.overrideWith(
            (ref) async => [
              mine,
              evaluation(
                'other',
                stage: 'manager_review',
                status: 'SUBMITTED_TO_DIRECT_MANAGER',
                relation: 'review',
              ),
            ],
          ),
          kpiEvaluationFormProvider.overrideWith(
            (ref, id) async => KpiEvaluationForm.fromJson({
              'id': id,
              'employeeId': mine.employeeId,
              'employeeName': mine.employeeName,
              'periodMonth': '2026-08-01',
              'currentStage': mine.currentStage,
              'workflowStatus': mine.workflowStatus,
              'editableStage': locked ? null : 'self',
              'locked': locked,
            }),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: MobileKpiPage(access: access)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('التقييم المتأخر يفتح التفاصيل ويشرح القفل', (tester) async {
    await pump(
      tester,
      evaluation('me', stage: 'manager_review', status: 'OVERDUE'),
      locked: true,
    );
    expect(find.text('تقييمي'), findsOneWidget);
    expect(find.text('المهام'), findsNothing);
    expect(find.text('فتح مراجعة التقييم'), findsNothing);
    await tester.tap(find.text('تقييمات الموظفين'));
    await tester.pumpAndSettle();
    expect(find.text('موظف الفريق'), findsOneWidget);
    await tester.tap(find.text('تقييمي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عرض تفاصيل التقييم'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل التقييم'), findsOneWidget);
    expect(find.textContaining('انتهت مهلة الدورة'), findsOneWidget);
    expect(find.text('تسليم التقييم الذاتي للمدير'), findsNothing);
  });

  testWidgets('التقييم الذاتي المفتوح يصل إلى نموذج الإرسال', (tester) async {
    await pump(
      tester,
      evaluation('me', stage: 'self', status: 'OPEN_FOR_SELF_EVALUATION'),
      locked: false,
    );
    await tester.tap(find.text('بدء التقييم الذاتي'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل التقييم'), findsOneWidget);
    expect(
      find.text('تسليم التقييم الذاتي للمدير', skipOffstage: false),
      findsOneWidget,
    );
  });
}
