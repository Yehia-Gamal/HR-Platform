import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar', null);
    FlutterError.onError = (details) {
      debugPrint('SUMMARY: ${details.summary}');
      for (final prop in details.toDiagnosticsNode().getChildren()) {
        debugPrint('CHILD_PROP: ${prop.value}');
      }
    };
  });

  testWidgets(
    'MobileAttendancePage renders work shift section, policy dialog, and interactive shift selection sheet',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockAttendanceState = AttendanceState(
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
        todayCheckInAt: null,
        todayCheckOutAt: null,
      );

      final mockShiftInfo = MobileWorkShiftInfo(
        currentShift: CurrentWorkShift(
          id: 'shift-official-uuid',
          code: 'OFFICIAL',
          name: 'الدوام الأساسي (10 ص – 6 م)',
          nameEn: 'Standard Shift (10 AM - 6 PM)',
          startTime: '10:00:00',
          endTime: '18:00:00',
          graceInMinutes: 15,
          isAssigned: true,
          assignmentId: 'assign-1',
          effectiveFrom: DateTime(2026, 10, 4),
          status: 'approved',
        ),
        availableShifts: const [
          MobileWorkShift(
            id: 'shift-9-5-uuid',
            code: 'SHIFT_9_5',
            name: 'فترة صباحية (9 ص – 5 م)',
            startTime: '09:00:00',
            endTime: '17:00:00',
            graceInMinutes: 15,
            isDefault: false,
            description: 'تبدأ 9:00 ص وتنتهي 5:00 م',
          ),
          MobileWorkShift(
            id: 'shift-official-uuid',
            code: 'OFFICIAL',
            name: 'الدوام الأساسي (10 ص – 6 م)',
            startTime: '10:00:00',
            endTime: '18:00:00',
            graceInMinutes: 15,
            isDefault: true,
            description: 'الدوام الرسمي العام',
          ),
          MobileWorkShift(
            id: 'shift-11-7-uuid',
            code: 'SHIFT_11_7',
            name: 'فترة مسائية (11 ص – 7 م)',
            startTime: '11:00:00',
            endTime: '19:00:00',
            graceInMinutes: 15,
            isDefault: false,
            description: 'تبدأ 11:00 ص وتنتهي 7:00 م',
          ),
        ],
        pendingRequest: null,
      );

      final mockServices = MobileAttendanceServices(
        schedule: const [],
        corrections: const [],
        lastUpdatedAt: DateTime(2026, 10, 4),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            attendanceRealtimeProvider.overrideWithValue(null),
            attendanceStateProvider.overrideWith(
              (ref) async => mockAttendanceState,
            ),
            myWorkShiftInfoProvider.overrideWith(
              (ref) async => mockShiftInfo,
            ),
            myAttendanceServicesProvider.overrideWith(
              (ref) async => mockServices,
            ),
          ],
          child: const MaterialApp(
            home: MobileAttendancePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // التحقق من ظهور عنوان فترات العمل
      expect(find.text('فترة العمل والورديات'), findsOneWidget);

      // التحقق من ظهور اسم الوردية الحالية وشارة الاعتماد الرسمي
      expect(find.text('الدوام الأساسي (10 ص – 6 م)'), findsOneWidget);
      expect(find.text('معتمدة من الإدارة'), findsAtLeastNWidgets(1));

      // التحقق من رقائق تفاصيل المواعيد
      expect(find.text('الحضور: 10:00 ص'), findsOneWidget);
      expect(find.text('سماح: 15 دقيقة'), findsOneWidget);
      expect(find.text('الانصراف: 6:00 م'), findsOneWidget);

      // التحقق من زر سياسة الدوام وفتحه
      final policyButton = find.text('السياسة');
      expect(policyButton, findsOneWidget);
      await tester.tap(policyButton);
      await tester.pumpAndSettle();

      // التحقق من محتوى نافذة السياسة وإغلاقها
      expect(find.text('سياسة فترات العمل والتأخير'), findsOneWidget);
      expect(find.text('فترة السماح (15 دقيقة)'), findsOneWidget);
      await tester.tap(find.text('حسناً، فهمت'));
      await tester.pumpAndSettle();

      // النقر على زر تغيير الفترة لفتح نافذة الاختيار السلسة
      final changeButton = find.text('تغيير الفترة');
      expect(changeButton, findsOneWidget);
      await tester.tap(changeButton);
      await tester.pumpAndSettle();

      // التحقق من ظهور النافذة والورديات المتاحة
      expect(find.text('اختيار وتغيير فترة العمل'), findsOneWidget);
      expect(find.text('فترة صباحية (9 ص – 5 م)'), findsOneWidget);
      expect(find.text('فترة مسائية (11 ص – 7 م)'), findsOneWidget);
      expect(find.text('فترتك الحالية'), findsOneWidget);

      // النقر على الوردية الصباحية لاختيارها
      await tester.tap(find.text('فترة صباحية (9 ص – 5 م)'));
      await tester.pumpAndSettle();

      // التحقق من ظهور بطاقة ملخص الانتقال المقترح
      expect(find.text('ملخص التغيير المطلوب:'), findsOneWidget);

      // النقر على أحد أزرار الأسباب السريعة
      final transportChip = find.text('🚌 مواعيد المواصلات');
      expect(transportChip, findsOneWidget);
      await tester.tap(transportChip);
      await tester.pumpAndSettle();

      // التحقق من تعبئة سبب التغيير وظهور زر الإرسال النشط
      expect(find.text('مواعيد المواصلات'), findsOneWidget);
      expect(find.text('إرسال طلب تغيير الوردية للاعتماد'), findsOneWidget);

      // إغلاق النافذة
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // التحقق من عدم وجود أي أخطاء أو تجاوزات
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'MobileAttendancePage renders pending shift change request and navigates to detail',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockAttendanceState = AttendanceState(
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
        todayCheckInAt: null,
        todayCheckOutAt: null,
      );

      final mockShiftInfoWithPending = MobileWorkShiftInfo(
        currentShift: CurrentWorkShift(
          id: 'shift-official-uuid',
          code: 'OFFICIAL',
          name: 'الدوام الأساسي (10 ص – 6 م)',
          startTime: '10:00:00',
          endTime: '18:00:00',
          graceInMinutes: 15,
          isAssigned: true,
          status: 'approved',
        ),
        availableShifts: const [
          MobileWorkShift(
            id: 'shift-9-5-uuid',
            code: 'SHIFT_9_5',
            name: 'فترة صباحية (9 ص – 5 م)',
            startTime: '09:00:00',
            endTime: '17:00:00',
            graceInMinutes: 15,
          ),
          MobileWorkShift(
            id: 'shift-official-uuid',
            code: 'OFFICIAL',
            name: 'الدوام الأساسي (10 ص – 6 م)',
            startTime: '10:00:00',
            endTime: '18:00:00',
            graceInMinutes: 15,
            isDefault: true,
          ),
        ],
        pendingRequest: const PendingShiftChange(
          requestId: 'req-shift-change-123',
          title: 'طلب تغيير فترة العمل',
          reason: 'مواعيد مواصلات السكن الجديدة',
          requestedShiftId: 'shift-9-5-uuid',
          requestedShiftName: 'فترة صباحية (9 ص – 5 م)',
          status: 'pending',
        ),
      );

      final mockDetail = MobileRequestDetail.fromJson({
        'id': 'req-shift-change-123',
        'requestNumber': 101,
        'type': 'shift_change',
        'employeeName': 'أحمد محمد',
        'employeeCode': 'EMP-01',
        'title': 'طلب تغيير فترة العمل',
        'reason': 'مواعيد مواصلات السكن الجديدة',
        'status': 'pending',
        'workflowStatus': 'pending',
        'payload': {
          'shiftId': 'shift-9-5-uuid',
          'shiftName': 'فترة صباحية (9 ص – 5 م)',
          'startTime': '09:00:00',
          'endTime': '17:00:00',
        },
        'createdAt': '2026-10-04T10:00:00Z',
        'updatedAt': '2026-10-04T10:00:00Z',
        'canDecide': false,
        'canCancel': true,
        'canResubmit': false,
        'steps': [],
        'attachments': [],
        'conflicts': [],
        'decisionMode': 'DIRECT',
        'decisionOnBehalfOfExecutive': false,
      });

      final mockServices = MobileAttendanceServices(
        schedule: const [],
        corrections: const [],
        lastUpdatedAt: DateTime(2026, 10, 4),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            attendanceRealtimeProvider.overrideWithValue(null),
            attendanceStateProvider.overrideWith(
              (ref) async => mockAttendanceState,
            ),
            myWorkShiftInfoProvider.overrideWith(
              (ref) async => mockShiftInfoWithPending,
            ),
            myAttendanceServicesProvider.overrideWith(
              (ref) async => mockServices,
            ),
            mobileRequestDetailProvider('req-shift-change-123').overrideWith(
              (ref) async => mockDetail,
            ),
          ],
          child: const MaterialApp(
            home: MobileAttendancePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // التحقق من ظهور بطاقة الطلب المعلق مع شارة بانتظار الإدارة
      expect(
        find.text('طلب قيد المراجعة والاعتماد: فترة صباحية (9 ص – 5 م)'),
        findsOneWidget,
      );
      expect(find.text('مواعيد مواصلات السكن الجديدة'), findsOneWidget);
      expect(find.text('بانتظار الإدارة'), findsOneWidget);

      // النقر على بطاقة الطلب المعلق للانتقال لصفحة التفاصيل
      final pendingFinder = find.text('طلب قيد المراجعة والاعتماد: فترة صباحية (9 ص – 5 م)');
      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pumpAndSettle();
      await tester.tap(pendingFinder);
      await tester.pumpAndSettle();

      // التحقق من فتح صفحة تفاصيل الطلب MobileRequestDetailPage
      expect(find.byType(MobileRequestDetailPage), findsOneWidget);

      final exc = tester.takeException();
      if (exc != null) {
        if (exc is FlutterError) {
          debugPrint('FULL_ERROR: ${exc.toStringDeep()}');
        }
      }
      expect(exc, isNull);
    },
  );

  testWidgets(
    'MobileAttendancePage renders corrections section with filter tabs, quick chips, and shift integration',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockAttendanceState = AttendanceState(
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
        todayCheckInAt: DateTime(2026, 10, 5, 10, 5), // within 15m grace!
        todayCheckOutAt: null,
      );

      final mockShiftInfo = MobileWorkShiftInfo(
        currentShift: CurrentWorkShift(
          id: 'shift-official-uuid',
          code: 'OFFICIAL',
          name: 'الدوام الأساسي (10 ص – 6 م)',
          startTime: '10:00:00',
          endTime: '18:00:00',
          graceInMinutes: 15,
          isAssigned: true,
          status: 'approved',
        ),
        availableShifts: const [
          MobileWorkShift(
            id: 'shift-official-uuid',
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

      final mockCorrections = [
        MobileAttendanceCorrection(
          id: 'corr-pending-1',
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
        MobileAttendanceCorrection(
          id: 'corr-approved-1',
          workDate: DateTime(2026, 10, 3),
          type: 'missing_check_out',
          requestedCheckIn: null,
          requestedCheckOut: DateTime(2026, 10, 3, 18, 0),
          requestedStatus: null,
          reason: 'عطل في شبكة المقر',
          status: 'approved',
          reviewNote: 'تم التحقق واعتماد التصحيح',
          createdAt: DateTime(2026, 10, 3, 18, 15),
        ),
        MobileAttendanceCorrection(
          id: 'corr-rejected-1',
          workDate: DateTime(2026, 10, 2),
          type: 'wrong_time',
          requestedCheckIn: null,
          requestedCheckOut: null,
          requestedStatus: null,
          reason: 'طلب تعديل وقت البصمة',
          status: 'rejected',
          reviewNote: 'لا يتوفر إثبات كافٍ',
          createdAt: DateTime(2026, 10, 2, 12, 0),
        ),
      ];

      final mockServices = MobileAttendanceServices(
        schedule: const [],
        corrections: mockCorrections,
        lastUpdatedAt: DateTime(2026, 10, 5),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            attendanceRealtimeProvider.overrideWithValue(null),
            attendanceStateProvider.overrideWith(
              (ref) async => mockAttendanceState,
            ),
            myWorkShiftInfoProvider.overrideWith(
              (ref) async => mockShiftInfo,
            ),
            myAttendanceServicesProvider.overrideWith(
              (ref) async => mockServices,
            ),
          ],
          child: const MaterialApp(
            home: MobileAttendancePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // التحقق من ظهور بطاقة البصمة مع مواعيد الوردية
      expect(find.text('تسجيل الحضور'), findsAtLeastNWidgets(1));
      expect(find.text('الوردية: 10:00 ص · سماح حتى 10:15 ص'), findsOneWidget);

      // التحقق من بطاقة حالة اليوم ومؤشر الانضباط ضمن فترة السماح
      expect(find.text('سماح معتمد'), findsAtLeastNWidgets(1));

      // التمرير لأسفل لعرض قسم طلبات التصحيح
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      // التحقق من عنوان قسم التصحيحات وعدد الطلبات
      expect(find.text('تصحيحات وبلاغات الحضور'), findsOneWidget);
      expect(find.text('3 طلبات مسجلة'), findsOneWidget);

      // التحقق من تبويبات التصفية التفاعلية
      expect(find.text('الكل'), findsOneWidget);
      expect(find.text('قيد المراجعة'), findsAtLeastNWidgets(1));
      expect(find.text('معتمدة'), findsAtLeastNWidgets(1));
      expect(find.text('مرفوضة'), findsAtLeastNWidgets(1));

      // النقر على تبويب معتمدة
      await tester.tap(find.text('معتمدة').first);
      await tester.pumpAndSettle();

      // التحقق من ظهور رد الإدارة للطلب المعتمد
      expect(find.text('رد الإدارة: تم التحقق واعتماد التصحيح'), findsOneWidget);

      // النقر على زر طلب تصحيح
      final quickChip = find.text('نسيت حضور اليوم؟');
      expect(quickChip, findsOneWidget);
      await tester.tap(quickChip);
      await tester.pumpAndSettle();

      // التحقق من فتح نافذة طلب تصحيح حضور
      expect(find.text('طلب تصحيح حضور'), findsOneWidget);
      expect(find.text('إرسال للمراجعة'), findsOneWidget);

      // إغلاق النافذة
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
