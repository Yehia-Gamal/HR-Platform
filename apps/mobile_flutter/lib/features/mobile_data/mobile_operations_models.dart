Map<String, dynamic> _map(dynamic value) =>
    Map<String, dynamic>.from(value as Map<dynamic, dynamic>);

List<T> _items<T>(dynamic value, T Function(Map<String, dynamic>) factory) =>
    (value as List<dynamic>? ?? const [])
        .map((item) => factory(_map(item)))
        .toList(growable: false);

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());

DateTime _reqDate(dynamic value) => _date(value) ?? DateTime(0);

class MobileManagerOperations {
  const MobileManagerOperations({
    required this.from,
    required this.to,
    required this.metrics,
    required this.calendar,
    required this.documentAlerts,
    required this.tasks,
    required this.missingReports,
    required this.lastUpdatedAt,
  });

  factory MobileManagerOperations.fromJson(Map<String, dynamic> json) =>
      MobileManagerOperations(
        from: _reqDate(json['from']),
        to: _reqDate(json['to']),
        metrics: ManagerOperationsMetrics.fromJson(_map(json['metrics'])),
        calendar: _items(json['calendar'], ManagerRosterEntry.fromJson),
        documentAlerts: _items(
          json['documentAlerts'],
          ManagerDocumentAlert.fromJson,
        ),
        tasks: _items(json['tasks'], ManagerTaskAlert.fromJson),
        missingReports: _items(
          json['missingReports'],
          ManagerMissingReport.fromJson,
        ),
        lastUpdatedAt: _reqDate(json['lastUpdatedAt']),
      );

  final DateTime from;
  final DateTime to;
  final ManagerOperationsMetrics metrics;
  final List<ManagerRosterEntry> calendar;
  final List<ManagerDocumentAlert> documentAlerts;
  final List<ManagerTaskAlert> tasks;
  final List<ManagerMissingReport> missingReports;
  final DateTime lastUpdatedAt;
}

class ManagerOperationsMetrics {
  const ManagerOperationsMetrics({
    required this.scheduledToday,
    required this.awayToday,
    required this.overdueTasks,
    required this.expiringDocuments,
    required this.missingReports,
  });

  factory ManagerOperationsMetrics.fromJson(Map<String, dynamic> json) =>
      ManagerOperationsMetrics(
        scheduledToday: (json['scheduledToday'] as num?)?.toInt() ?? 0,
        awayToday: (json['awayToday'] as num?)?.toInt() ?? 0,
        overdueTasks: (json['overdueTasks'] as num?)?.toInt() ?? 0,
        expiringDocuments: (json['expiringDocuments'] as num?)?.toInt() ?? 0,
        missingReports: (json['missingReports'] as num?)?.toInt() ?? 0,
      );

  final int scheduledToday;
  final int awayToday;
  final int overdueTasks;
  final int expiringDocuments;
  final int missingReports;
}

class ManagerRosterEntry {
  const ManagerRosterEntry({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.workDate,
    required this.dayStatus,
    required this.shiftName,
    required this.startsAt,
    required this.endsAt,
    required this.notes,
  });

  factory ManagerRosterEntry.fromJson(Map<String, dynamic> json) =>
      ManagerRosterEntry(
        id: json['id'] as String,
        employeeId: json['employeeId'] as String,
        employeeName: json['employeeName'] as String? ?? 'موظف',
        employeeCode: json['employeeCode'] as String?,
        workDate: _reqDate(json['workDate']),
        dayStatus: json['dayStatus'] as String? ?? 'scheduled',
        shiftName: json['shiftName'] as String?,
        startsAt: json['startsAt']?.toString(),
        endsAt: json['endsAt']?.toString(),
        notes: json['notes'] as String?,
      );

  final String id;
  final String employeeId;
  final String employeeName;
  final String? employeeCode;
  final DateTime workDate;
  final String dayStatus;
  final String? shiftName;
  final String? startsAt;
  final String? endsAt;
  final String? notes;
}

class ManagerDocumentAlert {
  const ManagerDocumentAlert({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.title,
    required this.documentType,
    required this.expiryDate,
    required this.status,
  });

  factory ManagerDocumentAlert.fromJson(Map<String, dynamic> json) =>
      ManagerDocumentAlert(
        id: json['id'] as String,
        employeeId: json['employeeId'] as String,
        employeeName: json['employeeName'] as String? ?? 'موظف',
        employeeCode: json['employeeCode'] as String?,
        title: json['title'] as String? ?? 'مستند',
        documentType: json['documentType'] as String? ?? 'other',
        expiryDate: _reqDate(json['expiryDate']),
        status: json['status'] as String? ?? 'active',
      );

  final String id;
  final String employeeId;
  final String employeeName;
  final String? employeeCode;
  final String title;
  final String documentType;
  final DateTime expiryDate;
  final String status;
}

class ManagerTaskAlert {
  const ManagerTaskAlert({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.title,
    required this.priority,
    required this.status,
    required this.dueDate,
    required this.isOverdue,
  });

  factory ManagerTaskAlert.fromJson(Map<String, dynamic> json) =>
      ManagerTaskAlert(
        id: json['id'] as String,
        employeeId: json['employeeId'] as String,
        employeeName: json['employeeName'] as String? ?? 'موظف',
        title: json['title'] as String? ?? 'مهمة',
        priority: json['priority'] as String? ?? 'medium',
        status: json['status'] as String? ?? 'pending',
        dueDate: _date(json['dueDate']),
        isOverdue: json['isOverdue'] as bool? ?? false,
      );

  final String id;
  final String employeeId;
  final String employeeName;
  final String title;
  final String priority;
  final String status;
  final DateTime? dueDate;
  final bool isOverdue;
}

class ManagerMissingReport {
  const ManagerMissingReport({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
  });

  factory ManagerMissingReport.fromJson(Map<String, dynamic> json) =>
      ManagerMissingReport(
        employeeId: json['employeeId'] as String,
        employeeName: json['employeeName'] as String? ?? 'موظف',
        employeeCode: json['employeeCode'] as String?,
      );

  final String employeeId;
  final String employeeName;
  final String? employeeCode;
}

class MobileExecutiveCommandCenter {
  const MobileExecutiveCommandCenter({
    required this.reports,
    required this.reportSchedules,
    required this.executionItems,
    required this.polls,
    required this.risks,
    required this.incidents,
    required this.meetings,
    required this.lastUpdatedAt,
  });

  factory MobileExecutiveCommandCenter.fromJson(Map<String, dynamic> json) =>
      MobileExecutiveCommandCenter(
        reports: _items(json['reports'], ExecutiveReportRun.fromJson),
        reportSchedules: _items(
          json['reportSchedules'],
          ExecutiveReportSchedule.fromJson,
        ),
        executionItems: _items(
          json['executionItems'],
          ExecutiveDecisionExecution.fromJson,
        ),
        polls: _items(json['polls'], ExecutiveDecisionPoll.fromJson),
        risks: _items(json['risks'], ExecutiveRiskItem.fromJson),
        incidents: _items(json['incidents'], ExecutiveIncidentItem.fromJson),
        meetings: _items(json['meetings'], ExecutiveMeeting.fromJson),
        lastUpdatedAt: _reqDate(json['lastUpdatedAt']),
      );

  final List<ExecutiveReportRun> reports;
  final List<ExecutiveReportSchedule> reportSchedules;
  final List<ExecutiveDecisionExecution> executionItems;
  final List<ExecutiveDecisionPoll> polls;
  final List<ExecutiveRiskItem> risks;
  final List<ExecutiveIncidentItem> incidents;
  final List<ExecutiveMeeting> meetings;
  final DateTime lastUpdatedAt;
}

class ExecutiveReportRun {
  const ExecutiveReportRun({
    required this.id,
    required this.name,
    required this.reportType,
    required this.scheduleKind,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
    required this.storagePath,
    required this.summary,
    required this.attempts,
    required this.createdAt,
    required this.completedAt,
    required this.errorDetail,
  });

  factory ExecutiveReportRun.fromJson(Map<String, dynamic> json) =>
      ExecutiveReportRun(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'تقرير',
        reportType: json['reportType'] as String? ?? 'general',
        scheduleKind: json['scheduleKind'] as String?,
        status: json['status'] as String? ?? 'queued',
        periodStart: _date(json['periodStart']),
        periodEnd: _date(json['periodEnd']),
        storagePath: json['storagePath'] as String?,
        summary: json['summary'] == null ? const {} : _map(json['summary']),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        createdAt: _reqDate(json['createdAt']),
        completedAt: _date(json['completedAt']),
        errorDetail: json['errorDetail'] as String?,
      );

  final String id;
  final String name;
  final String reportType;
  final String? scheduleKind;
  final String status;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final String? storagePath;
  final Map<String, dynamic> summary;
  final int attempts;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? errorDetail;
}

class ExecutiveReportSchedule {
  const ExecutiveReportSchedule({
    required this.id,
    required this.name,
    required this.reportType,
    required this.scheduleKind,
    required this.active,
    required this.nextRunAt,
    required this.lastRunAt,
  });

  factory ExecutiveReportSchedule.fromJson(Map<String, dynamic> json) =>
      ExecutiveReportSchedule(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'تقرير مجدول',
        reportType: json['reportType'] as String? ?? 'general',
        scheduleKind: json['scheduleKind'] as String? ?? 'manual',
        active: json['active'] as bool? ?? false,
        nextRunAt: _date(json['nextRunAt']),
        lastRunAt: _date(json['lastRunAt']),
      );

  final String id;
  final String name;
  final String reportType;
  final String scheduleKind;
  final bool active;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
}

class ExecutiveDecisionExecution {
  const ExecutiveDecisionExecution({
    required this.id,
    required this.decisionId,
    required this.decisionTitle,
    required this.title,
    required this.ownerName,
    required this.dueAt,
    required this.status,
    required this.progressPercent,
    required this.blocker,
    required this.updatedAt,
  });

  factory ExecutiveDecisionExecution.fromJson(Map<String, dynamic> json) =>
      ExecutiveDecisionExecution(
        id: json['id'] as String,
        decisionId: json['decisionId'] as String,
        decisionTitle: json['decisionTitle'] as String? ?? 'قرار إداري',
        title: json['title'] as String? ?? 'بند تنفيذ',
        ownerName: json['ownerName'] as String?,
        dueAt: _date(json['dueAt']),
        status: json['status'] as String? ?? 'not_started',
        progressPercent: (json['progressPercent'] as num?)?.toInt() ?? 0,
        blocker: json['blocker'] as String?,
        updatedAt: _date(json['updatedAt']),
      );

  final String id;
  final String decisionId;
  final String decisionTitle;
  final String title;
  final String? ownerName;
  final DateTime? dueAt;
  final String status;
  final int progressPercent;
  final String? blocker;
  final DateTime? updatedAt;
}

class ExecutivePollOption {
  const ExecutivePollOption({required this.id, required this.label});

  factory ExecutivePollOption.fromJson(Map<String, dynamic> json) =>
      ExecutivePollOption(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'خيار',
      );

  final String id;
  final String label;
}

class ExecutiveDecisionPoll {
  const ExecutiveDecisionPoll({
    required this.id,
    required this.decisionId,
    required this.decisionTitle,
    required this.question,
    required this.pollType,
    required this.status,
    required this.isAnonymous,
    required this.opensAt,
    required this.closesAt,
    required this.quorumPercent,
    required this.approvalThresholdPercent,
    required this.eligibleCount,
    required this.voteCount,
    required this.canVote,
    required this.myOptionIds,
    required this.myRating,
    required this.options,
  });

  factory ExecutiveDecisionPoll.fromJson(Map<String, dynamic> json) =>
      ExecutiveDecisionPoll(
        id: json['id'] as String,
        decisionId: json['decisionId'] as String?,
        decisionTitle: json['decisionTitle'] as String?,
        question: json['question'] as String? ?? 'تصويت',
        pollType: json['pollType'] as String? ?? 'yes_no',
        status: json['status'] as String? ?? 'open',
        isAnonymous: json['isAnonymous'] as bool? ?? false,
        opensAt: _reqDate(json['opensAt']),
        closesAt: _reqDate(json['closesAt']),
        quorumPercent: (json['quorumPercent'] as num?)?.toDouble(),
        approvalThresholdPercent: (json['approvalThresholdPercent'] as num?)
            ?.toDouble(),
        eligibleCount: (json['eligibleCount'] as num?)?.toInt() ?? 0,
        voteCount: (json['voteCount'] as num?)?.toInt() ?? 0,
        canVote: json['canVote'] as bool? ?? false,
        myOptionIds: List<String>.from(
          json['myOptionIds'] as List<dynamic>? ?? const [],
        ),
        myRating: (json['myRating'] as num?)?.toDouble(),
        options: _items(json['options'], ExecutivePollOption.fromJson),
      );

  final String id;
  final String? decisionId;
  final String? decisionTitle;
  final String question;
  final String pollType;
  final String status;
  final bool isAnonymous;
  final DateTime opensAt;
  final DateTime closesAt;
  final double? quorumPercent;
  final double? approvalThresholdPercent;
  final int eligibleCount;
  final int voteCount;
  final bool canVote;
  final List<String> myOptionIds;
  final double? myRating;
  final List<ExecutivePollOption> options;

  double get participationPercent =>
      eligibleCount == 0 ? 0 : (voteCount / eligibleCount) * 100;
  bool get hasVoted => myOptionIds.isNotEmpty || myRating != null;
}

class ExecutiveRiskItem {
  const ExecutiveRiskItem({
    required this.id,
    required this.title,
    required this.description,
    required this.likelihood,
    required this.impact,
    required this.severity,
    required this.status,
    required this.ownerName,
    required this.updatedAt,
    required this.createdAt,
  });

  factory ExecutiveRiskItem.fromJson(Map<String, dynamic> json) =>
      ExecutiveRiskItem(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'مخاطرة',
        description: json['description'] as String?,
        likelihood: json['likelihood'] as String? ?? 'medium',
        impact: json['impact'] as String? ?? 'medium',
        severity: json['severity'] as String? ?? 'medium',
        status: json['status'] as String? ?? 'open',
        ownerName: json['ownerName'] as String?,
        updatedAt: _date(json['updatedAt']),
        createdAt: _reqDate(json['createdAt']),
      );

  final String id;
  final String title;
  final String? description;
  final String likelihood;
  final String impact;
  final String severity;
  final String status;
  final String? ownerName;
  final DateTime? updatedAt;
  final DateTime createdAt;
}

class ExecutiveIncidentItem {
  const ExecutiveIncidentItem({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.status,
    required this.reporterName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExecutiveIncidentItem.fromJson(Map<String, dynamic> json) =>
      ExecutiveIncidentItem(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'حادث',
        description: json['description'] as String?,
        severity: json['severity'] as String? ?? 'medium',
        status: json['status'] as String? ?? 'open',
        reporterName: json['reporterName'] as String?,
        createdAt: _reqDate(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
      );

  final String id;
  final String title;
  final String? description;
  final String severity;
  final String status;
  final String? reporterName;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

class ExecutiveMeeting {
  const ExecutiveMeeting({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.locationOrLink,
    required this.organizerName,
    required this.status,
  });

  factory ExecutiveMeeting.fromJson(Map<String, dynamic> json) =>
      ExecutiveMeeting(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'اجتماع',
        scheduledAt: _date(json['scheduledAt']),
        locationOrLink: json['locationOrLink'] as String?,
        organizerName: json['organizerName'] as String?,
        status: json['status'] as String? ?? 'scheduled',
      );

  final String id;
  final String title;
  final DateTime? scheduledAt;
  final String? locationOrLink;
  final String? organizerName;
  final String status;
}
