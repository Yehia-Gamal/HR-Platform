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
      'currentStage': 'manager',
      'editableStage': 'manager',
      'workflowStatus': 'MANAGER_EVALUATION_IN_PROGRESS',
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
    expect(form.editableStage, 'manager');
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
      'kpiStage': 'manager',
    });
    expect(member.lateMinutes, 12);
    expect(member.pendingRequests, 2);
    expect(member.kpiStage, 'manager');
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
      'steps': [],
    });
    expect(request.canCancel, isTrue);
    expect(request.payload['days'], 3);
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
    expect(asg.typeLabel, 'فاندي');
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

  MobileLocationRequest req(String mode) => MobileLocationRequest.fromJson({
    'id': '33333333-3333-4333-8333-333333333333',
    'requesterName': 'المدير التنفيذي',
    'reason': 'متابعة إدارية',
    'status': 'pending',
    'mode': mode,
    'durationMinutes': 2,
    'requestedAt': '2026-07-15T08:00:00Z',
  });

  test('location_video mode requires both a point and a video', () {
    final r = req('location_video');
    expect(r.needsVideo, isTrue);
    expect(r.needsPoint, isTrue);
    expect(r.isTracking, isFalse);
  });

  test('video_5s needs video but not a separate point', () {
    final r = req('video_5s');
    expect(r.needsVideo, isTrue);
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
}
