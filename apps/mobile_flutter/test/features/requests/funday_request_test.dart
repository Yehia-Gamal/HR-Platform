import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_self_service_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  group('hasFieldExecution helper test', () {
    test('fundraising does NOT have field execution, missions and convoys do', () {
      expect(hasFieldExecution('mission'), isTrue);
      expect(hasFieldExecution('convoy'), isTrue);
      expect(hasFieldExecution('fundraising'), isFalse);
      expect(hasFieldExecution('leave'), isFalse);
    });
  });

  group('Funday Request Details UI', () {
    testWidgets('Funday detail does NOT render _MissionExecutionCard and shows cancel label for funday', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now().toUtc();
      final fundayDetail = MobileRequestDetail.fromJson({
        'id': 'req-funday-1',
        'requestNumber': 88,
        'requestType': 'fundraising',
        'employeeId': 'emp-owner',
        'employeeName': 'يحيى جمال',
        'employeeCode': 'EMP-01',
        'title': 'فاندي للريف الأوروبي',
        'reason': 'يوم ترفيهي للموظفين لقضاء عطلة على حساب العمل',
        'status': 'pending',
        'workflowStatus': 'submitted',
        'payload': {
          'startDate': now.toIso8601String().substring(0, 10),
          'endDate': now.toIso8601String().substring(0, 10),
          'location': 'الريف الأوروبي فيلا لازورد',
        },
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'canDecide': false,
        'canCancel': true,
        'canResubmit': false,
        'steps': [],
        'attachments': [],
        'conflicts': [],
        'decisionMode': 'DIRECT',
        'decisionOnBehalfOfExecutive': false,
        'missionExecution': null,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accessContextProvider.overrideWith(
              (ref) async => AccessContext.fromJson({
                'userId': 'user-emp-owner',
                'employeeId': 'emp-owner',
                'displayName': 'يحيى جمال',
                'roles': ['employee'],
              }),
            ),
            mobileRequestDetailProvider('req-funday-1').overrideWith(
              (ref) async => fundayDetail,
            ),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            supportedLocales: [Locale('ar')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MobileRequestDetailPage(requestId: 'req-funday-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify "تنفيذ الفاندي" or "ابدأ الفاندي الآن" is NOT rendered
      expect(find.text('تنفيذ الفاندي'), findsNothing);
      expect(find.text('ابدأ الفاندي الآن'), findsNothing);

      // Verify the cancel button label is "إلغاء الفاندي" NOT "إلغاء المأمورية"
      expect(find.text('إلغاء المأمورية'), findsNothing);
      expect(find.text('إلغاء الفاندي'), findsOneWidget);
    });
  });

  group('Funday Request Submission Form UI', () {
    testWidgets('NewRequestSheet for fundraising has no start/end time buttons and allows submit without reason', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? submittedData;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  final res = await showModalBottomSheet<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => const NewRequestSheet(type: 'fundraising'),
                  );
                  submittedData = res;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify title
      expect(find.text('طلب يوم ترفيهي (فاندي)'), findsOneWidget);

      // Verify banner
      expect(find.textContaining('يوم ترفيهي للموظفين لقضاء عطلة على حساب العمل'), findsOneWidget);

      // Verify NO start/end time buttons
      expect(find.text('وقت البداية (اختياري)'), findsNothing);
      expect(find.text('وقت النهاية (اختياري)'), findsNothing);

      // Verify reason is labeled as optional notes
      expect(find.text('ملاحظات إضافية (اختياري)'), findsOneWidget);

      // Tap submit button without touching anything
      await tester.tap(find.text('إرسال الطلب'));
      await tester.pumpAndSettle();

      // Should have successfully submitted!
      expect(submittedData, isNotNull);
      expect(submittedData!['title'], contains('يوم ترفيهي'));
      expect(submittedData!['reason'], contains('يوم ترفيهي للموظفين'));
      final payload = submittedData!['payload'] as Map;
      expect(payload['location'], isNotNull);
      expect(payload.containsKey('startTime'), isFalse);
      expect(payload.containsKey('endTime'), isFalse);
    });
  });
}
