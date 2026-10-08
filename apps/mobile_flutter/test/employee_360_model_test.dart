import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _base() => {
  'id': '11111111-1111-1111-1111-111111111111',
  'employeeCode': 'E1',
  'fullNameAr': 'موظف',
  'status': 'active',
};

void main() {
  group('Employee360 (0631)', () {
    test('يقرأ مديره المباشر وفريقه ونطاق العرض وموعد الحضور', () {
      final e = Employee360.fromJson({
        ..._base(),
        'managerId': 'm1',
        'manager': {'id': 'm1', 'fullNameAr': 'المدير', 'jobTitle': 'مدير تنفيذي'},
        'teamMembers': [
          {
            'id': 't1',
            'fullNameAr': 'عضو',
            'jobTitle': 'مصمم',
            'status': 'mission',
            'statusLabel': 'في مأمورية',
            'activityTitle': 'سوهاج',
          },
        ],
        'directReports': 1,
        'viewerScope': 'basic',
        'todayStatus': {'status': 'present', 'statusLabel': 'حاضر في الجمعية', 'dueTime': '10:15'},
      });

      expect(e.managerId, 'm1');
      expect(e.manager?.fullNameAr, 'المدير');
      expect(e.manager?.jobTitle, 'مدير تنفيذي');
      expect(e.teamMembers, hasLength(1));
      expect(e.teamMembers.single.status, 'mission');
      expect(e.teamMembers.single.activityTitle, 'سوهاج');
      expect(e.viewerScope, 'basic');
      expect(e.todayStatus?.dueTime, '10:15');
    });

    test('خادم أقدم بلا حقول 0631 يبقى صالحًا بقيم افتراضية', () {
      final e = Employee360.fromJson({
        ..._base(),
        'managerName': 'المدير',
        'directReports': 2,
      });

      expect(e.manager, isNull);
      expect(e.teamMembers, isEmpty);
      expect(e.viewerScope, isNull);
      expect(e.managerName, 'المدير');
      expect(e.directReports, 2);
      expect(e.attendance30.offsiteDays, isNull);
    });

    test('ملف أساسي لزميل: حقول التفاصيل فارغة دون أخطاء', () {
      final e = Employee360.fromJson({
        ..._base(),
        'viewerScope': 'basic',
        'phoneE164': null,
        'hireDate': null,
        'contractEnd': null,
        'probationEnd': null,
        'grade': null,
        'accountStatus': null,
        'todayStatus': {'status': 'present', 'statusLabel': 'حاضر في الجمعية', 'activityTitle': null},
      });

      expect(e.email, isNull);
      expect(e.hireDate, isNull);
      expect(e.recentRequests, isEmpty);
      expect(e.requestCounts.pending, 0);
      expect(e.todayStatus?.checkInAt, isNull);
      expect(e.todayStatus?.lateMinutes, 0);
    });
  });
}
