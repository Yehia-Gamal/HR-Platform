import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('json_parse helpers', () {
    test('handle null, empty, and mismatched primitive types safely', () {
      expect(asString(null, 'fallback'), 'fallback');
      expect(asString(123), '123');
      expect(asNullableString(null), isNull);
      expect(asNullableString(42), '42');

      expect(asInt(null, 5), 5);
      expect(asInt('42'), 42);
      expect(asInt('42.9'), 42);
      expect(asInt('bad', 7), 7);
      expect(asNullableInt(null), isNull);
      expect(asNullableInt('15'), 15);
      expect(asNullableInt('abc'), isNull);

      expect(asDouble(null, 1.5), 1.5);
      expect(asDouble('12.25'), 12.25);
      expect(asDouble('bad', 2.0), 2.0);
      expect(asNullableDouble('bad'), isNull);

      expect(asBool(null, true), isTrue);
      expect(asBool(1), isTrue);
      expect(asBool('true'), isTrue);
      expect(asBool('0'), isFalse);
      expect(asNullableBool(null), isNull);

      expect(reqDate(null), DateTime(0));
      expect(reqDate('not-a-date'), DateTime(0));
      expect(optDate(null), isNull);
      expect(optDate('null'), isNull);
      expect(optDate('not-a-date'), isNull);

      expect(asMap('{"a": 1}')['a'], 1);
      expect(asMap('not-json'), isEmpty);
      expect(asNullableMap('invalid'), isNull);
      expect(asList('not-a-list'), isEmpty);
      expect(asMapList(['bad', {'id': '1'}]).single['id'], '1');
      expect(asStringList([1, null, 'ok']), ['1', 'ok']);
    });
  });

  group('Domain models survive empty, null, and mismatched-type payloads', () {
    final corruptPayload = <String, dynamic>{
      'id': 999,
      'name': 123,
      'title': 456,
      'status': null,
      'createdAt': 'not-a-date',
      'updatedAt': 12345,
      'lateMinutes': '25',
      'attendanceRate': '91.5',
      'canPunch': 'true',
      'reactionSummary': {'like': '4'},
      'dailyReport': 'invalid-map',
      'currentShift': null,
      'days': 'not-a-list',
      'attendance': null,
      'missionExecution': null,
      'decisionContext': 'invalid',
      'employee': 'invalid',
      'attendance30': null,
      'requestCounts': null,
    };

    test('dashboard summary models parse empty and corrupt maps', () {
      expect(EmployeeHomeSummary.fromJson(const {}).pendingRequests, 0);
      expect(EmployeeHomeSummary.fromJson(corruptPayload).kpiStage, isNull);
      expect(ManagerDashboardSummary.fromJson(const {}).teamMembers, 0);
      expect(ExecutiveDashboardSummary.fromJson(corruptPayload).activeEmployees, 0);
    });

    test('attendance models parse empty and corrupt maps', () {
      final state = AttendanceState.fromJson(corruptPayload);
      expect(state.canPunch, isTrue);
      expect(state.lastEventAt, isNull);

      expect(PasskeyDevice.fromJson(corruptPayload).id, '999');
      expect(AttendanceHistoryItem.fromJson(corruptPayload).eventAt, DateTime(0));
      expect(
        MonthlyAttendanceStatement.fromJson(corruptPayload).days,
        isEmpty,
      );
      expect(CurrentWorkShift.fromJson(corruptPayload).startTime, '10:00:00');
      expect(MobileWorkShiftInfo.fromJson(corruptPayload).availableShifts, isEmpty);

      final penalty = MobileInstantPenalty.fromJson(corruptPayload);
      expect(penalty.id, '999');
      expect(penalty.lateMinutes, 25);
    });

    test('request, kpi, location, people, and portal models parse safely', () {
      expect(MobileRequest.fromJson(corruptPayload).id, '999');
      expect(MobileRequestDetail.fromJson(corruptPayload).conflicts, isEmpty);
      expect(KpiCriterionForm.fromJson(corruptPayload).weight, 0);
      expect(KpiEvaluationForm.fromJson(corruptPayload).criteria, isEmpty);
      expect(
        ExecutiveEmployeeLocationDossier.fromJson(corruptPayload).points,
        isEmpty,
      );
      expect(MobileProfile.fromJson(corruptPayload).id, '999');
      expect(Employee360.fromJson(corruptPayload).documents, isEmpty);
      expect(MobileFeedItem.fromJson(corruptPayload).reactionSummary['like'], 4);
      expect(MobileNotificationItem.fromJson(corruptPayload).id, '999');
      expect(MobilePayslip.fromJson(corruptPayload).lines, isEmpty);
    });
  });
}
