Map<String, dynamic> _map(dynamic value) =>
    Map<String, dynamic>.from(value as Map<dynamic, dynamic>);

List<T> _items<T>(dynamic value, T Function(Map<String, dynamic>) factory) =>
    (value as List<dynamic>? ?? const [])
        .map((item) => factory(_map(item)))
        .toList(growable: false);

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());

DateTime _reqDate(dynamic value) => _date(value) ?? DateTime(0);

class MobileExecutiveBrief {
  const MobileExecutiveBrief({
    required this.period,
    required this.briefDate,
    required this.attendance,
    required this.decisions,
    required this.risk,
    required this.highlights,
    required this.dailyReport,
    required this.generatedAt,
    required this.sourceLabel,
  });

  factory MobileExecutiveBrief.fromJson(Map<String, dynamic> json) =>
      MobileExecutiveBrief(
        period: json['period'] as String? ?? 'morning',
        briefDate: _reqDate(json['briefDate']),
        attendance: ExecutiveBriefAttendance.fromJson(_map(json['attendance'])),
        decisions: ExecutiveBriefDecisions.fromJson(_map(json['decisions'])),
        risk: ExecutiveBriefRisk.fromJson(_map(json['risk'])),
        highlights: _items(
          json['highlights'],
          ExecutiveBriefHighlight.fromJson,
        ),
        dailyReport: _map(json['dailyReport'] ?? <String, dynamic>{}),
        generatedAt: _reqDate(json['generatedAt']),
        sourceLabel: json['sourceLabel'] as String? ?? 'مصادر تشغيلية مباشرة',
      );

  final String period;
  final DateTime briefDate;
  final ExecutiveBriefAttendance attendance;
  final ExecutiveBriefDecisions decisions;
  final ExecutiveBriefRisk risk;
  final List<ExecutiveBriefHighlight> highlights;
  final Map<String, dynamic> dailyReport;
  final DateTime generatedAt;
  final String sourceLabel;
}

class ExecutiveBriefAttendance {
  const ExecutiveBriefAttendance({
    required this.presentToday,
    required this.presentYesterday,
    required this.lateToday,
    required this.lateYesterday,
    required this.absentToday,
    required this.onLeaveToday,
    required this.weekAverageLate,
  });

  factory ExecutiveBriefAttendance.fromJson(Map<String, dynamic> json) =>
      ExecutiveBriefAttendance(
        presentToday: (json['presentToday'] as num?)?.toInt() ?? 0,
        presentYesterday: (json['presentYesterday'] as num?)?.toInt() ?? 0,
        lateToday: (json['lateToday'] as num?)?.toInt() ?? 0,
        lateYesterday: (json['lateYesterday'] as num?)?.toInt() ?? 0,
        absentToday: (json['absentToday'] as num?)?.toInt() ?? 0,
        onLeaveToday: (json['onLeaveToday'] as num?)?.toInt() ?? 0,
        weekAverageLate: (json['weekAverageLate'] as num?)?.toDouble() ?? 0,
      );

  final int presentToday;
  final int presentYesterday;
  final int lateToday;
  final int lateYesterday;
  final int absentToday;
  final int onLeaveToday;
  final double weekAverageLate;
}

class ExecutiveBriefDecisions {
  const ExecutiveBriefDecisions({
    required this.urgentActions,
    required this.pendingApprovals,
    required this.pendingFinalKpi,
    required this.decisionsInReview,
    required this.publishedToday,
    required this.reportsReadyToday,
  });

  factory ExecutiveBriefDecisions.fromJson(Map<String, dynamic> json) =>
      ExecutiveBriefDecisions(
        urgentActions: (json['urgentActions'] as num?)?.toInt() ?? 0,
        pendingApprovals: (json['pendingApprovals'] as num?)?.toInt() ?? 0,
        pendingFinalKpi: (json['pendingFinalKpi'] as num?)?.toInt() ?? 0,
        decisionsInReview: (json['decisionsInReview'] as num?)?.toInt() ?? 0,
        publishedToday: (json['publishedToday'] as num?)?.toInt() ?? 0,
        reportsReadyToday: (json['reportsReadyToday'] as num?)?.toInt() ?? 0,
      );

  final int urgentActions;
  final int pendingApprovals;
  final int pendingFinalKpi;
  final int decisionsInReview;
  final int publishedToday;
  final int reportsReadyToday;
}

class ExecutiveBriefRisk {
  const ExecutiveBriefRisk({
    required this.criticalRisks,
    required this.highRisks,
    required this.activeIncidents,
    required this.criticalIncidents,
  });

  factory ExecutiveBriefRisk.fromJson(Map<String, dynamic> json) =>
      ExecutiveBriefRisk(
        criticalRisks: (json['criticalRisks'] as num?)?.toInt() ?? 0,
        highRisks: (json['highRisks'] as num?)?.toInt() ?? 0,
        activeIncidents: (json['activeIncidents'] as num?)?.toInt() ?? 0,
        criticalIncidents: (json['criticalIncidents'] as num?)?.toInt() ?? 0,
      );

  final int criticalRisks;
  final int highRisks;
  final int activeIncidents;
  final int criticalIncidents;
}

class ExecutiveBriefHighlight {
  const ExecutiveBriefHighlight({
    required this.kind,
    required this.title,
    required this.value,
    required this.severity,
    required this.detail,
  });

  factory ExecutiveBriefHighlight.fromJson(Map<String, dynamic> json) =>
      ExecutiveBriefHighlight(
        kind: json['kind'] as String? ?? 'general',
        title: json['title'] as String? ?? '',
        value: (json['value'] as num?)?.toInt() ?? 0,
        severity: json['severity'] as String? ?? 'normal',
        detail: json['detail'] as String? ?? '',
      );

  final String kind;
  final String title;
  final int value;
  final String severity;
  final String detail;
}

class ExecutivePersonItem {
  const ExecutivePersonItem({
    required this.id,
    required this.employeeCode,
    required this.name,
    required this.photoUrl,
    required this.jobTitle,
    required this.department,
    required this.team,
    required this.attendanceStatus,
    required this.pendingRequests,
    required this.openTasks,
    required this.latestKpiScore,
  });

  factory ExecutivePersonItem.fromJson(Map<String, dynamic> json) =>
      ExecutivePersonItem(
        id: json['id'] as String,
        employeeCode: json['employeeCode'] as String? ?? '',
        name: json['name'] as String? ?? 'موظف',
        photoUrl: json['photoUrl'] as String?,
        jobTitle: json['jobTitle'] as String?,
        department: json['department'] as String?,
        team: json['team'] as String?,
        attendanceStatus: json['attendanceStatus'] as String?,
        pendingRequests: (json['pendingRequests'] as num?)?.toInt() ?? 0,
        openTasks: (json['openTasks'] as num?)?.toInt() ?? 0,
        latestKpiScore: (json['latestKpiScore'] as num?)?.toDouble(),
      );

  final String id;
  final String employeeCode;
  final String name;
  final String? photoUrl;
  final String? jobTitle;
  final String? department;
  final String? team;
  final String? attendanceStatus;
  final int pendingRequests;
  final int openTasks;
  final double? latestKpiScore;
}

class ExecutiveEmployeeSummary {
  const ExecutiveEmployeeSummary({
    required this.id,
    required this.employeeCode,
    required this.name,
    required this.photoUrl,
    required this.status,
    required this.jobTitle,
    required this.position,
    required this.department,
    required this.team,
    required this.branch,
    required this.workSite,
    required this.managerName,
    required this.hireDate,
    required this.pendingRequests,
    required this.openTasks,
    required this.expiringDocuments,
    required this.latestKpi,
    required this.recentAttendance,
    required this.lastUpdatedAt,
  });

  factory ExecutiveEmployeeSummary.fromJson(Map<String, dynamic> json) =>
      ExecutiveEmployeeSummary(
        id: json['id'] as String,
        employeeCode: json['employeeCode'] as String? ?? '',
        name: json['name'] as String? ?? 'موظف',
        photoUrl: json['photoUrl'] as String?,
        status: json['status'] as String? ?? 'active',
        jobTitle: json['jobTitle'] as String?,
        position: json['position'] as String?,
        department: json['department'] as String?,
        team: json['team'] as String?,
        branch: json['branch'] as String?,
        workSite: json['workSite'] as String?,
        managerName: json['managerName'] as String?,
        hireDate: _date(json['hireDate']),
        pendingRequests: (json['pendingRequests'] as num?)?.toInt() ?? 0,
        openTasks: (json['openTasks'] as num?)?.toInt() ?? 0,
        expiringDocuments: (json['expiringDocuments'] as num?)?.toInt() ?? 0,
        latestKpi: json['latestKpi'] == null
            ? null
            : ExecutiveEmployeeKpi.fromJson(_map(json['latestKpi'])),
        recentAttendance: _items(
          json['recentAttendance'],
          ExecutiveEmployeeAttendance.fromJson,
        ),
        lastUpdatedAt: _reqDate(json['lastUpdatedAt']),
      );

  final String id;
  final String employeeCode;
  final String name;
  final String? photoUrl;
  final String status;
  final String? jobTitle;
  final String? position;
  final String? department;
  final String? team;
  final String? branch;
  final String? workSite;
  final String? managerName;
  final DateTime? hireDate;
  final int pendingRequests;
  final int openTasks;
  final int expiringDocuments;
  final ExecutiveEmployeeKpi? latestKpi;
  final List<ExecutiveEmployeeAttendance> recentAttendance;
  final DateTime lastUpdatedAt;
}

class ExecutiveEmployeeKpi {
  const ExecutiveEmployeeKpi({
    required this.score,
    required this.rating,
    required this.stage,
    required this.periodMonth,
  });

  factory ExecutiveEmployeeKpi.fromJson(Map<String, dynamic> json) =>
      ExecutiveEmployeeKpi(
        score: (json['score'] as num?)?.toDouble(),
        rating: json['rating'] as String?,
        stage: json['stage'] as String? ?? 'self',
        periodMonth: _date(json['periodMonth']),
      );

  final double? score;
  final String? rating;
  final String stage;
  final DateTime? periodMonth;
}

class ExecutiveEmployeeAttendance {
  const ExecutiveEmployeeAttendance({
    required this.workDate,
    required this.status,
    required this.lateMinutes,
    required this.workMinutes,
    required this.firstCheckIn,
    required this.lastCheckOut,
  });

  factory ExecutiveEmployeeAttendance.fromJson(Map<String, dynamic> json) =>
      ExecutiveEmployeeAttendance(
        workDate: _reqDate(json['workDate']),
        status: json['status'] as String? ?? 'pending',
        lateMinutes: (json['lateMinutes'] as num?)?.toInt() ?? 0,
        workMinutes: (json['workMinutes'] as num?)?.toInt() ?? 0,
        firstCheckIn: _date(json['firstCheckIn']),
        lastCheckOut: _date(json['lastCheckOut']),
      );

  final DateTime workDate;
  final String status;
  final int lateMinutes;
  final int workMinutes;
  final DateTime? firstCheckIn;
  final DateTime? lastCheckOut;
}
