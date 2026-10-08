import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'action target keeps complete UUID after prefixed action id is resolved by server',
    () {
      final target = MobileActionTarget.fromJson({
        'kind': 'request',
        'recordId': '123e4567-e89b-12d3-a456-426614174000',
        'mobileRoute': 'request_detail',
      });
      expect(target.recordId, '123e4567-e89b-12d3-a456-426614174000');
      expect(target.mobileRoute, 'request_detail');
    },
  );

  test('KPI form parses stage scores', () {
    final form = KpiEvaluationForm.fromJson({
      'id': 'evaluation',
      'employeeId': 'employee',
      'employeeName': 'موظف تجريبي',
      'periodMonth': '2026-07-01',
      'currentStage': 'manager_review',
      'editableStage': 'manager_review',
      'workflowStatus': 'MANAGER_REVIEW',
      'locked': false,
      'criteria': [
        {
          'id': 'criterion',
          'name': 'الالتزام',
          'code': 'CONDUCT',
          'weight': 50,
          'maxScore': 100,
          'sortOrder': 1,
          'stageScores': {
            'self': {'score': 80, 'note': 'ملاحظة'},
          },
          'editable': true,
        },
      ],
      'attendance': {
        'lateCount': 1,
        'earlyLeaveCount': 0,
        'unexcusedAbsenceCount': 0,
        'shortagePenalty': 1,
        'missingPunchCount': 0,
        'score': 18,
        'hasPendingItems': false,
      },
    });
    expect(form.criteria.single.stageScores['self']?.score, 80);
    expect(form.editableStage, 'manager_review');
    expect(form.attendance?.score, 18);
  });

  test('mobile profile parses documents and assets', () {
    final profile = MobileProfile.fromJson({
      'id': 'employee',
      'employeeCode': 'EMP-001',
      'fullNameAr': 'موظف تجريبي',
      'status': 'active',
      'documents': [
        {'id': 'doc', 'type': 'contract', 'title': 'العقد', 'status': 'active'},
      ],
      'assets': [
        {'id': 'asset', 'assetName': 'هاتف', 'assetType': 'phone'},
      ],
    });
    expect(profile.documents.single.title, 'العقد');
    expect(profile.assets.single.assetName, 'هاتف');
  });

  test('team member parses attendance and workflow summary', () {
    final member = MobileTeamMember.fromJson({
      'id': 'employee',
      'name': 'أحمد',
      'attendanceStatus': 'late',
      'lateMinutes': 12,
      'pendingRequests': 2,
      'kpiStage': 'manager_review',
    });
    expect(member.lateMinutes, 12);
    expect(member.pendingRequests, 2);
    expect(member.kpiStage, 'manager_review');
  });

  test('request detail exposes cancel capability from server', () {
    final request = MobileRequestDetail.fromJson({
      'id': 'request',
      'requestNumber': 17,
      'requestType': 'leave',
      'employeeName': 'أحمد',
      'status': 'pending',
      'workflowStatus': 'in_review',
      'payload': {
        'leaveType': 'annual',
        'startDate': '2026-07-20',
        'endDate': '2026-07-22',
        'days': 3,
      },
      'createdAt': '2026-07-13T08:00:00Z',
      'canDecide': false,
      'canCancel': true,
      'steps': [
        {
          'id': 'step',
          'order': 1,
          'name': 'اعتماد المدير',
          'status': 'approved',
          'actorName': 'مسؤول Operations',
        },
      ],
      'attachments': [
        {'path': 'user/request.jpg', 'mimeType': 'image/jpeg', 'sizeBytes': 2048},
      ],
      'decisionContext': {
        'substitute': {'id': 'substitute', 'name': 'الموظف البديل'},
        'hasConflict': true,
        'conflicts': [
          {'type': 'substitute_overlap', 'message': 'البديل لديه طلب متداخل'},
        ],
      },
      'decisionActorName': 'مسؤول Operations',
      'decisionMode': 'OPERATIONS_ON_BEHALF_OF_EXECUTIVE_DIRECTOR',
      'decisionOnBehalfOfExecutive': true,
    });
    expect(request.canCancel, isTrue);
    expect(request.payload['days'], 3);
    expect(request.attachments.single.path, 'user/request.jpg');
    expect(request.substituteName, 'الموظف البديل');
    expect(request.conflicts.single, 'البديل لديه طلب متداخل');
    expect(request.steps.single.actorName, 'مسؤول Operations');
    expect(request.decisionOnBehalfOfExecutive, isTrue);
  });

  test('daily report keeps manager review timestamp', () {
    final report = MobileDailyReport.fromJson({
      'id': 'report',
      'employeeId': 'employee',
      'employeeName': 'أحمد',
      'reportDate': '2026-07-13',
      'achievements': 'إنجاز المهام',
      'managerComment': 'عمل جيد',
      'reviewerName': 'المدير',
      'reviewedAt': '2026-07-13T12:00:00Z',
      'createdAt': '2026-07-13T09:00:00Z',
    });
    expect(report.managerComment, 'عمل جيد');
    expect(report.reviewedAt, isNotNull);
  });

  test('mobile task identifies onboarding source', () {
    final task = MobileTask.fromJson({
      'id': 'task',
      'sourceType': 'onboarding',
      'title': 'توقيع السياسات',
      'priority': 'high',
      'status': 'pending',
      'createdAt': '2026-07-13T09:00:00Z',
      'isOverdue': false,
    });
    expect(task.sourceType, 'onboarding');
    expect(task.title, 'توقيع السياسات');
  });

  test('work assignment parses fundraising with financial target', () {
    final asg = MobileWorkAssignment.fromJson({
      'id': 'asg-1',
      'assignment_number': 7,
      'assignment_type': 'FUNDRAISING',
      'title': 'حملة فاندي رمضان',
      'status': 'APPROVED',
      'start_at': '2026-08-03T07:00:00Z',
      'end_at': '2026-08-03T19:00:00Z',
      'is_full_day': true,
      'location': 'نقطة التجمع',
      'needs_report': true,
      'target_amount': 50000,
    });
    expect(asg.assignmentType, 'FUNDRAISING');
    expect(asg.typeLabel, 'فاندي ترفيهي');
    expect(asg.targetAmount, 50000);
  });

  test('work assignment marks an hourly mission', () {
    final asg = MobileWorkAssignment.fromJson({
      'id': 'asg-2',
      'assignment_number': 8,
      'assignment_type': 'MISSION',
      'title': 'مأمورية بالساعات',
      'status': 'APPROVED',
      'start_at': '2026-08-01T08:00:00Z',
      'end_at': '2026-08-01T12:00:00Z',
      'is_full_day': false,
    });
    expect(asg.typeLabel, 'مأمورية');
    expect(asg.isFullDay, isFalse);
    expect(asg.targetAmount, isNull);
  });

  test('monthly attendance statement parses days and summary (V12 §18)', () {
    final stmt = MonthlyAttendanceStatement.fromJson({
      'employee': {'fullNameAr': 'موظف تجريبي'},
      'period': {'year': 2026, 'month': 7},
      'days': [
        {
          'date': '2026-07-01',
          'dayNameAr': 'الأربعاء',
          'checkIn': '08:05:00',
          'checkOut': '16:00:00',
          'shiftName': 'صباحي',
          'workHours': 7.5,
          'lateMinutes': 5,
          'status': 'متأخر',
          'missingCheckOut': false,
        },
        {
          'date': '2026-07-07',
          'dayNameAr': 'الثلاثاء',
          'status': 'قافلة',
          'hasConvoyFundi': true,
        },
      ],
      'summary': {
        'presentDays': 1,
        'scheduledDays': 2,
        'dueScheduledDays': 2,
        'upcomingDays': 0,
        'openShiftDays': 0,
        'completedPresenceDays': 1,
        'missionDays': 1,
        'totalWorkHours': 7.5,
        'totalRequiredHours': 8,
        'totalLateMinutes': 5,
        'attendanceRate': 50,
        'attendanceRateBasis': {
          'presentInDue': 1,
          'dueDays': 2,
          'presentDays': 1,
          'absentDays': 1,
          'openShiftDays': 0,
          'upcomingDays': 0,
        },
        'hoursComplianceRate': 93.75,
        'hoursComplianceAvailable': true,
      },
    });
    expect(stmt.employeeNameAr, 'موظف تجريبي');
    expect(stmt.days.length, 2);
    expect(stmt.days.first.lateMinutes, 5);
    expect(stmt.days[1].hasConvoyFundi, isTrue);
    expect(stmt.summary.totalWorkHours, 7.5);
    expect(stmt.summary.missionDays, 1);
    expect(stmt.attendancePercentage, 50);
    expect(stmt.summary.attendanceRatePresentDays, 1);
    expect(stmt.summary.hoursComplianceAvailable, isTrue);
  });

  MobileLocationRequest req(String mode) => MobileLocationRequest.fromJson({
    'id': '33333333-3333-4333-8333-333333333333',
    'requesterName': 'المدير التنفيذي',
    'reason': 'متابعة إدارية',
    'status': 'pending',
    'mode': mode,
    'durationMinutes': 2,
    'requestedAt': '2026-07-15T08:00:00Z',
  });

  // V12 §9: الفيديو ملغى نهائيًا — needsVideo دائمًا false.
  test('location_video mode requires a point but video is disabled (V12)', () {
    final r = req('location_video');
    expect(r.needsVideo, isFalse); // V12: الفيديو ملغى
    expect(r.needsPoint, isTrue);
    expect(r.isTracking, isFalse);
  });

  test('video_5s: video disabled in V12, no point either', () {
    final r = req('video_5s');
    expect(r.needsVideo, isFalse); // V12: الفيديو ملغى
    expect(r.needsPoint, isFalse);
  });

  test('snapshot needs a point but no video', () {
    final r = req('snapshot');
    expect(r.needsVideo, isFalse);
    expect(r.needsPoint, isTrue);
  });

  test('track_ modes are tracking sessions, not point/video', () {
    final r = req('track_10');
    expect(r.isTracking, isTrue);
    expect(r.needsVideo, isFalse);
    expect(r.needsPoint, isFalse);
  });

  test('employee summary parses enriched employee row', () {
    final employee = MobileEmployeeSummary.fromJson({
      'id': 'employee-1',
      'employeeCode': 'E-101',
      'fullNameAr': 'محمد أحمد',
      'fullNameEn': 'Mohamed Ahmed',
      'status': 'active',
      'isActive': true,
      'photoUrl': 'https://example.com/p.png',
      'department': 'التشغيل',
      'team': 'فريق الشحن',
      'branch': 'المنصورة',
      'jobTitle': 'مشرف لوجستي',
    });

    expect(employee.id, 'employee-1');
    expect(employee.fullNameAr, 'محمد أحمد');
    expect(employee.status, 'active');
    expect(employee.isActive, isTrue);
    expect(employee.department, 'التشغيل');
    expect(employee.team, 'فريق الشحن');
    expect(employee.jobTitle, 'مشرف لوجستي');
  });

  test('instant penalty row from PostgREST parses (escalation_level is text)', () {
    // صف حقيقي الشكل من instant_attendance_penalties عبر select=*
    final p = MobileInstantPenalty.fromJson({
      'id': '0b1c2d3e-0000-4000-8000-000000000001',
      'employee_id': '0b1c2d3e-0000-4000-8000-000000000002',
      'work_date': '2026-10-03',
      'late_minutes': 27,
      'original_amount': 20,
      'current_amount': 20.0,
      'currency': 'EGP',
      'status': 'pending_payment',
      'escalation_level': 'initial',
      'paid_at': null,
      'suspended_at': null,
      'created_at': '2026-10-03T07:30:00.318079+00:00',
      'notes': 'تأخير حضور فعلي (27 دقيقة)',
      'excuse_status': 'none',
    });
    expect(p.escalationLevel, 'initial');
    expect(p.lateMinutes, 27);
    expect(p.currentAmount, 20.0);
    expect(p.status, 'pending_payment');

    final doubled = MobileInstantPenalty.fromJson({
      'id': 'x',
      'work_date': '2026-10-02',
      'late_minutes': 120,
      'original_amount': 150,
      'current_amount': 500,
      'status': 'doubled',
      'escalation_level': 'doubled',
      'created_at': '2026-10-02T08:00:00+00:00',
    });
    expect(doubled.escalationLevel, 'doubled');
    expect(doubled.currentAmount, 500.0);
  });

  test('instant penalty handles String numeric amounts and non-string reference number safely', () {
    final p = MobileInstantPenalty.fromJson({
      'id': 'uuid-123',
      'work_date': '2026-10-03',
      'late_minutes': '45',
      'original_amount': '150.00',
      'current_amount': '150.50',
      'receipt_reference_number': 987654,
      'created_at': '2026-10-03 07:40:00+00',
    });
    expect(p.lateMinutes, 45);
    expect(p.originalAmount, 150.0);
    expect(p.currentAmount, 150.5);
    expect(p.receiptReferenceNumber, '987654');
    expect(p.escalationLevel, 'initial');
    expect(p.status, 'pending_payment');
  });

  test('Employee360 parses todayStatus correctly and handles null safely', () {
    final withToday = Employee360.fromJson({
      'id': 'emp-uuid',
      'employeeCode': 'EMP-01',
      'fullNameAr': 'محمد أحمد',
      'status': 'active',
      'todayStatus': {
        'status': 'present',
        'lateMinutes': 15,
        'checkInAt': '2026-10-03T08:15:00Z',
        'checkOutAt': '2026-10-03T16:00:00Z',
        'workMinutes': 465,
      },
      'attendance30': {
        'present': 20,
        'lateDays': 2,
        'absent': 1,
        'workMinutes': 9000,
      },
      'requestCounts': {
        'pending': 1,
        'approved': 5,
        'rejected': 0,
      },
    });

    expect(withToday.todayStatus, isNotNull);
    expect(withToday.todayStatus!.status, 'present');
    expect(withToday.todayStatus!.lateMinutes, 15);
    expect(withToday.todayStatus!.workMinutes, 465);
    expect(withToday.todayStatus!.checkInAt, isNotNull);
    expect(withToday.todayStatus!.checkOutAt, isNotNull);

    final withoutToday = Employee360.fromJson({
      'id': 'emp-uuid-2',
      'employeeCode': 'EMP-02',
      'fullNameAr': 'علي حسن',
      'status': 'active',
    });

    expect(withoutToday.todayStatus, isNull);
  });

  test('Employee360 and DirectoryEmployee parse convoy, mission, fundraising with label and activity', () {
    final emp360Convoy = Employee360.fromJson({
      'id': 'emp-convoy',
      'employeeCode': 'EMP-CV',
      'fullNameAr': 'سعيد محمد',
      'status': 'active',
      'todayStatus': {
        'status': 'convoy',
        'statusLabel': 'في قافلة',
        'activityTitle': 'سوهاج - طما',
      },
    });

    expect(emp360Convoy.todayStatus, isNotNull);
    expect(emp360Convoy.todayStatus!.status, 'convoy');
    expect(emp360Convoy.todayStatus!.statusLabel, 'في قافلة');
    expect(emp360Convoy.todayStatus!.activityTitle, 'سوهاج - طما');

    final dirEmp = DirectoryEmployee.fromJson({
      'id': 'dir-1',
      'name': 'خالد إبراهيم',
      'statusToday': 'fundraising',
      'statusTodayLabel': 'في فاندي',
      'activityTitle': 'الريف الأوروبي',
    });

    expect(dirEmp.statusToday, 'fundraising');
    expect(dirEmp.statusTodayLabel, 'في فاندي');
    expect(dirEmp.activityTitle, 'الريف الأوروبي');
  });

  test('MobileWorkShiftInfo parses current shift, available shifts, and pending request', () {
    final info = MobileWorkShiftInfo.fromJson({
      'currentShift': {
        'id': 'shift-official',
        'code': 'OFFICIAL',
        'name': 'الدوام الأساسي (10 ص – 6 م)',
        'startTime': '10:00:00',
        'endTime': '18:00:00',
        'graceInMinutes': 15,
        'isAssigned': true,
        'assignmentId': 'assign-1',
        'effectiveFrom': '2026-10-01',
        'status': 'approved',
      },
      'availableShifts': [
        {
          'id': 'shift-9-5',
          'code': 'SHIFT_9_5',
          'name': 'الوردية الصباحية (9 ص – 5 م)',
          'startTime': '09:00:00',
          'endTime': '17:00:00',
          'graceInMinutes': 15,
          'isDefault': false,
          'description': 'فترة صباحية',
        },
        {
          'id': 'shift-official',
          'code': 'OFFICIAL',
          'name': 'الدوام الأساسي (10 ص – 6 م)',
          'startTime': '10:00:00',
          'endTime': '18:00:00',
          'graceInMinutes': 15,
          'isDefault': true,
        },
      ],
      'pendingRequest': {
        'requestId': 'req-1',
        'title': 'طلب تغيير فترة العمل',
        'reason': 'مواعيد المواصلات',
        'requestedShiftId': 'shift-9-5',
        'requestedShiftName': 'الوردية الصباحية (9 ص – 5 م)',
        'createdAt': '2026-10-04T12:00:00Z',
        'status': 'pending',
      },
    });

    expect(info.currentShift.isAssigned, isTrue);
    expect(info.currentShift.badgeLabel, 'معتمدة من الإدارة');
    expect(info.currentShift.formattedRange, contains('10'));
    expect(info.availableShifts.length, 2);
    expect(info.availableShifts.first.code, 'SHIFT_9_5');
    expect(info.pendingRequest, isNotNull);
    expect(info.pendingRequest!.status, 'pending');
    expect(info.pendingRequest!.requestedShiftName, 'الوردية الصباحية (9 ص – 5 م)');
  });
}
