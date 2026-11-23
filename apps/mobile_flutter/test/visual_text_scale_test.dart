import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_list_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// فحص أن الشاشات الرئيسية لا تتجاوز التخطيط على هاتف صغير (360×640)
/// مع تكبير خط النظام — وهو أكثر سبب لتقارير «الشاشة مكسورة» على الموبايل.
const double _textScale = 1.6;

Widget _shell(Widget home) {
  return MaterialApp(
    locale: const Locale('ar', 'EG'),
    supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(_textScale)),
      child: child!,
    ),
    home: home,
  );
}

void _useSmallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920); // 360×640 @3x
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

MobileInstantPenalty _penalty({
  required String id,
  required String status,
  int lateMinutes = 10,
  double original = 20,
  double current = 20,
  String? notes,
  String excuseStatus = 'none',
  String? receiptRef,
}) => MobileInstantPenalty(
  id: id,
  workDate: '2026-10-05',
  lateMinutes: lateMinutes,
  originalAmount: original,
  currentAmount: current,
  currency: 'EGP',
  status: status,
  notes: notes,
  createdAt: DateTime(2026, 10, 4, 9, 30),
  excuseStatus: excuseStatus,
  excuseText: excuseStatus == 'submitted' ? 'ظرف طارئ وتأخير عن الميعاد' : null,
  receiptReferenceNumber: receiptRef,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar_EG');
    DateFormat.useNativeDigitsByDefaultFor('ar', false);
    DateFormat.useNativeDigitsByDefaultFor('ar_EG', false);
  });

  testWidgets('الغرامات لا تتجاوز التخطيط عند تكبير الخط', (tester) async {
    _useSmallPhone(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myInstantPenaltiesProvider.overrideWith(
            (ref) async => [
              _penalty(
                id: 'p1',
                status: 'pending_payment',
                notes:
                    'تأخير 15 دقيقة عن موعد العمل 10:00 - تم تسجيل البطاقة',
              ),
              _penalty(
                id: 'p2',
                status: 'doubled',
                current: 500,
                original: 20,
                lateMinutes: 95,
                excuseStatus: 'submitted',
                notes:
                    'تأخير 95 دقيقة (وصل 11:35 موعد العمل 10:00) - تم الإرسال',
              ),
              _penalty(id: 'p3', status: 'suspended', current: 500),
            ],
          ),
        ],
        child: _shell(const MyInstantPenaltiesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('الحضور لا يتجاوز التخطيط عند تكبير الخط', (tester) async {
    _useSmallPhone(tester);

    final attendanceState = AttendanceState(
      attendanceRequired: true,
      selfPunchEnabled: true,
      activeLocalDevices: 1,
      hasActiveLocalDevice: true,
      canPunch: true,
      suggestedAction: 'CHECK_IN',
      lastEventType: null,
      lastEventAt: null,
      lastEventStatus: null,
      todayStatus: 'present',
      localDeviceStatus: 'active',
      todayCheckInAt: DateTime(2026, 10, 5, 10, 5),
      todayCheckOutAt: null,
      workMinutes: 60,
    );

    final shiftInfo = MobileWorkShiftInfo(
      currentShift: CurrentWorkShift(
        id: 'shift-official',
        code: 'OFFICIAL',
        name: 'الدوام الأساسي (10 ص – 6 م)',
        nameEn: 'Standard Shift',
        startTime: '10:00:00',
        endTime: '18:00:00',
        graceInMinutes: 15,
        isAssigned: true,
        status: 'approved',
      ),
      availableShifts: const [
        MobileWorkShift(
          id: 'shift-official',
          code: 'OFFICIAL',
          name: 'الدوام الأساسي (10 ص – 6 م)',
          startTime: '10:00:00',
          endTime: '18:00:00',
          graceInMinutes: 15,
          isDefault: true,
        ),
      ],
      pendingRequest: null,
    );

    final services = MobileAttendanceServices(
      schedule: const [],
      corrections: [
        MobileAttendanceCorrection(
          id: 'corr-1',
          workDate: DateTime(2026, 10, 4),
          type: 'missing_check_in',
          requestedCheckIn: DateTime(2026, 10, 4, 10, 5),
          requestedCheckOut: null,
          requestedStatus: null,
          reason: 'نسيان تسجيل الحضور',
          status: 'pending',
          reviewNote: null,
          createdAt: DateTime(2026, 10, 4, 10, 10),
        ),
      ],
      lastUpdatedAt: DateTime(2026, 10, 5),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceRealtimeProvider.overrideWithValue(null),
          attendanceStateProvider.overrideWith((ref) async => attendanceState),
          myWorkShiftInfoProvider.overrideWith((ref) async => shiftInfo),
          myAttendanceServicesProvider.overrideWith((ref) async => services),
        ],
        child: _shell(const MobileAttendancePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('شبكة المؤشرات تتحمل خطًا كبيرًا جدًا', (tester) async {
    _useSmallPhone(tester);

    await tester.pumpWidget(
      _shell(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: MetricGrid(
                cards: [
                  ('حضور', '22', Icons.check_circle_outline, null),
                  ('غياب', '1', Icons.cancel_outlined, null),
                  ('إجازات', '3', Icons.beach_access_outlined, null),
                  ('مأموريات', '2', Icons.directions_car_outlined, null),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('أرصدة الإجازات لا تتجاوز التخطيط عند تكبير الخط', (
    tester,
  ) async {
    _useSmallPhone(tester);

    final balances = [
      MobileLeaveBalance.fromJson({
        'leave_type_id': 'lt-annual',
        'code': 'annual',
        'name_ar': 'سنوية',
        'available_units': 14,
        'consumed_units': 2,
        'reserved_units': 0,
      }),
      MobileLeaveBalance.fromJson({
        'leave_type_id': 'lt-casual',
        'code': 'casual',
        'name_ar': 'عارضة',
        'available_units': 5,
        'consumed_units': 1,
        'reserved_units': 0,
      }),
      MobileLeaveBalance.fromJson({
        'leave_type_id': 'lt-rest',
        'code': 'rest_day',
        'name_ar': 'بدل راحة أسبوعية',
        'available_units': 1,
        'consumed_units': 4,
        'reserved_units': 0,
      }),
    ];

    final permitBalance = MobilePermitBalance.fromJson({
      'month': '2026-11',
      'max_permits': 4,
      'max_hours': 8,
      'used_approved': 0,
      'used_pending': 0,
      'total_used': 0,
      'remaining_permits': 4,
      'remaining_hours': 8,
      'minutes_per_permit': 120,
      'has_remaining': true,
      'items': [],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myPermitBalanceProvider.overrideWith((ref) async => permitBalance),
        ],
        child: _shell(
          Scaffold(
            body: SingleChildScrollView(
              child: LeaveBalanceStrip(balances: balances),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // الشريط الأفقي كان بارتفاع ثابت لا يكبر مع الخط.
    await tester.tap(find.text('عرض شريط'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
