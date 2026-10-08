import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/month_glance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  final now = DateTime.now();
  String day(int d) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<Map<String, dynamic>> penalties,
  }) async {
    final statement = MonthlyAttendanceStatement.fromJson({
      'employee': {'id': 'emp-me', 'fullNameAr': 'موظف', 'employeeCode': 'E-1'},
      'period': {'year': now.year, 'month': now.month},
      'days': [
        {'date': day(1), 'status': 'حاضر', 'lateMinutes': 25, 'isDue': true},
        {'date': day(2), 'status': 'حاضر', 'lateMinutes': 0, 'isDue': true},
      ],
      'summary': {
        'attendanceRate': 92.4,
        'totalLateMinutes': 25,
        'attendanceRateBasis': {'presentInDue': 12, 'dueDays': 13},
      },
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myMonthlyStatementProvider.overrideWith((ref, params) async => statement),
          myLeaveBalancesProvider.overrideWith(
            (ref) async => [
              MobileLeaveBalance.fromJson({
                'leave_type_id': 'lt-annual',
                'code': 'annual',
                'name_ar': 'سنوية',
                'available_units': 12,
              }),
              MobileLeaveBalance.fromJson({
                'leave_type_id': 'lt-casual',
                'code': 'casual',
                'name_ar': 'عارضة',
                'available_units': 4.5,
              }),
            ],
          ),
          myInstantPenaltiesProvider.overrideWith(
            (ref) async => penalties.map(MobileInstantPenalty.fromJson).toList(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MonthGlanceCard())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('يلخّص الحضور والتأخير والرصيد والغرامات المستحقة', (tester) async {
    await pumpCard(
      tester,
      penalties: [
        {'id': 'p1', 'work_date': day(1), 'status': 'pending_payment', 'current_amount': 20, 'created_at': '${day(1)}T10:00:00Z'},
        {'id': 'p2', 'work_date': day(1), 'status': 'cancelled', 'current_amount': 50, 'created_at': '${day(1)}T10:00:00Z'},
        // غرامة الشهر الماضي لا تُحسب
        {'id': 'p3', 'work_date': '2000-01-01', 'status': 'pending_payment', 'current_amount': 150, 'created_at': '2000-01-01T10:00:00Z'},
      ],
    );

    expect(find.textContaining('شهري في لمحة'), findsOneWidget);
    expect(find.text('92%'), findsOneWidget);
    expect(find.text('12 من 13'), findsOneWidget);
    expect(find.text('يوم واحد'), findsOneWidget); // أيام التأخير
    expect(find.text('12 يومًا'), findsOneWidget); // رصيد السنوية
    expect(find.text('العارضة: 4.5'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // غرامة واحدة هذا الشهر (الملغاة لا تُحسب)
    expect(find.text('مستحق 20 ج.م'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('بلا غرامات: «لا غرامات» و«لا مستحقات»', (tester) async {
    await pumpCard(tester, penalties: const []);

    expect(find.text('لا غرامات'), findsOneWidget);
    expect(find.text('لا مستحقات'), findsOneWidget);
  });
}
