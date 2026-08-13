import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manager operations parse roster, alerts and daily report gaps', () {
    final value = MobileManagerOperations.fromJson({
      'from': '2026-07-13',
      'to': '2026-07-27',
      'metrics': {
        'scheduledToday': 8,
        'awayToday': 2,
        'overdueTasks': 1,
        'expiringDocuments': 3,
        'missingReports': 2,
      },
      'calendar': [
        {
          'id': 'roster-1',
          'employeeId': 'employee-1',
          'employeeName': 'أحمد محمود',
          'employeeCode': 'E-101',
          'workDate': '2026-07-13',
          'dayStatus': 'scheduled',
          'shiftName': 'صباحية',
          'startsAt': '09:00:00',
          'endsAt': '17:00:00',
          'notes': null,
        },
      ],
      'documentAlerts': [
        {
          'id': 'document-1',
          'employeeId': 'employee-1',
          'employeeName': 'أحمد محمود',
          'employeeCode': 'E-101',
          'title': 'بطاقة الهوية',
          'documentType': 'id',
          'expiryDate': '2026-07-20',
          'status': 'active',
        },
      ],
      'tasks': [
        {
          'id': 'task-1',
          'employeeId': 'employee-1',
          'employeeName': 'أحمد محمود',
          'title': 'تسليم خطة الوردية',
          'priority': 'high',
          'status': 'pending',
          'dueDate': '2026-07-12',
          'isOverdue': true,
        },
      ],
      'missingReports': [
        {
          'employeeId': 'employee-1',
          'employeeName': 'أحمد محمود',
          'employeeCode': 'E-101',
        },
      ],
      'lastUpdatedAt': '2026-07-13T10:00:00Z',
    });

    expect(value.metrics.scheduledToday, 8);
    expect(value.calendar.single.shiftName, 'صباحية');
    expect(value.documentAlerts.single.documentType, 'id');
    expect(value.tasks.single.isOverdue, isTrue);
    expect(value.missingReports.single.employeeCode, 'E-101');
  });

  test('executive command center parses reports, votes and risk records', () {
    final value = MobileExecutiveCommandCenter.fromJson({
      'reports': [
        {
          'id': 'report-1',
          'name': 'التقرير الأسبوعي',
          'reportType': 'executive_weekly',
          'scheduleKind': 'weekly',
          'status': 'completed',
          'periodStart': '2026-07-06',
          'periodEnd': '2026-07-12',
          'storagePath': 'reports/report-1.pdf',
          'summary': {'employees': 45},
          'attempts': 1,
          'createdAt': '2026-07-13T06:00:00Z',
          'completedAt': '2026-07-13T06:04:00Z',
          'errorDetail': null,
        },
      ],
      'reportSchedules': [],
      'executionItems': [],
      'polls': [
        {
          'id': 'poll-1',
          'decisionId': 'decision-1',
          'decisionTitle': 'خطة التوسع',
          'question': 'هل تعتمد الخطة؟',
          'pollType': 'yes_no',
          'status': 'open',
          'isAnonymous': false,
          'opensAt': '2026-07-13T08:00:00Z',
          'closesAt': '2026-07-14T08:00:00Z',
          'quorumPercent': 60,
          'approvalThresholdPercent': 50,
          'eligibleCount': 10,
          'voteCount': 7,
          'canVote': true,
          'myOptionIds': [],
          'myRating': null,
          'options': [
            {'id': 'yes', 'label': 'نعم'},
            {'id': 'no', 'label': 'لا'},
          ],
        },
      ],
      'risks': [
        {
          'id': 'risk-1',
          'title': 'تأخر التوريد',
          'description': null,
          'likelihood': 'high',
          'impact': 'high',
          'severity': 'critical',
          'status': 'mitigating',
          'ownerName': 'مدير التشغيل',
          'updatedAt': null,
          'createdAt': '2026-07-12T10:00:00Z',
        },
      ],
      'incidents': [],
      'meetings': [],
      'lastUpdatedAt': '2026-07-13T10:00:00Z',
    });

    expect(value.reports.single.summary['employees'], 45);
    expect(value.polls.single.participationPercent, 70);
    expect(value.polls.single.canVote, isTrue);
    expect(value.polls.single.options, hasLength(2));
    expect(value.risks.single.severity, 'critical');
  });

  test('operations center parses summary, tasks, missions and convoys', () {
    final value = MobileOperationsCenter.fromJson({
      'summary': {
        'openTasks': 3,
        'urgentTasks': 1,
        'missions': 2,
        'convoys': 1,
      },
      'tasks': [
        {
          'id': 'task-1',
          'title': 'تجهيز التقارير',
          'description': 'تفاصيل',
          'assigneeId': 'employee-1',
          'assigneeName': 'محمد',
          'priority': 'urgent',
          'dueDate': '2026-07-20',
          'status': 'in_progress',
        },
        {
          'id': 'task-2',
          'title': 'مهمة منتهية',
          'priority': 'medium',
          'status': 'done',
        },
      ],
      'missions': [
        {
          'id': 'mission-1',
          'employeeName': 'أحمد',
          'destination': 'القاهرة',
          'purpose': 'تسليم مستندات',
          'startAt': '2026-07-20T08:00:00Z',
          'endAt': '2026-07-20T14:00:00Z',
          'status': 'approved',
          'transportMode': 'company_vehicle',
        },
      ],
      'convoys': [
        {
          'id': 'convoy-1',
          'employeeName': 'خالد',
          'name': 'قافلة الشحن',
          'origin': 'المنصورة',
          'destination': 'القاهرة',
          'departureAt': '2026-07-21T06:00:00Z',
          'returnAt': '2026-07-21T18:00:00Z',
          'passengers': 4,
          'vehicles': 2,
          'status': 'pending',
        },
      ],
      'lastUpdatedAt': '2026-07-13T10:00:00Z',
    });

    expect(value.summary.openTasks, 3);
    expect(value.summary.urgentTasks, 1);
    expect(value.summary.missions, 2);
    expect(value.summary.convoys, 1);
    expect(value.tasks, hasLength(2));
    expect(value.tasks.first.priority, 'urgent');
    expect(value.tasks.first.isOpen, isTrue);
    expect(value.tasks.last.isOpen, isFalse);
    expect(value.tasks.first.dueDate, DateTime(2026, 7, 20));
    expect(value.missions.single.destination, 'القاهرة');
    expect(value.missions.single.status, 'approved');
    expect(value.convoys.single.passengers, 4);
    expect(value.convoys.single.vehicles, 2);
    expect(value.convoys.single.name, 'قافلة الشحن');
  });
}
