import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_inbox_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/team_requests_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// الأحدث أولًا في اعتماد طلبات الفريق (قرار المالك):
///   • لا «دورك أولًا ثم الأقدم انتظارًا» — كان الطلب القديم المتأخر يتصدّر.
///   • التصحيحات والطلبات خط زمني واحد — كانت كتلة التصحيحات (ولو قديمة)
///     تُعرض فوق كل الطلبات.
void main() {
  const me = 'emp-me';

  Map<String, dynamic> request(
    String id,
    String name,
    String createdAt, {
    bool awaitingMe = false,
    String? decisionDueAt,
  }) => {
    'id': id,
    'requestNumber': id.hashCode.abs() % 1000,
    'requestType': 'leave',
    'status': 'pending',
    'workflowStatus': 'pending',
    'title': 'إجازة',
    'employeeId': 'emp-$id',
    'employeeName': name,
    'isMine': false,
    'canDecide': true,
    'awaitingMe': awaitingMe,
    'decisionDueAt': decisionDueAt,
    'payload': <String, dynamic>{},
    'createdAt': createdAt,
  };

  Map<String, dynamic> correction(String id, String name, String createdAt) => {
    'id': id,
    'employeeId': 'emp-$id',
    'employeeName': name,
    'employeeCode': 'E-$id',
    'workDate': createdAt.substring(0, 10),
    'type': 'missing_check_in',
    'requestedCheckIn': '${createdAt.substring(0, 10)}T08:11:00Z',
    'reason': 'نسيت البصمة',
    'status': 'pending',
    'canDecide': true,
    'createdAt': createdAt,
  };

  final requests = [
    // الأقدم، «دورك الآن» ومتأخر — كان يتصدّر القائمة
    request(
      'r-old',
      'طلب أغسطس',
      '2026-08-10T09:00:00Z',
      awaitingMe: true,
      decisionDueAt: '2026-08-12T09:00:00Z',
    ),
    request('r-new', 'طلب أكتوبر', '2026-10-05T09:00:00Z'),
    request('r-mid', 'طلب سبتمبر', '2026-09-20T09:00:00Z', awaitingMe: true),
  ].map(MobileRequest.fromJson).toList();

  final corrections = [
    correction('c-new', 'تصحيح أكتوبر', '2026-10-06T07:00:00Z'),
    correction('c-old', 'تصحيح أغسطس', '2026-08-17T07:00:00Z'),
  ].map(MobileTeamAttendanceCorrection.fromJson).toList();

  const access = AccessContext(
    userId: 'user-me',
    employeeId: me,
    displayName: 'مدير',
    employeeCode: 'E-ME',
    roles: ['manager'],
    permissions: ['requests.request.approve', 'attendance.correction.review'],
    workspaces: [WorkspaceId.manager],
    defaultWorkspace: WorkspaceId.manager,
    attendancePolicy: AttendancePolicy(
      attendanceRequired: true,
      selfPunchEnabled: true,
      liveLocationResponseEnabled: false,
    ),
  );

  testWidgets('بانتظار القرار: الأحدث أولًا والتصحيحات ضمن الخط الزمني نفسه', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accessContextProvider.overrideWith((ref) async => access),
          mobileTeamProvider.overrideWith((ref) async => const []),
          mobileRequestsProvider.overrideWith((ref) async => requests),
          teamAttendanceCorrectionsProvider.overrideWith(
            (ref, status) async => corrections,
          ),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          supportedLocales: [Locale('ar'), Locale('en')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: TeamRequestsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const expected = [
      'تصحيح أكتوبر', // 06/10
      'طلب أكتوبر', // 05/10
      'طلب سبتمبر', // 20/09
      'تصحيح أغسطس', // 17/08
      'طلب أغسطس', // 10/08 — رغم «دورك الآن» والتأخر
    ];
    final tops = [
      for (final name in expected) tester.getTopLeft(find.text(name)).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '«${expected[i]}» يجب أن يأتي بعد «${expected[i - 1]}»',
      );
    }
  });

  testWidgets('صندوق الإجراءات: طلبات بانتظار القرار الأحدث أولًا', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // مركز الإجراءات يرتّب بآخر تحديث — نعطيه ترتيبًا مختلطًا عمدًا
    final actions = [
      for (final id in ['r-mid', 'r-old', 'r-new'])
        MobileActionItem.fromJson({
          'id': 'request-$id',
          'kind': 'request',
          'title': 'طلب',
          'priority': 'normal',
          'status': 'pending',
        }),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accessContextProvider.overrideWith((ref) async => access),
          mobileActionCenterProvider.overrideWith((ref) async => actions),
          mobileRequestsProvider.overrideWith((ref) async => requests),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          supportedLocales: [Locale('ar'), Locale('en')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: MobileActionInboxPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const expected = ['طلب أكتوبر', 'طلب سبتمبر', 'طلب أغسطس'];
    final tops = [
      for (final name in expected)
        tester.getTopLeft(find.textContaining(name)).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '«${expected[i]}» يجب أن يأتي بعد «${expected[i - 1]}»',
      );
    }
  });
}
