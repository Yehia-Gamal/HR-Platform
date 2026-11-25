import 'package:ahla_shabab_management_os/features/mobile_data/models/json_parse.dart';

class EmployeeHomeSummary {
  const EmployeeHomeSummary({
    required this.pendingRequests,
    required this.activeTasks,
    required this.kpiStage,
    required this.unreadNotifications,
    required this.unreadOfficial,
    required this.pendingLocationRequests,
  });
  factory EmployeeHomeSummary.fromJson(Map<String, dynamic> json) =>
      EmployeeHomeSummary(
        pendingRequests: asInt(json['pendingRequests'], 0),
        activeTasks: asInt(json['activeTasks'], 0),
        kpiStage: asNullableString(json['kpiStage']),
        unreadNotifications:
            asInt(json['unreadNotifications'], 0),
        unreadOfficial: asInt(json['unreadOfficial'], 0),
        pendingLocationRequests:
            asInt(json['pendingLocationRequests'], 0),
      );
  final int pendingRequests;
  final int activeTasks;
  final String? kpiStage;
  final int unreadNotifications;
  final int unreadOfficial;
  final int pendingLocationRequests;
}

class ManagerDashboardSummary {
  const ManagerDashboardSummary({
    required this.teamMembers,
    required this.pendingRequests,
    required this.pendingKpi,
    required this.lateToday,
  });
  factory ManagerDashboardSummary.fromJson(Map<String, dynamic> json) =>
      ManagerDashboardSummary(
        teamMembers: asInt(json['teamMembers'], 0),
        pendingRequests: asInt(json['pendingRequests'], 0),
        pendingKpi: asInt(json['pendingKpi'], 0),
        lateToday: asInt(json['lateToday'], 0),
      );
  final int teamMembers;
  final int pendingRequests;
  final int pendingKpi;
  final int lateToday;
}

class ExecutiveDashboardSummary {
  const ExecutiveDashboardSummary({
    required this.urgentActions,
    required this.pendingApprovals,
    required this.pendingFinalKpi,
    required this.publishedDecisions,
    required this.openCases,
    required this.activeLocationRequests,
    required this.attendancePresent,
    required this.attendanceRequired,
    this.attendanceLate = 0,
    this.attendanceAbsent = 0,
    this.attendanceNotYet = 0,
    this.onLeave = 0,
    this.fieldWork = 0,
    this.activeEmployees = 0,
  });
  factory ExecutiveDashboardSummary.fromJson(Map<String, dynamic> json) {
    // استخراج بيانات الحضور من dailyReport (get_v10_executive_daily_report — 0597)
    int n(Map<String, dynamic> m, String k) => asInt(m[k], 0);
    final report = asMap(json['dailyReport']);
    final att = asMap(report['attendance']);
    final emp = asMap(report['employees']);
    final work = asMap(report['workStatus']);
    return ExecutiveDashboardSummary(
      attendanceLate: n(att, 'late'),
      attendanceAbsent: n(att, 'absent'),
      attendanceNotYet: n(att, 'notYet'),
      onLeave: n(work, 'approvedLeave'),
      fieldWork: n(work, 'missions') + n(work, 'convoys') + n(work, 'fundraising'),
      activeEmployees: n(emp, 'active'),
      urgentActions: asInt(json['urgentActions'], 0),
      pendingApprovals: asInt(json['pendingApprovals'], 0),
      pendingFinalKpi: asInt(json['pendingFinalKpi'], 0),
      publishedDecisions: asInt(json['publishedDecisions'], 0),
      openCases: asInt(json['openCases'], 0),
      activeLocationRequests:
          asInt(json['activeLocationRequests'], 0),
      attendancePresent: asInt(att['present'], 0),
      attendanceRequired: asInt(emp['requiredToday'], 0),
    );
  }
  final int urgentActions;
  final int pendingApprovals;
  final int pendingFinalKpi;
  final int publishedDecisions;
  final int openCases;
  final int activeLocationRequests;

  /// عدد الحاضرين اليوم (من dailyReport.attendance.present)
  final int attendancePresent;

  /// العدد المطلوب اليوم (من dailyReport.employees.requiredToday)
  final int attendanceRequired;

  /// متأخرون (ضمن الحاضرين)، وغائبون بعد موعد الحضور، ومن لم يحن موعدهم بعد.
  final int attendanceLate;
  final int attendanceAbsent;
  final int attendanceNotYet;

  /// في إجازة معتمدة، وفي عمل ميداني (مأمورية/قافلة/فاندي) — خارج المطلوب حضورهم.
  final int onLeave;
  final int fieldWork;

  /// الموظفون الخاضعون للحضور (بلا المعفين من البصمة).
  final int activeEmployees;

  /// نسبة الحضور من المطلوب حضورهم (0-100) — نفس رقم لوحة الموارد البشرية.
  int get attendanceRate => attendanceRequired > 0
      ? (attendancePresent * 100 / attendanceRequired).round().clamp(0, 100)
      : 0;
}
