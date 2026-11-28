import 'dart:convert';

import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar'));
  late List<Map<String, dynamic>> submissions;
  late SupabaseClient client;
  setUp(() {
    submissions = [];
    client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(
          request.url.path,
          endsWith('/rpc/request_attendance_correction'),
        );
        submissions.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          '"00000000-0000-4000-8000-000000000099"',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDown(() => client.dispose());

  testWidgets('history opens its day and submits a missing checkout once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const workDate = '2026-07-16';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseProvider.overrideWithValue(client),
          accessContextProvider.overrideWith((ref) async => null),
          myAttendanceHistoryProvider.overrideWith(
            (ref) async => [
              AttendanceHistoryItem.fromJson({
                'id': 'punch',
                'eventAt': '${workDate}T06:00:00Z',
                'status': 'accepted',
              }),
            ],
          ),
          myMonthlyStatementProvider.overrideWith((ref, month) async {
            expect(month, (2026, 7));
            return MonthlyAttendanceStatement.fromJson({
              'days': [
                {
                  'date': workDate,
                  'dayNameAr': 'الخميس',
                  'status': 'يحتاج مراجعة',
                  'checkIn': '09:00',
                  'missingCheckOut': true,
                },
              ],
            });
          }),
          myAttendanceServicesProvider.overrideWith((ref) async {
            return MobileAttendanceServices.fromJson({
              'corrections': [
                if (submissions.isNotEmpty)
                  {
                    'workDate': workDate,
                    'createdAt': '2026-07-17T09:00:00Z',
                    'type': 'missing_check_out',
                    'status': 'pending',
                  },
              ],
            });
          }),
        ],
        child: const MaterialApp(home: AttendanceHistoryPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('تفاصيل اليوم والتصحيح'));
    await tester.pumpAndSettle();
    expect(find.text('لم يسجل انصراف'), findsOneWidget);
    await tester.tap(find.text('طلب تصحيح بصمة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'نسيت تسجيل الانصراف');
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pumpAndSettle();

    expect(submissions, [
      containsPair('p_check_out', '2026-07-16T14:00:00.000Z'),
    ]);
    expect(submissions.single['p_work_date'], workDate);
    expect(submissions.single['p_type'], 'missing_check_out');
    expect(submissions.single['p_check_in'], isNull);
    expect(find.text('تصحيح الانصراف · بانتظار المراجعة'), findsOneWidget);
    expect(find.text('طلب تصحيح بصمة'), findsNothing);
  });
}
