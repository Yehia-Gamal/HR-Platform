import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/weekly_executive_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('الملخص الأسبوعي للحضور التنفيذي', () {
    test('تحليل بيانات الملخص من metadata المنظمة', () {
      final item = MobileNotificationItem(
        id: 'notif-1',
        title: 'الملخص الأسبوعي للحضور',
        body: 'الملخص الأسبوعي للحضور (04/10/2026 - 10/10/2026): حضور 106، تأخر 16، غياب 64، إجازة 0.',
        category: 'system',
        priority: 'normal',
        actionUrl: '/reports/attendance',
        entityType: 'weekly_executive_summary',
        entityId: null,
        isRead: false,
        createdAt: DateTime(2026, 10, 11, 8, 0),
        metadata: {
          'periodId': '2026-10-04_2026-10-10',
          'startDate': '2026-10-04',
          'endDate': '2026-10-10',
          'summary': {
            'present': 106,
            'late': 16,
            'absent': 64,
            'onLeave': 2,
            'presentRate': 57.0,
            'lateRate': 8.6,
            'absentRate': 34.4,
            'totalLateMinutes': 140,
            'activeEmployees': 45,
          },
          'topLateEmployees': [
            {
              'employeeId': 'emp-1',
              'employeeName': 'أحمد مصطفى',
              'lateCount': 3,
              'totalMinutes': 45,
            },
          ],
          'absentGt3Employees': [
            {
              'employeeId': 'emp-2',
              'employeeName': 'محمد علي',
              'absentCount': 4,
            },
          ],
        },
      );

      final data = WeeklyExecutiveSummaryData.fromNotification(item);
      expect(data.startDateText, '2026-10-04');
      expect(data.endDateText, '2026-10-10');
      expect(data.presentCount, 106);
      expect(data.lateCount, 16);
      expect(data.absentCount, 64);
      expect(data.onLeaveCount, 2);
      expect(data.presentRate, 57.0);
      expect(data.lateRate, 8.6);
      expect(data.absentRate, 34.4);
      expect(data.totalLateMinutes, 140);
      expect(data.activeEmployees, 45);
      expect(data.topLateEmployees.length, 1);
      expect(data.topLateEmployees.first.employeeName, 'أحمد مصطفى');
      expect(data.absentGt3Employees.length, 1);
      expect(data.absentGt3Employees.first.employeeName, 'محمد علي');
    });

    test('تحليل بيانات الملخص الاحتياطي من نص الإشعار فقط (عند غياب metadata)', () {
      final item = MobileNotificationItem(
        id: 'notif-2',
        title: 'الملخص الأسبوعي للحضور',
        body: 'الملخص الأسبوعي للحضور (04/10/2026 - 10/10/2026): حضور 106، تأخر 16، غياب 64، إجازة 0. نسبة التأخر 8.6%، نسبة الغياب 34.4%. أعلى المتأخرين: مصطفى، يوسف.',
        category: 'system',
        priority: 'normal',
        actionUrl: '/reports/attendance',
        entityType: 'weekly_executive_summary',
        entityId: null,
        isRead: false,
        createdAt: DateTime(2026, 10, 11, 8, 0),
        metadata: const {},
      );

      final data = WeeklyExecutiveSummaryData.fromNotification(item);
      expect(data.startDateText, '04/10/2026');
      expect(data.endDateText, '10/10/2026');
      expect(data.presentCount, 106);
      expect(data.lateCount, 16);
      expect(data.absentCount, 64);
      expect(data.onLeaveCount, 0);
      expect(data.lateRate, 8.6);
      expect(data.absentRate, 34.4);
      expect(data.topLateEmployees.length, 2);
      expect(data.topLateEmployees[0].employeeName, 'مصطفى');
      expect(data.topLateEmployees[1].employeeName, 'يوسف');
    });

    test('توجيه الرابط العميق إلى شاشة الملخص الأسبوعي التنفيذي', () {
      final route = resolveRouteFromDeepLink(
        'ahlashabab://action/reports/attendance?start=2026-10-04&end=2026-10-10',
      );
      expect(
        route,
        '/action/weekly_executive_summary/default?start=2026-10-04&end=2026-10-10',
      );

      final page = getDirectActionPage(
        kind: 'weekly_executive_summary',
        actionId: 'default',
      );
      expect(page, isA<WeeklyExecutiveSummaryPage>());
    });

    testWidgets('عرض شاشة الملخص الأسبوعي وتفاعلها بدون أخطاء', (tester) async {
      final item = MobileNotificationItem(
        id: 'notif-ui',
        title: 'الملخص الأسبوعي للحضور',
        body: 'الملخص الأسبوعي للحضور (04/10/2026 - 10/10/2026): حضور 106، تأخر 16، غياب 64، إجازة 0.',
        category: 'system',
        priority: 'normal',
        actionUrl: '/reports/attendance',
        entityType: 'weekly_executive_summary',
        entityId: null,
        isRead: false,
        createdAt: DateTime(2026, 10, 11, 8, 0),
        metadata: {
          'startDate': '04/10/2026',
          'endDate': '10/10/2026',
          'summary': {
            'present': 106,
            'late': 16,
            'absent': 64,
            'onLeave': 0,
            'presentRate': 57.0,
            'lateRate': 8.6,
            'absentRate': 34.4,
          },
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: WeeklyExecutiveSummaryPage(item: item),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('الملخص الأسبوعي للحضور'), findsWidgets);
      expect(find.text('106'), findsOneWidget); // حضور
      expect(find.text('16'), findsOneWidget);  // تأخر
      expect(find.text('64'), findsOneWidget);  // غياب
      expect(find.text('مشاركة الملخص عبر واتساب'), findsOneWidget);
    });
  });
}
