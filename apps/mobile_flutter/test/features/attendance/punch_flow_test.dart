import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';
import 'package:ahla_shabab_management_os/core/widgets/gps_preflight_banner.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeMobileCommands extends MobileCommands {
  _FakeMobileCommands(super.ref, this.onPunch);
  final Future<Map<String, dynamic>> Function(String eventType) onPunch;

  @override
  Future<Map<String, dynamic>> punchAttendanceLocal({
    required String eventType,
  }) => onPunch(eventType);
}

AttendanceState _sampleState() => const AttendanceState(
  attendanceRequired: true,
  selfPunchEnabled: true,
  activeLocalDevices: 1,
  hasActiveLocalDevice: true,
  canPunch: true,
  suggestedAction: 'CHECK_IN',
  lastEventType: null,
  lastEventAt: null,
  lastEventStatus: 'accepted',
  todayStatus: 'not_recorded',
  localDeviceStatus: 'active',
  todayCheckInAt: null,
  todayCheckOutAt: null,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar', null);
  });

  testWidgets(
    'displays pre-punch readiness (GPS, accuracy, range, registered device) and server-time receipt on punch',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            attendanceRealtimeProvider.overrideWithValue(null),
            attendanceStateProvider.overrideWith((_) async => _sampleState()),
            myWorkShiftInfoProvider.overrideWith(
              (_) async => MobileWorkShiftInfo.fromJson(const {}),
            ),
            myAttendanceServicesProvider.overrideWith(
              (_) async => MobileAttendanceServices(
                schedule: const [],
                corrections: const [],
                lastUpdatedAt: DateTime(2026, 11, 25),
              ),
            ),
            gpsPreflightProvider.overrideWith(
              (_) async => const GpsPreflightResult(
                serviceEnabled: true,
                permission: LocationPermission.whileInUse,
                accuracyMeters: 18.4,
                isMocked: false,
              ),
            ),
            mobileCommandsProvider.overrideWith(
              (ref) => _FakeMobileCommands(ref, (_) async {
                return {
                  'ok': true,
                  'recordedAt': '2026-11-25T07:05:00Z',
                  'distanceMeters': 14.2,
                };
              }),
            ),
          ],
          child: const MaterialApp(home: MobileAttendancePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('جاهزية البصمة قبل التسجيل'), findsOneWidget);
      expect(find.text('GPS جاهز · دقة 18 م (الحد 150 م)'), findsOneWidget);
      expect(find.text('النطاق: آخر بصمة داخل النطاق المعتمد ✓'), findsOneWidget);
      expect(find.text('الجهاز: مسجّل ومفعّل ✓'), findsOneWidget);

      final punchBtn = find.text('تسجيل الحضور').last;
      await tester.ensureVisible(punchBtn);
      await tester.tap(punchBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('متابعة وتسجيل'));
      await tester.pumpAndSettle();

      expect(find.textContaining('وقت الخادم:'), findsOneWidget);
      expect(find.textContaining('14 م من النطاق'), findsOneWidget);
    },
  );

  testWidgets(
    'shows no-connection error instead of queueing attendance punch offline',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            attendanceRealtimeProvider.overrideWithValue(null),
            attendanceStateProvider.overrideWith((_) async => _sampleState()),
            myWorkShiftInfoProvider.overrideWith(
              (_) async => MobileWorkShiftInfo.fromJson(const {}),
            ),
            myAttendanceServicesProvider.overrideWith(
              (_) async => MobileAttendanceServices(
                schedule: const [],
                corrections: const [],
                lastUpdatedAt: DateTime(2026, 11, 25),
              ),
            ),
            gpsPreflightProvider.overrideWith(
              (_) async => const GpsPreflightResult(
                serviceEnabled: true,
                permission: LocationPermission.whileInUse,
              ),
            ),
            mobileCommandsProvider.overrideWith(
              (ref) => _FakeMobileCommands(ref, (_) async {
                throw const AttendanceOfflineException();
              }),
            ),
          ],
          child: const MaterialApp(home: MobileAttendancePage()),
        ),
      );
      await tester.pumpAndSettle();

      final punchBtn = find.text('تسجيل الحضور').last;
      await tester.ensureVisible(punchBtn);
      await tester.tap(punchBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('متابعة وتسجيل'));
      await tester.pumpAndSettle();

      expect(find.textContaining('لا يوجد اتصال، حاول لاحقاً'), findsOneWidget);
    },
  );
}
