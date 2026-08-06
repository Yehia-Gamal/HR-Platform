import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'employee statement shows the closed-days rate and the open shift separately',
    (tester) async {
      final statement = MonthlyAttendanceStatement.fromJson({
        'employee': {'fullNameAr': 'موظف تجريبي', 'employeeCode': 'EMP-001'},
        'period': {
          'year': DateTime.now().year,
          'month': DateTime.now().month,
          'startDate': '2026-08-01',
          'endDate': '2026-08-31',
          'generatedAt': '2026-08-03T12:00:00Z',
        },
        'days': const <Map<String, dynamic>>[],
        'summary': {
          'scheduledDays': 22,
          'dueScheduledDays': 2,
          'upcomingDays': 20,
          'presentDays': 2,
          'absentDays': 0,
          'openShiftDays': 1,
          'completedPresenceDays': 1,
          'attendanceRateBasis': {
            'presentInDue': 1,
            'dueDays': 2,
            'presentDays': 2,
            'absentDays': 0,
            'openShiftDays': 1,
            'upcomingDays': 20,
          },
        },
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myMonthlyStatementProvider.overrideWith(
              (ref, params) async => statement,
            ),
          ],
          child: const MaterialApp(home: MonthlyAttendanceStatementPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('موظف تجريبي'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('نسبة الحضور الشهرية'), findsOneWidget);
      expect(find.text('إجمالي الحضور'), findsOneWidget);
      expect(find.text('ورديات مفتوحة'), findsOneWidget);
      expect(find.text('أيام قادمة'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
