import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar', null);
  });

  const testShiftInfo = MobileWorkShiftInfo(
    currentShift: CurrentWorkShift(
      id: 'shift-1',
      code: 'OFFICIAL',
      name: 'الدوام الأساسي',
      startTime: '09:00:00',
      endTime: '17:00:00',
      graceInMinutes: 15,
      isAssigned: true,
      status: 'approved',
    ),
    availableShifts: [],
  );

  group('Mission Lifecycle & Direct Attendance Flow Test (0704)', () {
    testWidgets('1) أثناء سريان المأمورية: يحل زر إنهاء المأمورية محل زر الانصراف بدون كولداون', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final inProgressMissionState = AttendanceState(
        attendanceRequired: true,
        selfPunchEnabled: true,
        activeLocalDevices: 1,
        hasActiveLocalDevice: true,
        canPunch: true,
        suggestedAction: 'MISSION_IN_PROGRESS',
        lastEventType: 'CHECK_IN',
        lastEventAt: DateTime.now().subtract(const Duration(minutes: 10)),
        lastEventStatus: 'accepted',
        todayStatus: 'mission',
        localDeviceStatus: 'active',
        todayCheckInAt: DateTime.now().subtract(const Duration(minutes: 10)),
        todayCheckOutAt: null,
        missionToday: MissionToday(
          requestId: 'm-req-12345',
          type: 'mission',
          startTime: '09:00',
          execStatus: 'in_progress',
          startedAt: DateTime.now().subtract(const Duration(minutes: 10)),
          endedAt: null,
          autoCheckout: false,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            attendanceRealtimeProvider.overrideWithValue(null),
            attendanceStateProvider.overrideWith(
              (ref) async => inProgressMissionState,
            ),
            myWorkShiftInfoProvider.overrideWith(
              (ref) async => testShiftInfo,
            ),
            myAttendanceServicesProvider.overrideWith(
              (ref) async => MobileAttendanceServices(
                schedule: const [],
                corrections: const [],
                lastUpdatedAt: DateTime.now(),
              ),
            ),
          ],
          child: const MaterialApp(
            home: MobileAttendancePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // التحقق من ظهور بطاقة إنهاء المأمورية كإجراء رئيسي
      expect(find.text('إنهاء المأمورية'), findsAtLeast(1));
      expect(find.text('إنهاء المأمورية الآن'), findsOneWidget);
      expect(find.text('إلغاء المأمورية (العودة للوضع الطبيعي)'), findsOneWidget);

      // التأكد من عدم ظهور زر الانصراف الاعتيادي المقفل
      expect(find.text('تسجيل الانصراف'), findsNothing);

      // النقر على زر إنهاء المأمورية الآن
      await tester.tap(find.text('إنهاء المأمورية الآن'));
      await tester.pumpAndSettle();

      // التحقق من فتح نافذة الإنهاء وخياراتها
      expect(find.text('تقرير المأمورية (اختياري)'), findsOneWidget);
      expect(find.text('إنهاء والعودة للجمعية (استمرار الدوام)'), findsOneWidget);
      expect(find.text('إنهاء مع الانصراف من موقعي (من برّة برّة)'), findsOneWidget);

      // إغلاق النافذة
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
    });

    testWidgets('2) بعد إنهاء المأمورية والعودة للمقر: يظهر زر بصمة الانصراف العادي لاستكمال الدوام', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final afterReturnState = AttendanceState(
        attendanceRequired: true,
        selfPunchEnabled: true,
        activeLocalDevices: 1,
        hasActiveLocalDevice: true,
        canPunch: true,
        suggestedAction: 'CHECK_OUT',
        lastEventType: 'CHECK_IN',
        lastEventAt: DateTime.now().subtract(const Duration(hours: 3)),
        lastEventStatus: 'accepted',
        todayStatus: 'present',
        localDeviceStatus: 'active',
        todayCheckInAt: DateTime.now().subtract(const Duration(hours: 3)),
        todayCheckOutAt: null,
        missionToday: MissionToday(
          requestId: 'm-req-12345',
          type: 'mission',
          startTime: '09:00',
          execStatus: 'completed',
          startedAt: DateTime.now().subtract(const Duration(hours: 3)),
          endedAt: DateTime.now().subtract(const Duration(minutes: 30)),
          autoCheckout: false,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            attendanceRealtimeProvider.overrideWithValue(null),
            attendanceStateProvider.overrideWith(
              (ref) async => afterReturnState,
            ),
            myWorkShiftInfoProvider.overrideWith(
              (ref) async => testShiftInfo,
            ),
            myAttendanceServicesProvider.overrideWith(
              (ref) async => MobileAttendanceServices(
                schedule: const [],
                corrections: const [],
                lastUpdatedAt: DateTime.now(),
              ),
            ),
          ],
          child: const MaterialApp(
            home: MobileAttendancePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // التحقق من ظهور زر تسجيل الانصراف العادي في المقر
      expect(find.text('تسجيل الانصراف'), findsAtLeast(1));
      expect(find.text('إنهاء المأمورية الآن'), findsNothing);
    });

    testWidgets('3) بعد الإنهاء مع الانصراف الميداني: يكتمل اليوم وتظهر بطاقة اكتمال الحضور والانصراف', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final completedDayState = AttendanceState(
        attendanceRequired: true,
        selfPunchEnabled: true,
        activeLocalDevices: 1,
        hasActiveLocalDevice: true,
        canPunch: false,
        suggestedAction: 'DAY_COMPLETED',
        lastEventType: 'CHECK_OUT',
        lastEventAt: DateTime.now(),
        lastEventStatus: 'accepted',
        todayStatus: 'present',
        localDeviceStatus: 'active',
        todayCheckInAt: DateTime.now().subtract(const Duration(hours: 8)),
        todayCheckOutAt: DateTime.now(),
        missionToday: MissionToday(
          requestId: 'm-req-12345',
          type: 'mission',
          startTime: '09:00',
          execStatus: 'completed',
          startedAt: DateTime.now().subtract(const Duration(hours: 8)),
          endedAt: DateTime.now(),
          autoCheckout: false,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            attendanceRealtimeProvider.overrideWithValue(null),
            attendanceStateProvider.overrideWith(
              (ref) async => completedDayState,
            ),
            myWorkShiftInfoProvider.overrideWith(
              (ref) async => testShiftInfo,
            ),
            myAttendanceServicesProvider.overrideWith(
              (ref) async => MobileAttendanceServices(
                schedule: const [],
                corrections: const [],
                lastUpdatedAt: DateTime.now(),
              ),
            ),
          ],
          child: const MaterialApp(
            home: MobileAttendancePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // التحقق من ظهور بطاقة اكتمال اليوم
      expect(find.text('اكتمل حضورك وانصرافك اليوم'), findsOneWidget);
      expect(find.text('ستظهر بصمتك من جديد بعد منتصف الليل'), findsOneWidget);
    });
  });
}
