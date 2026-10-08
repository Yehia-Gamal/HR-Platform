import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/team_operations_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testOpsData = MobileManagerOperations.fromJson({
    'from': '2026-10-01',
    'to': '2026-10-31',
    'metrics': {
      'scheduledToday': 5,
      'awayToday': 2,
      'overdueTasks': 1,
      'expiringDocuments': 2,
      'missingReports': 1,
    },
    'calendar': [
      {
        'id': 'roster-1',
        'employeeId': 'emp-1',
        'employeeName': 'أحمد محمود',
        'employeeCode': 'E-101',
        'workDate': '2026-10-05',
        'dayStatus': 'scheduled',
        'shiftName': 'وردية صباحية (09:00 - 17:00)',
        'startsAt': '09:00',
        'endsAt': '17:00',
        'notes': null,
      },
    ],
    'documentAlerts': [
      {
        'id': 'doc-1',
        'employeeId': 'emp-1',
        'employeeName': 'أحمد محمود',
        'employeeCode': 'E-101',
        'title': 'رخصة القيادة المهنية',
        'documentType': 'license',
        'expiryDate': '2026-10-25',
        'status': 'active',
      },
      {
        'id': 'doc-2',
        'employeeId': 'emp-2',
        'employeeName': 'سارة إبراهيم',
        'employeeCode': 'E-102',
        'title': 'عقد العمل الموحد',
        'documentType': 'contract',
        'expiryDate': '2026-09-30',
        'status': 'expired',
      },
    ],
    'tasks': [
      {
        'id': 'task-1',
        'employeeId': 'emp-1',
        'employeeName': 'أحمد محمود',
        'title': 'مراجعة أجهزة الحضور بالفرع',
        'priority': 'urgent',
        'status': 'pending',
        'dueDate': '2026-10-04',
        'isOverdue': true,
      },
    ],
    'missingReports': [
      {
        'employeeId': 'emp-3',
        'employeeName': 'محمد علي',
        'employeeCode': 'E-103',
      },
    ],
    'lastUpdatedAt': '2026-10-05T08:00:00Z',
  });

  Widget buildTestApp() {
    return ProviderScope(
      overrides: [
        mobileManagerOperationsProvider.overrideWith((ref) async => testOpsData),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar'), Locale('en')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: TeamOperationsSummaryPage(),
      ),
    );
  }

  testWidgets('renders monthly team operations summary with month navigator and KPIs',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // 1. Verify App Bar title
    expect(find.text('الملخص التشغيلي الشهري'), findsOneWidget);

    // 2. Verify Month navigator shows full month range
    expect(find.text('الشهر الحالي'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_outlined), findsWidgets);

    // 3. Verify Executive Metric Cards
    expect(find.text('مجدول اليوم'), findsOneWidget);
    expect(find.text('إجازة / مأمورية'), findsOneWidget);
    expect(find.text('مهام متأخرة'), findsOneWidget);
    expect(find.text('مستندات تنتهي'), findsOneWidget);
    expect(find.text('تقارير ناقصة'), findsOneWidget);

    expect(find.text('5'), findsOneWidget); // scheduledToday
    expect(find.text('2'), findsWidgets); // awayToday & expiringDocuments

    // 4. Verify Content items
    expect(find.text('جدول الفريق الشهري'), findsOneWidget);
    expect(find.textContaining('أحمد محمود'), findsWidgets);

    // Drag down to reveal tasks, documents, and reports
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.text('مراجعة أجهزة الحضور بالفرع'), findsOneWidget);
    expect(find.text('رخصة القيادة المهنية'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.text('محمد علي'), findsOneWidget);
    expect(find.text('بلا تقرير'), findsOneWidget);
  });

  testWidgets('filtering by tabs isolates sections', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Filter to tasks only
    final tasksChip = find.text('المهام (1)');
    await tester.ensureVisible(tasksChip);
    await tester.tap(tasksChip);
    await tester.pumpAndSettle();

    expect(find.text('المهام المفتوحة لفريقك'), findsOneWidget);
    expect(find.text('جدول الفريق الشهري'), findsNothing);
    expect(find.text('المستندات المنتهية قريباً'), findsNothing);

    // Filter to missing reports only
    final reportsChip = find.text('تقارير اليوم (1)');
    await tester.ensureVisible(reportsChip);
    await tester.tap(reportsChip);
    await tester.pumpAndSettle();

    expect(find.text('تقارير الإنجاز اليومية'), findsOneWidget);
    expect(find.text('المهام المفتوحة لفريقك'), findsNothing);
    expect(find.text('محمد علي'), findsOneWidget);
  });
}
