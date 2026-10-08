import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
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
      // الملخص الشهري — قائمة المقاييس تستخدم 'حضور' (وليس 'إجمالي الحضور')
      expect(find.text('ملخص الشهر'), findsOneWidget);
      expect(find.text('حضور'), findsWidgets);
      // أيام الشهر القادمة تظهر في مفتاح التقويم كـ 'قادم'
      // (تمرير لأن القائمة كسولة ودليل الألوان تحت الطيّ في شاشة الاختبار).
      await tester.scrollUntilVisible(
        find.text('قادم'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('قادم'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  // شكوى المالك: المدير يفتح كشف مرؤوسه فيجد «طلب إجازة» و«تعديل حالة هذا اليوم»
  // و«نسيان بصمة» — وكلها تُقدَّم باسمه هو لا باسم الموظف.
  group('كشف موظف آخر للاطلاع فقط', () {
    final now = DateTime.now();
    final dayNum = now.day > 1 ? now.day - 1 : 1;
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${dayNum.toString().padLeft(2, '0')}';

    MonthlyAttendanceStatement statementOf(String employeeId, {bool canEditDays = false}) =>
        MonthlyAttendanceStatement.fromJson({
          'employee': {'id': employeeId, 'fullNameAr': 'موظف تجريبي', 'employeeCode': 'EMP-001'},
          'period': {'year': now.year, 'month': now.month},
          'capabilities': {'canEditDays': canEditDays},
          'days': [
            {
              'date': date,
              'status': 'حاضر',
              'checkOut': '17:00',
              'missingCheckIn': true,
              'lateMinutes': 20,
              'isDue': true,
            },
          ],
          'summary': {'scheduledDays': 22, 'presentDays': 1, 'missingCheckInCount': 1},
        });

    Future<void> pumpStatement(
      WidgetTester tester,
      MonthlyAttendanceStatement statement, {
      String? employeeId,
    }) async {
      // شاشة هاتف طويلة: ورقة اليوم وإجراءاتها تُبنى كاملة دون تمرير داخلي.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accessContextProvider.overrideWith(
              (ref) async => AccessContext.fromJson({
                'userId': 'user-me',
                'employeeId': 'emp-me',
                'displayName': 'مدير مباشر',
                'roles': ['direct-manager'],
              }),
            ),
            myMonthlyStatementProvider.overrideWith((ref, params) async => statement),
            employeeMonthlyStatementProvider.overrideWith((ref, params) async => statement),
          ],
          child: MaterialApp(
            home: MonthlyAttendanceStatementPage(employeeId: employeeId),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> showBanner(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('تنبيه نقص تسجيل البصمة'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    Future<void> openDay(WidgetTester tester) async {
      final cell = find.bySemanticsLabel(RegExp('^يوم $dayNum( |\$)'));
      await tester.scrollUntilVisible(cell, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.text('الإجراءات المتاحة'), findsOneWidget);
    }

    testWidgets('على كشف المرؤوس: لا طلبات باسم المدير ولا معالجة بصماته', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpStatement(tester, statementOf('emp-report'), employeeId: 'emp-report');

      await showBanner(tester);
      expect(find.text('معالجة البصمات المنسية'), findsNothing);
      await openDay(tester);
      expect(find.text('تعديل حالة هذا اليوم'), findsNothing);
      expect(find.text('تسجيل بصمة منسية'), findsNothing);
      expect(find.text('طلب إذن حضور'), findsNothing);
      expect(find.textContaining('للاطلاع فقط'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('الموارد البشرية على كشف موظف: التعديل الإداري وحده', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpStatement(tester, statementOf('emp-report', canEditDays: true), employeeId: 'emp-report');

      await openDay(tester);
      expect(find.text('تعديل اليوم إدارياً (حالة اليوم وساعات العمل)'), findsOneWidget);
      expect(find.text('تعديل حالة هذا اليوم'), findsNothing);
      expect(find.textContaining('للاطلاع فقط'), findsNothing);
      semantics.dispose();
    });

    testWidgets('على كشفي أنا: الطلبات الذاتية كما هي', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpStatement(tester, statementOf('emp-me'));

      await showBanner(tester);
      expect(find.text('معالجة البصمات المنسية'), findsOneWidget);
      await openDay(tester);
      expect(find.text('تسجيل بصمة منسية'), findsOneWidget);
      expect(find.text('طلب إذن حضور'), findsOneWidget);
      expect(find.textContaining('للاطلاع فقط'), findsNothing);
      semantics.dispose();
    });
  });
}
