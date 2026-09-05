import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonthlyAttendanceStatement Resilient Deserialization', () {
    test('handles null and dynamic-typed elements in days list without crashing', () {
      final dynamic rawJson = {
        'employee': <dynamic, dynamic>{
          'fullNameAr': 'يحيى جمال السبع',
          'employeeCode': '+201154869616',
          'jobTitle': 'السكرتير التنفيذي',
        },
        'period': <dynamic, dynamic>{
          'year': 2026,
          'month': 8,
          'startDate': '2026-08-01',
          'endDate': '2026-08-31',
        },
        'days': <dynamic>[
          <dynamic, dynamic>{
            'date': '2026-08-01',
            'dayNameAr': 'السبت',
            'status': 'حاضر',
            'checkIn': '07:15',
            'checkOut': '18:39',
            'workHours': 11.4,
            'requiredHours': 8,
            'isCompleted': true,
            'isDue': true,
          },
          null, // This was the exact bug from unapplied migration in PostgreSQL
          <dynamic, dynamic>{
            'date': '2026-08-02',
            'dayNameAr': 'الأحد',
            'status': 'فاندي',
            'workHours': 0,
            'requiredHours': 8,
            'hasConvoyFundi': true,
          },
        ],
        'summary': <dynamic, dynamic>{
          'totalDays': 31,
          'scheduledDays': 27,
          'presentDays': 21,
          'absentDays': 2,
          'attendanceRate': 77.78,
          'attendanceRateBasis': <dynamic, dynamic>{
            'presentInDue': 21,
            'dueDays': 27,
          },
          'hoursRateBasis': <dynamic, dynamic>{
            'workedMinutes': 10175,
            'requiredMinutes': 12960,
          },
        },
      };

      final statement = MonthlyAttendanceStatement.fromJson(
        Map<String, dynamic>.from(rawJson as Map),
      );

      expect(statement.employeeNameAr, 'يحيى جمال السبع');
      expect(statement.year, 2026);
      expect(statement.month, 8);
      // The null day is filtered out cleanly
      expect(statement.days.length, 2);
      expect(statement.days[0].date, '2026-08-01');
      expect(statement.days[1].date, '2026-08-02');
      expect(statement.days[1].status, 'فاندي');
      expect(statement.summary.attendanceRate, 77.78);
      expect(statement.summary.attendanceRatePresentDays, 21);
      expect(statement.summary.attendanceRateDueDays, 27);
      expect(statement.summary.hoursRateWorkedMinutes, 10175);
    });

    test('AttendanceStatementSummary parses null bases gracefully', () {
      final summary = AttendanceStatementSummary.fromJson({
        'totalDays': 30,
        'scheduledDays': 22,
        'presentDays': 20,
        'totalWorkHours': 160.0,
        'totalRequiredHours': 160.0,
      });

      expect(summary.totalDays, 30);
      expect(summary.presentDays, 20);
      expect(summary.attendanceRatePresentDays, 20);
      expect(summary.attendanceRateDueDays, 22);
      expect(summary.hoursRateWorkedMinutes, 9600);
      expect(summary.hoursRateRequiredMinutes, 9600);
    });
  });
}
