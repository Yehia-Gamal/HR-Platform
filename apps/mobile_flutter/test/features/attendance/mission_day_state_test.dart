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
