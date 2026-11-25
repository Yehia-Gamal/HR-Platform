import 'package:ahla_shabab_management_os/core/widgets/gps_preflight_banner.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _MockLoginAndPunchCommands extends MobileCommands {
  _MockLoginAndPunchCommands(super.ref);
  bool punched = false;

  @override
  Future<Map<String, dynamic>> punchAttendanceLocal({
    required String eventType,
  }) async {
    punched = true;
    return {
      'ok': true,
      'eventType': eventType,
      'recordedAt': '2026-11-25T07:00:00Z',
      'distanceMeters': 8.0,
    };
  }
}

class _FlowHarness extends ConsumerStatefulWidget {
  const _FlowHarness();

  @override
  ConsumerState<_FlowHarness> createState() => _FlowHarnessState();
}

class _FlowHarnessState extends ConsumerState<_FlowHarness> {
  bool _loggedIn = false;
  final _idCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedIn) {
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                key: const Key('login-identifier'),
                controller: _idCtrl,
                decoration: const InputDecoration(labelText: 'البريد أو الهاتف'),
              ),
              TextField(
                key: const Key('login-password'),
                controller: _pwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة المرور'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('login-submit'),
                onPressed: () {
                  if (_idCtrl.text.isNotEmpty && _pwdCtrl.text.isNotEmpty) {
                    setState(() => _loggedIn = true);
                  }
                },
                child: const Text('تسجيل الدخول'),
              ),
            ],
          ),
        ),
      );
    }
    return const MobileAttendancePage();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ar', null);
  });

  testWidgets('mocked login -> attendance readiness -> punch flow succeeds', (
    tester,
  ) async {
    late _MockLoginAndPunchCommands commands;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceRealtimeProvider.overrideWithValue(null),
          attendanceStateProvider.overrideWith(
            (_) async => const AttendanceState(
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
            ),
          ),
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
              accuracyMeters: 12,
              isMocked: false,
            ),
          ),
          mobileCommandsProvider.overrideWith((ref) {
            commands = _MockLoginAndPunchCommands(ref);
            return commands;
          }),
        ],
        child: const MaterialApp(home: _FlowHarness()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('login-identifier')),
      '01000000001',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'Pass12345!',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('جاهزية البصمة قبل التسجيل'), findsOneWidget);
    final punchBtn = find.text('تسجيل الحضور').last;
    await tester.ensureVisible(punchBtn);
    await tester.tap(punchBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('متابعة وتسجيل'));
    await tester.pumpAndSettle();

    expect(commands.punched, isTrue);
    expect(find.textContaining('وقت الخادم:'), findsOneWidget);
  });
}
