import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('0450: MissionToday parsing', () {
    test('يوزّع يوم مأمورية قيد التنفيذ بكل الحقول', () {
      final state = AttendanceState.fromJson({
        'attendanceRequired': true,
        'selfPunchEnabled': true,
        'canPunch': false,
        'suggestedAction': 'MISSION_IN_PROGRESS',
        'missionToday': {
          'requestId': '11111111-1111-1111-1111-111111111111',
          'type': 'convoy',
          'execStatus': 'in_progress',
          'startTime': '09:30',
          'startedAt': '2026-08-22T07:00:00Z',
          'endedAt': null,
          'autoCheckout': false,
        },
      });

      final mission = state.missionToday;
      expect(mission, isNotNull);
      expect(mission!.requestId, '11111111-1111-1111-1111-111111111111');
      expect(mission.type, 'convoy');
      expect(mission.execStatus, 'in_progress');
      expect(mission.startTime, '09:30');
      expect(mission.startedAt, DateTime.parse('2026-08-22T07:00:00Z'));
      expect(mission.endedAt, isNull);
      expect(mission.autoCheckout, isFalse);
    });

    test('يوزّع انتهاءً تلقائياً بعد نهاية الدوام', () {
      final state = AttendanceState.fromJson({
        'suggestedAction': 'DAY_COMPLETED',
        'todayCheckOutAt': '2026-08-22T16:10:00Z',
        'missionToday': {
          'requestId': '22222222-2222-2222-2222-222222222222',
          'type': 'mission',
          'execStatus': 'completed',
          'autoCheckout': true,
        },
      });

      final mission = state.missionToday!;
      expect(mission.execStatus, 'completed');
      expect(mission.autoCheckout, isTrue);
      // اكتمال اليوم ⇒ todayCheckOutAt مضبوط من الخادم.
      expect(state.todayCheckOutAt, isNotNull);
    });

    test('0607: يوزّع مأمورية معلقة pending مع إمكانية البدء', () {
      final state = AttendanceState.fromJson({
        'attendanceRequired': true,
        'selfPunchEnabled': true,
        'canPunch': false,
        'suggestedAction': 'MISSION_START',
        'missionToday': {
          'requestId': '33333333-3333-3333-3333-333333333333',
          'type': 'mission',
          'execStatus': 'pending',
          'startTime': '10:00',
          'startedAt': null,
          'endedAt': null,
          'autoCheckout': false,
        },
      });

      final mission = state.missionToday!;
      expect(mission.execStatus, 'pending');
      expect(mission.startedAt, isNull);
      expect(state.suggestedAction, 'MISSION_START');
    });

    test('0607: إنهاء المأمورية دون بصمة انصراف يقترح CHECK_OUT لاستكمال الدوام', () {
      final state = AttendanceState.fromJson({
        'attendanceRequired': true,
        'selfPunchEnabled': true,
        'canPunch': true,
        'suggestedAction': 'CHECK_OUT',
        'todayCheckInAt': '2026-08-22T08:00:00Z',
        'todayCheckOutAt': null,
        'missionToday': {
          'requestId': '44444444-4444-4444-4444-444444444444',
          'type': 'mission',
          'execStatus': 'completed',
          'startedAt': '2026-08-22T08:00:00Z',
          'endedAt': '2026-08-22T13:00:00Z',
          'autoCheckout': false,
        },
      });

      final mission = state.missionToday!;
      expect(mission.execStatus, 'completed');
      expect(mission.autoCheckout, isFalse);
      expect(state.todayCheckInAt, isNotNull);
      expect(state.todayCheckOutAt, isNull);
      expect(state.suggestedAction, 'CHECK_OUT');
    });

    test('غياب المأمورية ⇒ null والقيم الافتراضية كما في 0439', () {
      final state = AttendanceState.fromJson({
        'attendanceRequired': true,
        'selfPunchEnabled': true,
        'canPunch': true,
        'suggestedAction': 'CHECK_IN',
      });
      expect(state.missionToday, isNull);
      expect(state.suggestedAction, 'CHECK_IN');
    });
  });
}
