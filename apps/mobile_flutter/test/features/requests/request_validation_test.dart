import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Request Validation Tests', () {
    group('Leave Request Validation', () {
      test('valid leave request - all fields provided', () {
        final request = LeaveRequestData(
          leaveTypeCode: 'annual',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 5),
          reason: 'إجازة سنوية',
          days: 5,
        );
        expect(validateLeaveRequest(request), isNull);
      });

      test('invalid leave request - end date before start date', () {
        final request = LeaveRequestData(
          leaveTypeCode: 'annual',
          startDate: DateTime(2026, 9, 5),
          endDate: DateTime(2026, 9, 1),
          reason: 'إجازة سنوية',
          days: 5,
        );
        expect(validateLeaveRequest(request), contains('تاريخ النهاية'));
      });

      test('invalid leave request - reason too short', () {
        final request = LeaveRequestData(
          leaveTypeCode: 'annual',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 5),
          reason: 'قص',
          days: 5,
        );
        expect(validateLeaveRequest(request), contains('السبب'));
      });

      test('invalid leave request - days is zero or negative', () {
        final request = LeaveRequestData(
          leaveTypeCode: 'annual',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 5),
          reason: 'إجازة سنوية',
          days: 0,
        );
        expect(validateLeaveRequest(request), contains('عدد الأيام'));
      });
    });

    group('Mission Request Validation', () {
      test('valid mission request', () {
        final request = MissionRequestData(
          destination: 'الرياض',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 5),
          purpose: 'اجتماع عمل مع العميل',
        );
        expect(validateMissionRequest(request), isNull);
      });

      test('invalid mission request - destination too short', () {
        final request = MissionRequestData(
          destination: 'ر',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 5),
          purpose: 'اجتماع عمل',
        );
        expect(validateMissionRequest(request), contains('الوجهة'));
      });

      test('invalid mission request - purpose too short', () {
        final request = MissionRequestData(
          destination: 'الرياض',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 5),
          purpose: 'اج',
        );
        expect(validateMissionRequest(request), contains('الغرض'));
      });
    });

    group('Attendance Correction Request Validation', () {
      test('valid attendance correction', () {
        final request = AttendanceCorrectionData(
          date: DateTime(2026, 8, 15),
          checkIn: '08:00',
          checkOut: '17:00',
          reason: 'نسيت التسجيل في النظام',
        );
        expect(validateAttendanceCorrection(request), isNull);
      });

      test('invalid attendance correction - future date', () {
        final request = AttendanceCorrectionData(
          date: DateTime(2026, 12, 31),
          checkIn: '08:00',
          checkOut: '17:00',
          reason: 'نسيت التسجيل',
        );
        expect(validateAttendanceCorrection(request), contains('التاريخ'));
      });

      test('invalid attendance correction - check-out before check-in', () {
        final request = AttendanceCorrectionData(
          date: DateTime(2026, 8, 15),
          checkIn: '17:00',
          checkOut: '08:00',
          reason: 'نسيت التسجيل',
        );
        expect(validateAttendanceCorrection(request), contains('خروج'));
      });

      test('invalid attendance correction - reason too short', () {
        final request = AttendanceCorrectionData(
          date: DateTime(2026, 8, 15),
          checkIn: '08:00',
          checkOut: '17:00',
          reason: 'نس',
        );
        expect(validateAttendanceCorrection(request), contains('السبب'));
      });
    });

    group('Request Type Detection', () {
      test('detect leave request type', () {
        expect(getRequestTypeLabel('leave'), 'طلب إجازة');
      });

      test('detect mission request type', () {
        expect(getRequestTypeLabel('mission'), 'طلب مهمة');
      });

      test('detect convoy request type', () {
        expect(getRequestTypeLabel('convoy'), 'طلب قافلة');
      });

      test('detect fundraising request type', () {
        expect(getRequestTypeLabel('fundraising'), 'طلب جمع تبرعات');
      });

      test('detect late permit type', () {
        expect(getRequestTypeLabel('late_permit'), 'طلب تصريح تأخير');
      });

      test('detect early permit type', () {
        expect(getRequestTypeLabel('early_permit'), 'طلب تصريح خروج مبكر');
      });

      test('detect attendance correction type', () {
        expect(getRequestTypeLabel('attendance_correction'), 'طلب تصحيح حضور');
      });
    });
  });
}

// Data classes للاختبار
class LeaveRequestData {
  LeaveRequestData({
    required this.leaveTypeCode,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.days,
  });

  final String leaveTypeCode;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final int days;
}

class MissionRequestData {
  MissionRequestData({
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.purpose,
  });

  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final String purpose;
}

class AttendanceCorrectionData {
  AttendanceCorrectionData({
    required this.date,
    required this.checkIn,
    required this.checkOut,
    required this.reason,
  });

  final DateTime date;
  final String checkIn;
  final String checkOut;
  final String reason;
}

// Validation functions
String? validateLeaveRequest(LeaveRequestData request) {
  if (request.reason.length < 3) {
    return 'السبب يجب أن يكون 3 أحرف على الأقل';
  }
  if (request.endDate.isBefore(request.startDate)) {
    return 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية';
  }
  if (request.days <= 0) {
    return 'عدد الأيام يجب أن يكون أكبر من صفر';
  }
  return null;
}

String? validateMissionRequest(MissionRequestData request) {
  if (request.destination.length < 2) {
    return 'الوجهة يجب أن تكون حرفين على الأقل';
  }
  if (request.purpose.length < 3) {
    return 'الغرض يجب أن يكون 3 أحرف على الأقل';
  }
  if (request.endDate.isBefore(request.startDate)) {
    return 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية';
  }
  return null;
}

String? validateAttendanceCorrection(AttendanceCorrectionData request) {
  if (request.date.isAfter(DateTime.now())) {
    return 'التاريخ يجب أن يكون في الماضي';
  }
  if (request.reason.length < 3) {
    return 'السبب يجب أن يكون 3 أحرف على الأقل';
  }
  
  // التحقق من أن وقت الخروج بعد وقت الدخول
  final checkIn = _parseTime(request.checkIn);
  final checkOut = _parseTime(request.checkOut);
  if (checkOut != null && checkIn != null && checkOut.isBefore(checkIn)) {
    return 'وقت الخروج يجب أن يكون بعد وقت الدخول';
  }
  
  return null;
}

DateTime? _parseTime(String time) {
  try {
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(2000, 1, 1, hour, minute);
  } catch (_) {
    return null;
  }
}

String getRequestTypeLabel(String type) {
  const labels = {
    'leave': 'طلب إجازة',
    'mission': 'طلب مهمة',
    'convoy': 'طلب قافلة',
    'fundraising': 'طلب جمع تبرعات',
    'late_permit': 'طلب تصريح تأخير',
    'early_permit': 'طلب تصريح خروج مبكر',
    'attendance_correction': 'طلب تصحيح حضور',
  };
  return labels[type] ?? 'طلب غير معروف';
}
