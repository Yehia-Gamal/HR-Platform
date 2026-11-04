import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/penalties_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mockAccess = AccessContext.fromJson({
    'userId': 'user-admin',
    'employeeId': 'emp-admin',
    'displayName': 'Admin',
    'employeeCode': 'ADM01',
    'roles': ['admin'],
    'permissions': ['all'],
    'workspaces': ['admin'],
    'defaultWorkspace': 'admin',
    'attendancePolicy': <String, dynamic>{},
  });

  final mockSuspended = [
    SuspendedEmployeeInfo(
      employeeId: 'emp-1',
      employeeName: 'طارق سيد إبراهيم',
      employeeCode: 'EMP001',
      departmentName: 'إدارة الحركة',
      jobTitle: 'سائق',
      photoUrl: null,
      phone: '01000000000',
      status: 'suspended',
      isActive: false,
      totalCurrentDue: 2000.0,
      totalOriginalDue: 600.0,
      has500Penalty: true,
      unpaidCount: 4,
      penalties: [
        {
          'id': 'pen-1',
          'workDate': '2026-11-02',
          'lateMinutes': 120,
          'originalAmount': 150.0,
          'currentAmount': 500.0,
          'status': 'suspended',
        }
      ],
    ),
  ];

  Widget buildTestWidget() {
    return ProviderScope(
      overrides: [
        accessContextProvider.overrideWith((ref) async => mockAccess),
        suspendedEmployeesProvider.overrideWith((ref) async => mockSuspended),
        myInstantPenaltiesProvider.overrideWith((ref) async => <MobileInstantPenalty>[]),
      ],
      child: const MaterialApp(
        locale: Locale('ar', 'EG'),
        supportedLocales: [Locale('ar', 'EG'), Locale('en')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: MyInstantPenaltiesPage(initialIndex: 2),
        ),
      ),
    );
  }

  testWidgets('SuspendedEmployeesTab displays bulk lift button and individual card', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('طارق سيد إبراهيم'), findsOneWidget);
    expect(find.text('موقوف عن العمل'), findsWidgets);
    expect(find.text('رفع إيقاف جميع الموظفين (1) دفعة واحدة'), findsOneWidget);
    expect(find.text('رفع الإيقاف إدارياً'), findsOneWidget);
  });

  testWidgets('Bulk lift opens fast confirmation dialog without reason/note text fields', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final bulkBtn = find.text('رفع إيقاف جميع الموظفين (1) دفعة واحدة');
    await tester.tap(bulkBtn);
    await tester.pumpAndSettle();

    // Verify confirmation dialog without any text field
    expect(find.text('رفع إيقاف جميع الموظفين'), findsOneWidget);
    expect(find.text('رفع الإيقاف للجميع (1)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);

    // Close dialog
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });

  testWidgets('Individual lift opens fast confirmation dialog without reason/note text fields', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final singleBtn = find.text('رفع الإيقاف إدارياً');
    await tester.ensureVisible(singleBtn);
    await tester.pumpAndSettle();

    await tester.tap(singleBtn);
    await tester.pumpAndSettle();

    // Verify dialog with no note input field
    expect(find.text('رفع الإيقاف عن العمل'), findsOneWidget);
    expect(find.text('تأكيد رفع الإيقاف'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);

    // Close dialog
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
}
