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
        pendingRequests: (json['pendingRequests'] as num?)?.toInt() ?? 0,
        activeTasks: (json['activeTasks'] as num?)?.toInt() ?? 0,
        kpiStage: json['kpiStage'] as String?,
        unreadNotifications:
            (json['unreadNotifications'] as num?)?.toInt() ?? 0,
        unreadOfficial: (json['unreadOfficial'] as num?)?.toInt() ?? 0,
        pendingLocationRequests:
            (json['pendingLocationRequests'] as num?)?.toInt() ?? 0,
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
        teamMembers: (json['teamMembers'] as num?)?.toInt() ?? 0,
        pendingRequests: (json['pendingRequests'] as num?)?.toInt() ?? 0,
        pendingKpi: (json['pendingKpi'] as num?)?.toInt() ?? 0,
        lateToday: (json['lateToday'] as num?)?.toInt() ?? 0,
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
  });
  factory ExecutiveDashboardSummary.fromJson(Map<String, dynamic> json) =>
      ExecutiveDashboardSummary(
        urgentActions: (json['urgentActions'] as num?)?.toInt() ?? 0,
        pendingApprovals: (json['pendingApprovals'] as num?)?.toInt() ?? 0,
        pendingFinalKpi: (json['pendingFinalKpi'] as num?)?.toInt() ?? 0,
        publishedDecisions: (json['publishedDecisions'] as num?)?.toInt() ?? 0,
        openCases: (json['openCases'] as num?)?.toInt() ?? 0,
        activeLocationRequests:
            (json['activeLocationRequests'] as num?)?.toInt() ?? 0,
      );
  final int urgentActions;
  final int pendingApprovals;
  final int pendingFinalKpi;
  final int publishedDecisions;
  final int openCases;
  final int activeLocationRequests;
}

class MobileRequest {
  const MobileRequest({
    required this.id,
    required this.number,
    required this.type,
    required this.employeeName,
    required this.title,
    required this.reason,
    required this.status,
    required this.workflowStatus,
    required this.activeStepName,
    required this.createdAt,
  });
  factory MobileRequest.fromJson(Map<String, dynamic> json) => MobileRequest(
    id: json['id'] as String,
    number: (json['requestNumber'] as num).toInt(),
    type: json['requestType'] as String,
    employeeName: json['employeeName'] as String? ?? 'موظف',
    title: json['title'] as String?,
    reason: json['reason'] as String?,
    status: json['status'] as String? ?? 'pending',
    workflowStatus: json['workflowStatus'] as String? ?? 'submitted',
    activeStepName: json['activeStepName'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
  final String id;
  final int number;
  final String type;
  final String employeeName;
  final String? title;
  final String? reason;
  final String status;
  final String workflowStatus;
  final String? activeStepName;
  final DateTime createdAt;
}

class MobileKpiEvaluation {
  const MobileKpiEvaluation({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.periodMonth,
    required this.currentStage,
    required this.workflowStatus,
    required this.deadlineAt,
    required this.finalScore,
    required this.finalRating,
  });
  factory MobileKpiEvaluation.fromJson(Map<String, dynamic> json) =>
      MobileKpiEvaluation(
        id: json['id'] as String,
        employeeId: json['employeeId'] as String,
        employeeName: json['employeeName'] as String? ?? 'موظف',
        employeeCode: json['employeeCode'] as String?,
        periodMonth: DateTime.parse(json['periodMonth'] as String),
        currentStage: json['currentStage'] as String? ?? 'self',
        workflowStatus: json['workflowStatus'] as String? ?? 'NOT_STARTED',
        deadlineAt: json['deadlineAt'] == null
            ? null
            : DateTime.parse(json['deadlineAt'] as String),
        finalScore: (json['finalScore'] as num?)?.toDouble(),
        finalRating: json['finalRating'] as String?,
      );
  final String id;
  final String employeeId;
  final String employeeName;
  final String? employeeCode;
  final DateTime periodMonth;
  final String currentStage;
  final String workflowStatus;
  final DateTime? deadlineAt;
  final double? finalScore;
  final String? finalRating;
}

class KpiStageScore {
  const KpiStageScore({required this.score, required this.note});
  factory KpiStageScore.fromJson(Map<String, dynamic> json) => KpiStageScore(
    score: (json['score'] as num?)?.toDouble(),
    note: json['note'] as String?,
  );
  final double? score;
  final String? note;
}

class KpiCriterionForm {
  const KpiCriterionForm({
    required this.id,
    required this.code,
    required this.name,
    required this.weight,
    required this.maxScore,
    required this.sortOrder,
    required this.stageScores,
    required this.description,
    required this.sourceType,
    required this.evaluatorStage,
    required this.calculationMethod,
    required this.editable,
    required this.effectiveScore,
  });
  factory KpiCriterionForm.fromJson(Map<String, dynamic> json) {
    final rawScores = Map<String, dynamic>.from(
      json['stageScores'] as Map<dynamic, dynamic>? ?? const {},
    );
    return KpiCriterionForm(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? 'معيار',
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
      maxScore: (json['maxScore'] as num?)?.toDouble() ?? 100,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      stageScores: rawScores.map(
        (key, value) => MapEntry(
          key,
          KpiStageScore.fromJson(
            Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
          ),
        ),
      ),
      description: json['description'] as String?,
      sourceType: json['sourceType'] as String? ?? 'manual',
      evaluatorStage: json['evaluatorStage'] as String?,
      calculationMethod: json['calculationMethod'] as String? ?? 'manual',
      editable: json['editable'] as bool? ?? false,
      effectiveScore: (json['effectiveScore'] as num?)?.toDouble(),
    );
  }
  final String id;
  final String code;
  final String name;
  final double weight;
  final double maxScore;
  final int sortOrder;
  final Map<String, KpiStageScore> stageScores;
  final String? description;
  final String sourceType;
  final String? evaluatorStage;
  final String calculationMethod;
  final bool editable;
  final double? effectiveScore;
}

class KpiGoalForm {
  const KpiGoalForm({
    required this.id,
    required this.title,
    required this.targetValue,
    required this.achievedValue,
    required this.unit,
    required this.weight,
    required this.status,
    required this.calculatedScore,
    required this.evidenceSource,
    required this.employeeNote,
  });
  factory KpiGoalForm.fromJson(Map<String, dynamic> json) => KpiGoalForm(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'هدف',
    targetValue: (json['targetValue'] as num?)?.toDouble() ?? 0,
    achievedValue: (json['achievedValue'] as num?)?.toDouble() ?? 0,
    unit: json['unit'] as String? ?? '',
    weight: (json['weight'] as num?)?.toDouble() ?? 0,
    status: json['status'] as String? ?? 'NOT_STARTED',
    calculatedScore: (json['calculatedScore'] as num?)?.toDouble() ?? 0,
    evidenceSource: json['evidenceSource'] as String?,
    employeeNote: json['employeeNote'] as String?,
  );
  final String id;
  final String title;
  final double targetValue;
  final double achievedValue;
  final String unit;
  final double weight;
  final String status;
  final double calculatedScore;
  final String? evidenceSource;
  final String? employeeNote;
}

class KpiComplianceForm {
  const KpiComplianceForm({
    required this.metric,
    required this.requiredCount,
    required this.actualCount,
    required this.exemptCount,
    required this.cancelledCount,
    required this.score,
    required this.note,
  });
  factory KpiComplianceForm.fromJson(Map<String, dynamic> json) =>
      KpiComplianceForm(
        metric: json['metric'] as String,
        requiredCount: (json['requiredCount'] as num?)?.toInt() ?? 0,
        actualCount: (json['actualCount'] as num?)?.toInt() ?? 0,
        exemptCount: (json['exemptCount'] as num?)?.toInt() ?? 0,
        cancelledCount: (json['cancelledCount'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble() ?? 0,
        note: json['note'] as String?,
      );
  final String metric;
  final int requiredCount;
  final int actualCount;
  final int exemptCount;
  final int cancelledCount;
  final double score;
  final String? note;
}

class KpiAttendanceSummary {
  const KpiAttendanceSummary({
    required this.lateCount,
    required this.earlyLeaveCount,
    required this.unexcusedAbsenceCount,
    required this.shortagePenalty,
    required this.missingPunchCount,
    required this.score,
    required this.hasPendingItems,
  });
  factory KpiAttendanceSummary.fromJson(Map<String, dynamic> json) =>
      KpiAttendanceSummary(
        lateCount: (json['lateCount'] as num?)?.toInt() ?? 0,
        earlyLeaveCount: (json['earlyLeaveCount'] as num?)?.toInt() ?? 0,
        unexcusedAbsenceCount:
            (json['unexcusedAbsenceCount'] as num?)?.toInt() ?? 0,
        shortagePenalty: (json['shortagePenalty'] as num?)?.toDouble() ?? 0,
        missingPunchCount: (json['missingPunchCount'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble() ?? 0,
        hasPendingItems: json['hasPendingItems'] as bool? ?? false,
      );
  final int lateCount;
  final int earlyLeaveCount;
  final int unexcusedAbsenceCount;
  final double shortagePenalty;
  final int missingPunchCount;
  final double score;
  final bool hasPendingItems;
}

class KpiEvaluationForm {
  const KpiEvaluationForm({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.periodMonth,
    required this.currentStage,
    required this.workflowStatus,
    required this.editableStage,
    required this.locked,
    required this.finalScore,
    required this.finalRating,
    required this.criteria,
    required this.goals,
    required this.compliance,
    required this.attendance,
    required this.validationErrors,
  });
  factory KpiEvaluationForm.fromJson(Map<String, dynamic> json) =>
      KpiEvaluationForm(
        id: json['id'] as String,
        employeeId: json['employeeId'] as String,
        employeeName: json['employeeName'] as String? ?? 'موظف',
        employeeCode: json['employeeCode'] as String?,
        periodMonth: DateTime.parse(json['periodMonth'] as String),
        currentStage: json['currentStage'] as String? ?? 'self',
        workflowStatus: json['workflowStatus'] as String? ?? 'NOT_STARTED',
        editableStage: json['editableStage'] as String?,
        locked: json['locked'] as bool? ?? false,
        finalScore: (json['finalScore'] as num?)?.toDouble(),
        finalRating: json['finalRating'] as String?,
        criteria: (json['criteria'] as List<dynamic>? ?? const [])
            .map(
              (item) => KpiCriterionForm.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        goals: (json['goals'] as List<dynamic>? ?? const [])
            .map(
              (item) => KpiGoalForm.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        compliance: (json['compliance'] as List<dynamic>? ?? const [])
            .map(
              (item) => KpiComplianceForm.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        attendance: json['attendance'] == null
            ? null
            : KpiAttendanceSummary.fromJson(
                Map<String, dynamic>.from(
                  json['attendance'] as Map<dynamic, dynamic>,
                ),
              ),
        validationErrors:
            (json['validationErrors'] as List<dynamic>? ?? const [])
                .map((item) => item.toString())
                .toList(growable: false),
      );
  final String id;
  final String employeeId;
  final String employeeName;
  final String? employeeCode;
  final DateTime periodMonth;
  final String currentStage;
  final String workflowStatus;
  final String? editableStage;
  final bool locked;
  final double? finalScore;
  final String? finalRating;
  final List<KpiCriterionForm> criteria;
  final List<KpiGoalForm> goals;
  final List<KpiComplianceForm> compliance;
  final KpiAttendanceSummary? attendance;
  final List<String> validationErrors;
}

class AttendanceState {
  const AttendanceState({
    required this.attendanceRequired,
    required this.selfPunchEnabled,
    required this.activeLocalDevices,
    required this.hasActiveLocalDevice,
    required this.canPunch,
    required this.suggestedAction,
    required this.lastEventType,
    required this.lastEventAt,
    required this.lastEventStatus,
    required this.todayStatus,
  });
  factory AttendanceState.fromJson(Map<String, dynamic> json) =>
      AttendanceState(
        attendanceRequired: json['attendanceRequired'] as bool? ?? false,
        selfPunchEnabled: json['selfPunchEnabled'] as bool? ?? false,
        activeLocalDevices: (json['activeLocalDevices'] as num?)?.toInt() ??
            (json['activePasskeys'] as num?)?.toInt() ??
            0,
        hasActiveLocalDevice: json['hasActiveLocalDevice'] as bool? ??
            json['hasActivePasskey'] as bool? ??
            false,
        canPunch: json['canPunch'] as bool? ?? false,
        suggestedAction: json['suggestedAction'] as String? ?? 'CHECK_IN',
        lastEventType: json['lastEventType'] as String?,
        lastEventAt: json['lastEventAt'] == null
            ? null
            : DateTime.parse(json['lastEventAt'] as String),
        lastEventStatus: json['lastEventStatus'] as String?,
        todayStatus: json['todayStatus'] as String?,
      );
  final bool attendanceRequired;
  final bool selfPunchEnabled;
  final int activeLocalDevices;
  final bool hasActiveLocalDevice;
  final bool canPunch;
  final String suggestedAction;
  final String? lastEventType;
  final DateTime? lastEventAt;
  final String? lastEventStatus;
  final String? todayStatus;
}

class MobileFeedItem {
  const MobileFeedItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.priority,
    required this.requiresAcknowledgement,
    required this.myAcknowledged,
    required this.publishedAt,
  });
  factory MobileFeedItem.fromJson(Map<String, dynamic> json) => MobileFeedItem(
    id: json['id'] as String,
    kind: json['kind'] as String? ?? 'announcement',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    priority: json['priority'] as String? ?? 'normal',
    requiresAcknowledgement: json['requiresAcknowledgement'] as bool? ?? false,
    myAcknowledged: json['myAcknowledged'] as bool? ?? false,
    publishedAt: json['publishedAt'] == null
        ? null
        : DateTime.parse(json['publishedAt'] as String),
  );
  final String id;
  final String kind;
  final String title;
  final String body;
  final String priority;
  final bool requiresAcknowledgement;
  final bool myAcknowledged;
  final DateTime? publishedAt;
}

class MobileActionItem {
  const MobileActionItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.priority,
    required this.status,
    required this.dueAt,
  });
  factory MobileActionItem.fromJson(Map<String, dynamic> json) =>
      MobileActionItem(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? 'task',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String?,
        priority: json['priority'] as String? ?? 'normal',
        status: json['status'] as String? ?? '',
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String),
      );
  final String id;
  final String kind;
  final String title;
  final String? subtitle;
  final String priority;
  final String status;
  final DateTime? dueAt;
}

class LocationDirectoryEmployee {
  const LocationDirectoryEmployee({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.jobTitle,
    required this.department,
    required this.lastLatitude,
    required this.lastLongitude,
    required this.lastAccuracy,
    required this.lastRecordedAt,
    required this.activeRequestId,
    required this.activeRequestStatus,
  });
  factory LocationDirectoryEmployee.fromJson(Map<String, dynamic> json) =>
      LocationDirectoryEmployee(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'موظف',
        employeeCode: json['employeeCode'] as String?,
        jobTitle: json['jobTitle'] as String?,
        department: json['department'] as String?,
        lastLatitude: (json['lastLatitude'] as num?)?.toDouble(),
        lastLongitude: (json['lastLongitude'] as num?)?.toDouble(),
        lastAccuracy: (json['lastAccuracy'] as num?)?.toDouble(),
        lastRecordedAt: json['lastRecordedAt'] == null
            ? null
            : DateTime.parse(json['lastRecordedAt'] as String),
        activeRequestId: json['activeRequestId'] as String?,
        activeRequestStatus: json['activeRequestStatus'] as String?,
      );
  final String id;
  final String name;
  final String? employeeCode;
  final String? jobTitle;
  final String? department;
  final double? lastLatitude;
  final double? lastLongitude;
  final double? lastAccuracy;
  final DateTime? lastRecordedAt;
  final String? activeRequestId;
  final String? activeRequestStatus;
}

class MobileLocationRequest {
  const MobileLocationRequest({
    required this.id,
    required this.requesterName,
    required this.reason,
    required this.status,
    required this.mode,
    required this.durationMinutes,
    required this.requestedAt,
    required this.expiresAt,
  });
  factory MobileLocationRequest.fromJson(Map<String, dynamic> json) =>
      MobileLocationRequest(
        id: json['id'] as String,
        requesterName: json['requesterName'] as String? ?? 'الإدارة',
        reason: json['reason'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        mode: json['mode'] as String? ?? 'snapshot',
        durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 1,
        requestedAt: DateTime.parse(json['requestedAt'] as String),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
      );
  final String id;
  final String requesterName;
  final String reason;
  final String status;
  final String mode;
  final int durationMinutes;
  final DateTime requestedAt;
  final DateTime? expiresAt;
  // V12 §9: الفيديو ملغى نهائيًا — needsVideo دائمًا false.
  bool get needsVideo => false;
  bool get needsPoint => mode == 'snapshot' || mode == 'location_video';
  bool get isTracking => mode.startsWith('track_');
}

class MobileActionTarget {
  const MobileActionTarget({
    required this.kind,
    required this.recordId,
    required this.mobileRoute,
  });
  factory MobileActionTarget.fromJson(Map<String, dynamic> json) =>
      MobileActionTarget(
        kind: json['kind'] as String? ?? '',
        recordId: json['recordId'] as String,
        mobileRoute: json['mobileRoute'] as String? ?? '',
      );
  final String kind;
  final String recordId;
  final String mobileRoute;
}

class MobileRequestStep {
  const MobileRequestStep({
    required this.id,
    required this.order,
    required this.name,
    required this.status,
    required this.decision,
    required this.comment,
    required this.decidedAt,
    required this.dueAt,
    required this.actorName,
  });
  factory MobileRequestStep.fromJson(Map<String, dynamic> json) =>
      MobileRequestStep(
        id: json['id'] as String,
        order: (json['order'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'مرحلة اعتماد',
        status: json['status'] as String? ?? 'pending',
        decision: json['decision'] as String?,
        comment: json['comment'] as String?,
        decidedAt: json['decidedAt'] == null
            ? null
            : DateTime.parse(json['decidedAt'] as String),
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String),
        actorName: json['actorName'] as String?,
      );
  final String id;
  final int order;
  final String name;
  final String status;
  final String? decision;
  final String? comment;
  final DateTime? decidedAt;
  final DateTime? dueAt;
  final String? actorName;
}

class MobileRequestAttachment {
  const MobileRequestAttachment({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  });

  factory MobileRequestAttachment.fromJson(Map<String, dynamic> json) =>
      MobileRequestAttachment(
        path: json['path'] as String,
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );

  final String path;
  final String mimeType;
  final int sizeBytes;
}

class MobileRequestDetail {
  const MobileRequestDetail({
    required this.id,
    required this.number,
    required this.type,
    required this.employeeName,
    required this.employeeCode,
    required this.title,
    required this.reason,
    required this.status,
    required this.workflowStatus,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    required this.canDecide,
    required this.canCancel,
    required this.steps,
    required this.attachments,
    required this.substituteName,
    required this.conflicts,
    required this.decisionActorName,
    required this.decisionMode,
    required this.decisionOnBehalfOfExecutive,
  });
  factory MobileRequestDetail.fromJson(Map<String, dynamic> json) =>
      MobileRequestDetail(
        id: json['id'] as String,
        number: (json['requestNumber'] as num?)?.toInt() ?? 0,
        type: json['requestType'] as String? ?? 'generic',
        employeeName: json['employeeName'] as String? ?? 'موظف',
        employeeCode: json['employeeCode'] as String?,
        title: json['title'] as String?,
        reason: json['reason'] as String?,
        status: json['status'] as String? ?? 'pending',
        workflowStatus: json['workflowStatus'] as String? ?? 'submitted',
        payload: Map<String, dynamic>.from(
          json['payload'] as Map<dynamic, dynamic>? ?? const {},
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        canDecide: json['canDecide'] as bool? ?? false,
        canCancel: json['canCancel'] as bool? ?? false,
        steps: (json['steps'] as List<dynamic>? ?? const [])
            .map(
              (item) => MobileRequestStep.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        attachments: (json['attachments'] as List<dynamic>? ?? const [])
            .map(
              (item) => MobileRequestAttachment.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        substituteName:
            ((json['decisionContext'] as Map<dynamic, dynamic>?)?['substitute']
                    as Map<dynamic, dynamic>?)?['name']
                as String?,
        conflicts:
            (((json['decisionContext'] as Map<dynamic, dynamic>?)?['conflicts']
                        as List<dynamic>?) ??
                    const [])
                .map(
                  (item) =>
                      (item as Map<dynamic, dynamic>)['message'] as String? ?? '',
                )
                .where((item) => item.isNotEmpty)
                .toList(growable: false),
        decisionActorName: json['decisionActorName'] as String?,
        decisionMode: json['decisionMode'] as String?,
        decisionOnBehalfOfExecutive:
            json['decisionOnBehalfOfExecutive'] as bool? ?? false,
      );
  final String id;
  final int number;
  final String type;
  final String employeeName;
  final String? employeeCode;
  final String? title;
  final String? reason;
  final String status;
  final String workflowStatus;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool canDecide;
  final bool canCancel;
  final List<MobileRequestStep> steps;
  final List<MobileRequestAttachment> attachments;
  final String? substituteName;
  final List<String> conflicts;
  final String? decisionActorName;
  final String? decisionMode;
  final bool decisionOnBehalfOfExecutive;
}

class PasskeyDevice {
  const PasskeyDevice({
    required this.id,
    required this.credentialId,
    required this.deviceLabel,
    required this.status,
    required this.trusted,
    required this.deviceType,
    required this.backedUp,
    required this.lastUsedAt,
    required this.createdAt,
  });
  factory PasskeyDevice.fromJson(Map<String, dynamic> json) => PasskeyDevice(
    id: json['id'] as String,
    credentialId: json['credentialId'] as String? ?? '',
    deviceLabel: json['deviceLabel'] as String? ?? 'جهاز موثوق',
    status: json['status'] as String? ?? 'active',
    trusted: json['trusted'] as bool? ?? false,
    deviceType: json['deviceType'] as String?,
    backedUp: json['backedUp'] as bool? ?? false,
    lastUsedAt: json['lastUsedAt'] == null
        ? null
        : DateTime.parse(json['lastUsedAt'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
  final String id;
  final String credentialId;
  final String deviceLabel;
  final String status;
  final bool trusted;
  final String? deviceType;
  final bool backedUp;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
}

class AttendanceHistoryItem {
  const AttendanceHistoryItem({
    required this.id,
    required this.eventType,
    required this.eventAt,
    required this.status,
    required this.verificationStatus,
    required this.lateMinutes,
    required this.requiresReview,
    required this.accuracyMeters,
    required this.distanceMeters,
    required this.source,
    required this.notes,
  });

  factory AttendanceHistoryItem.fromJson(Map<String, dynamic> json) =>
      AttendanceHistoryItem(
        id: json['id'] as String,
        eventType: json['eventType'] as String? ?? 'CHECK_IN',
        eventAt: DateTime.parse(json['eventAt'] as String),
        status: json['status'] as String? ?? 'pending',
        verificationStatus:
            json['verificationStatus'] as String? ?? 'unverified',
        lateMinutes: (json['lateMinutes'] as num?)?.toInt() ?? 0,
        requiresReview: json['requiresReview'] as bool? ?? false,
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
        distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
        source: json['source'] as String? ?? 'mobile',
        notes: json['notes'] as String?,
      );

  final String id;
  final String eventType;
  final DateTime eventAt;
  final String status;
  final String verificationStatus;
  final int lateMinutes;
  final bool requiresReview;
  final double? accuracyMeters;
  final double? distanceMeters;
  final String source;
  final String? notes;
}

class MobileDocumentSummary {
  const MobileDocumentSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.expiryDate,
    required this.status,
  });
  factory MobileDocumentSummary.fromJson(Map<String, dynamic> json) =>
      MobileDocumentSummary(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'other',
        title: json['title'] as String? ?? 'مستند',
        expiryDate: json['expiryDate'] == null
            ? null
            : DateTime.parse(json['expiryDate'] as String),
        status: json['status'] as String? ?? 'active',
      );
  final String id;
  final String type;
  final String title;
  final DateTime? expiryDate;
  final String status;
}

class MobileAssetSummary {
  const MobileAssetSummary({
    required this.id,
    required this.assetName,
    required this.assetType,
    required this.serial,
    required this.assignedAt,
    required this.returnedAt,
  });
  factory MobileAssetSummary.fromJson(Map<String, dynamic> json) =>
      MobileAssetSummary(
        id: json['id'] as String,
        assetName: json['assetName'] as String? ?? 'عهدة',
        assetType: json['assetType'] as String? ?? 'other',
        serial: json['serial'] as String?,
        assignedAt: json['assignedAt'] == null
            ? null
            : DateTime.parse(json['assignedAt'] as String),
        returnedAt: json['returnedAt'] == null
            ? null
            : DateTime.parse(json['returnedAt'] as String),
      );
  final String id;
  final String assetName;
  final String assetType;
  final String? serial;
  final DateTime? assignedAt;
  final DateTime? returnedAt;
}

class MobileProfile {
  const MobileProfile({
    required this.id,
    required this.employeeCode,
    required this.fullNameAr,
    required this.fullNameEn,
    required this.phoneE164,
    required this.photoUrl,
    required this.status,
    required this.hireDate,
    required this.contractEnd,
    required this.jobTitle,
    required this.position,
    required this.grade,
    required this.department,
    required this.team,
    required this.branch,
    required this.workSite,
    required this.managerName,
    required this.documents,
    required this.assets,
  });
  factory MobileProfile.fromJson(Map<String, dynamic> json) => MobileProfile(
    id: json['id'] as String,
    employeeCode: json['employeeCode'] as String? ?? '',
    fullNameAr: json['fullNameAr'] as String? ?? 'موظف',
    fullNameEn: json['fullNameEn'] as String?,
    phoneE164: json['phoneE164'] as String?,
    photoUrl: json['photoUrl'] as String?,
    status: json['status'] as String? ?? 'active',
    hireDate: json['hireDate'] == null
        ? null
        : DateTime.parse(json['hireDate'] as String),
    contractEnd: json['contractEnd'] == null
        ? null
        : DateTime.parse(json['contractEnd'] as String),
    jobTitle: json['jobTitle'] as String?,
    position: json['position'] as String?,
    grade: json['grade'] as String?,
    department: json['department'] as String?,
    team: json['team'] as String?,
    branch: json['branch'] as String?,
    workSite: json['workSite'] as String?,
    managerName: json['managerName'] as String?,
    documents: (json['documents'] as List<dynamic>? ?? const [])
        .map(
          (item) => MobileDocumentSummary.fromJson(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
          ),
        )
        .toList(growable: false),
    assets: (json['assets'] as List<dynamic>? ?? const [])
        .map(
          (item) => MobileAssetSummary.fromJson(
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
          ),
        )
        .toList(growable: false),
  );
  final String id;
  final String employeeCode;
  final String fullNameAr;
  final String? fullNameEn;
  final String? phoneE164;
  final String? photoUrl;
  final String status;
  final DateTime? hireDate;
  final DateTime? contractEnd;
  final String? jobTitle;
  final String? position;
  final String? grade;
  final String? department;
  final String? team;
  final String? branch;
  final String? workSite;
  final String? managerName;
  final List<MobileDocumentSummary> documents;
  final List<MobileAssetSummary> assets;
}

class MobileTask {
  const MobileTask({
    required this.id,
    required this.sourceType,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.dueDate,
    required this.createdAt,
    required this.createdByName,
    required this.isOverdue,
  });
  factory MobileTask.fromJson(Map<String, dynamic> json) => MobileTask(
    id: json['id'] as String,
    sourceType: json['sourceType'] as String? ?? 'task',
    title: json['title'] as String? ?? 'مهمة',
    description: json['description'] as String?,
    priority: json['priority'] as String? ?? 'medium',
    status: json['status'] as String? ?? 'pending',
    dueDate: json['dueDate'] == null
        ? null
        : DateTime.parse(json['dueDate'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    createdByName: json['createdByName'] as String?,
    isOverdue: json['isOverdue'] as bool? ?? false,
  );
  final String id;
  final String sourceType;
  final String title;
  final String? description;
  final String priority;
  final String status;
  final DateTime? dueDate;
  final DateTime createdAt;
  final String? createdByName;
  final bool isOverdue;
}

class MobileTeamMember {
  const MobileTeamMember({
    required this.id,
    required this.employeeCode,
    required this.name,
    required this.photoUrl,
    required this.jobTitle,
    required this.department,
    required this.team,
    required this.attendanceStatus,
    required this.lateMinutes,
    required this.firstCheckIn,
    required this.pendingRequests,
    required this.kpiStage,
  });
  factory MobileTeamMember.fromJson(Map<String, dynamic> json) =>
      MobileTeamMember(
        id: json['id'] as String,
        employeeCode: json['employeeCode'] as String?,
        name: json['name'] as String? ?? 'موظف',
        photoUrl: json['photoUrl'] as String?,
        jobTitle: json['jobTitle'] as String?,
        department: json['department'] as String?,
        team: json['team'] as String?,
        attendanceStatus: json['attendanceStatus'] as String?,
        lateMinutes: (json['lateMinutes'] as num?)?.toInt() ?? 0,
        firstCheckIn: json['firstCheckIn'] == null
            ? null
            : DateTime.parse(json['firstCheckIn'] as String),
        pendingRequests: (json['pendingRequests'] as num?)?.toInt() ?? 0,
        kpiStage: json['kpiStage'] as String?,
      );
  final String id;
  final String? employeeCode;
  final String name;
  final String? photoUrl;
  final String? jobTitle;
  final String? department;
  final String? team;
  final String? attendanceStatus;
  final int lateMinutes;
  final DateTime? firstCheckIn;
  final int pendingRequests;
  final String? kpiStage;
}

class MobileDailyReport {
  const MobileDailyReport({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.reportDate,
    required this.achievements,
    required this.blockers,
    required this.tomorrowPlan,
    required this.managerComment,
    required this.reviewerName,
    required this.reviewedAt,
    required this.createdAt,
  });
  factory MobileDailyReport.fromJson(Map<String, dynamic> json) =>
      MobileDailyReport(
        id: json['id'] as String,
        employeeId: json['employeeId'] as String,
        employeeName: json['employeeName'] as String? ?? 'موظف',
        reportDate: DateTime.parse(json['reportDate'] as String),
        achievements: json['achievements'] as String?,
        blockers: json['blockers'] as String?,
        tomorrowPlan: json['tomorrowPlan'] as String?,
        managerComment: json['managerComment'] as String?,
        reviewerName: json['reviewerName'] as String?,
        reviewedAt: json['reviewedAt'] == null
            ? null
            : DateTime.parse(json['reviewedAt'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
  final String id;
  final String employeeId;
  final String employeeName;
  final DateTime reportDate;
  final String? achievements;
  final String? blockers;
  final String? tomorrowPlan;
  final String? managerComment;
  final String? reviewerName;
  final DateTime? reviewedAt;
  final DateTime createdAt;
}

class MobileNotificationItem {
  const MobileNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.priority,
    required this.actionUrl,
    required this.entityType,
    required this.entityId,
    required this.isRead,
    required this.createdAt,
  });

  factory MobileNotificationItem.fromJson(Map<String, dynamic> json) =>
      MobileNotificationItem(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String?,
        category: json['category'] as String? ?? 'general',
        priority: json['priority'] as String? ?? 'normal',
        actionUrl: json['actionUrl'] as String?,
        entityType: json['entityType'] as String?,
        entityId: json['entityId'] as String?,
        isRead: json['isRead'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String title;
  final String? body;
  final String category;
  final String priority;
  final String? actionUrl;
  final String? entityType;
  final String? entityId;
  final bool isRead;
  final DateTime createdAt;

  bool get hasSupportedAction =>
      entityId != null &&
      const {'request', 'kpi', 'decision', 'announcement', 'dispute', 'task', 'attendance'}.contains(entityType);
}

class MobileLeaveBalance {
  const MobileLeaveBalance({
    required this.leaveTypeId,
    required this.code,
    required this.name,
    required this.availableUnits,
    required this.reservedUnits,
    required this.consumedUnits,
    required this.expiresAt,
  });

  factory MobileLeaveBalance.fromJson(Map<String, dynamic> json) =>
      MobileLeaveBalance(
        leaveTypeId: json['leave_type_id'] as String,
        code: json['code'] as String? ?? '',
        name: json['name_ar'] as String? ?? 'إجازة',
        availableUnits: (json['available_units'] as num?)?.toDouble() ?? 0,
        reservedUnits: (json['reserved_units'] as num?)?.toDouble() ?? 0,
        consumedUnits: (json['consumed_units'] as num?)?.toDouble() ?? 0,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String),
      );

  final String leaveTypeId;
  final String code;
  final String name;
  final double availableUnits;
  final double reservedUnits;
  final double consumedUnits;
  final DateTime? expiresAt;
}

/// تكليف عمل (مأمورية/قافلة/فاندي) — وحدة work_assignments.
/// لا يخصم من رصيد الإجازات ولا يُحتسب غيابًا.
class MobileWorkAssignment {
  const MobileWorkAssignment({
    required this.id,
    required this.assignmentNumber,
    required this.assignmentType,
    required this.title,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.isFullDay,
    required this.location,
    required this.needsReport,
    required this.targetAmount,
  });

  factory MobileWorkAssignment.fromJson(Map<String, dynamic> json) =>
      MobileWorkAssignment(
        id: json['id'] as String,
        assignmentNumber: (json['assignment_number'] as num?)?.toInt() ?? 0,
        assignmentType: json['assignment_type'] as String? ?? 'MISSION',
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? 'DRAFT',
        startAt: DateTime.parse(json['start_at'] as String),
        endAt: DateTime.parse(json['end_at'] as String),
        isFullDay: json['is_full_day'] as bool? ?? true,
        location: json['location'] as String?,
        needsReport: json['needs_report'] as bool? ?? false,
        targetAmount: (json['target_amount'] as num?)?.toDouble(),
      );

  final String id;
  final int assignmentNumber;
  final String assignmentType; // MISSION | CONVOY | FUNDRAISING
  final String title;
  final String status;
  final DateTime startAt;
  final DateTime endAt;
  final bool isFullDay;
  final String? location;
  final bool needsReport;
  final double? targetAmount;

  String get typeLabel => switch (assignmentType) {
        'CONVOY' => 'قافلة',
        'FUNDRAISING' => 'فاندي',
        _ => 'مأمورية',
      };
}

/// صف واحد في كشف الحضور اليومي (V12 §18).
class AttendanceStatementDay {
  const AttendanceStatementDay({
    required this.date,
    required this.dayNameAr,
    required this.checkIn,
    required this.checkOut,
    required this.shiftName,
    required this.workHours,
    required this.requiredHours,
    required this.lateMinutes,
    required this.status,
    required this.hasLeave,
    required this.hasPermit,
    required this.hasMission,
    required this.hasConvoyFundi,
    required this.missingCheckIn,
    required this.missingCheckOut,
    required this.correctionNote,
  });

  factory AttendanceStatementDay.fromJson(Map<String, dynamic> json) =>
      AttendanceStatementDay(
        date: json['date'] as String? ?? '',
        dayNameAr: json['dayNameAr'] as String? ?? '',
        checkIn: json['checkIn'] as String?,
        checkOut: json['checkOut'] as String?,
        shiftName: json['shiftName'] as String? ?? '',
        workHours: (json['workHours'] as num?)?.toDouble() ?? 0,
        requiredHours: (json['requiredHours'] as num?)?.toDouble() ?? 0,
        lateMinutes: (json['lateMinutes'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? '',
        hasLeave: json['hasLeave'] as bool? ?? false,
        hasPermit: json['hasPermit'] as bool? ?? false,
        hasMission: json['hasMission'] as bool? ?? false,
        hasConvoyFundi: json['hasConvoyFundi'] as bool? ?? false,
        missingCheckIn: json['missingCheckIn'] as bool? ?? false,
        missingCheckOut: json['missingCheckOut'] as bool? ?? false,
        correctionNote: json['correctionNote'] as String?,
      );

  final String date;
  final String dayNameAr;
  final String? checkIn;
  final String? checkOut;
  final String shiftName;
  final double workHours;
  final double requiredHours;
  final int lateMinutes;
  final String status;
  final bool hasLeave;
  final bool hasPermit;
  final bool hasMission;
  final bool hasConvoyFundi;
  final bool missingCheckIn;
  final bool missingCheckOut;
  final String? correctionNote;
}

/// ملخص شهري للكشف.
class AttendanceStatementSummary {
  const AttendanceStatementSummary({
    required this.totalDays,
    required this.scheduledDays,
    required this.presentDays,
    required this.absentDays,
    required this.leaveDays,
    required this.missionDays,
    required this.totalWorkHours,
    required this.averageWorkHours,
    required this.totalLateMinutes,
    required this.missingCheckInCount,
    required this.missingCheckOutCount,
  });

  factory AttendanceStatementSummary.fromJson(Map<String, dynamic> json) =>
      AttendanceStatementSummary(
        totalDays: (json['totalDays'] as num?)?.toInt() ?? 0,
        scheduledDays: (json['scheduledDays'] as num?)?.toInt() ?? 0,
        presentDays: (json['presentDays'] as num?)?.toInt() ?? 0,
        absentDays: (json['absentDays'] as num?)?.toInt() ?? 0,
        leaveDays: (json['leaveDays'] as num?)?.toInt() ?? 0,
        missionDays: (json['missionDays'] as num?)?.toInt() ?? 0,
        totalWorkHours: (json['totalWorkHours'] as num?)?.toDouble() ?? 0,
        averageWorkHours: (json['averageWorkHours'] as num?)?.toDouble() ?? 0,
        totalLateMinutes: (json['totalLateMinutes'] as num?)?.toInt() ?? 0,
        missingCheckInCount: (json['missingCheckInCount'] as num?)?.toInt() ?? 0,
        missingCheckOutCount: (json['missingCheckOutCount'] as num?)?.toInt() ?? 0,
      );

  final int totalDays;
  final int scheduledDays;
  final int presentDays;
  final int absentDays;
  final int leaveDays;
  final int missionDays;
  final double totalWorkHours;
  final double averageWorkHours;
  final int totalLateMinutes;
  final int missingCheckInCount;
  final int missingCheckOutCount;
}

/// كشف الحضور والانصراف الشهري الكامل (V12 §18).
class MonthlyAttendanceStatement {
  const MonthlyAttendanceStatement({
    required this.employeeNameAr,
    required this.year,
    required this.month,
    required this.days,
    required this.summary,
  });

  factory MonthlyAttendanceStatement.fromJson(Map<String, dynamic> json) {
    final emp = (json['employee'] as Map<String, dynamic>?) ?? {};
    final period = (json['period'] as Map<String, dynamic>?) ?? {};
    final sumJson = (json['summary'] as Map<String, dynamic>?) ?? {};
    final daysJson = (json['days'] as List<dynamic>?) ?? [];
    return MonthlyAttendanceStatement(
      employeeNameAr: emp['fullNameAr'] as String? ?? '',
      year: (period['year'] as num?)?.toInt() ?? 0,
      month: (period['month'] as num?)?.toInt() ?? 0,
      days: daysJson
          .map((e) => AttendanceStatementDay.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      summary: AttendanceStatementSummary.fromJson(sumJson),
    );
  }

  final String employeeNameAr;
  final int year;
  final int month;
  final List<AttendanceStatementDay> days;
  final AttendanceStatementSummary summary;
}

class MobileScheduleDay {
  const MobileScheduleDay({
    required this.id,
    required this.workDate,
    required this.dayStatus,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.notes,
  });
  factory MobileScheduleDay.fromJson(Map<String, dynamic> json) =>
      MobileScheduleDay(
        id: json['id'] as String,
        workDate: DateTime.parse(json['workDate'] as String),
        dayStatus: json['dayStatus'] as String? ?? 'scheduled',
        shiftName: json['shiftName'] as String?,
        startTime: json['startTime'] as String?,
        endTime: json['endTime'] as String?,
        notes: json['notes'] as String?,
      );
  final String id;
  final DateTime workDate;
  final String dayStatus;
  final String? shiftName;
  final String? startTime;
  final String? endTime;
  final String? notes;
}

class MobileAttendanceCorrection {
  const MobileAttendanceCorrection({
    required this.id,
    required this.workDate,
    required this.type,
    required this.reason,
    required this.status,
    required this.requestedCheckIn,
    required this.requestedCheckOut,
    required this.requestedStatus,
    required this.reviewNote,
    required this.createdAt,
  });
  factory MobileAttendanceCorrection.fromJson(Map<String, dynamic> json) =>
      MobileAttendanceCorrection(
        id: json['id'] as String,
        workDate: DateTime.parse(json['workDate'] as String),
        type: json['type'] as String? ?? 'other',
        reason: json['reason'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        requestedCheckIn: json['requestedCheckIn'] == null
            ? null
            : DateTime.parse(json['requestedCheckIn'] as String),
        requestedCheckOut: json['requestedCheckOut'] == null
            ? null
            : DateTime.parse(json['requestedCheckOut'] as String),
        requestedStatus: json['requestedStatus'] as String?,
        reviewNote: json['reviewNote'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
  final String id;
  final DateTime workDate;
  final String type;
  final String reason;
  final String status;
  final DateTime? requestedCheckIn;
  final DateTime? requestedCheckOut;
  final String? requestedStatus;
  final String? reviewNote;
  final DateTime createdAt;
}

class MobileAttendanceServices {
  const MobileAttendanceServices({
    required this.schedule,
    required this.corrections,
    required this.lastUpdatedAt,
  });
  factory MobileAttendanceServices.fromJson(Map<String, dynamic> json) =>
      MobileAttendanceServices(
        schedule: (json['schedule'] as List<dynamic>? ?? const [])
            .map(
              (e) => MobileScheduleDay.fromJson(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        corrections: (json['corrections'] as List<dynamic>? ?? const [])
            .map(
              (e) => MobileAttendanceCorrection.fromJson(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        lastUpdatedAt: json['lastUpdatedAt'] == null
            ? null
            : DateTime.parse(json['lastUpdatedAt'] as String),
      );
  final List<MobileScheduleDay> schedule;
  final List<MobileAttendanceCorrection> corrections;
  final DateTime? lastUpdatedAt;
}

class MobileDisputeCase {
  const MobileDisputeCase({
    required this.id,
    required this.caseNumber,
    required this.title,
    required this.description,
    required this.caseType,
    required this.status,
    required this.severity,
    required this.respondentName,
    required this.openedAt,
    required this.canCancel,
    required this.isCommitteeMember,
  });
  factory MobileDisputeCase.fromJson(Map<String, dynamic> json) =>
      MobileDisputeCase(
        id: json['id'] as String,
        caseNumber: json['caseNumber'] as String?,
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        caseType: json['caseType'] as String? ?? 'grievance',
        status: json['status'] as String? ?? 'submitted',
        severity: json['severity'] as String? ?? 'medium',
        respondentName: json['respondentName'] as String?,
        openedAt: DateTime.parse(json['openedAt'] as String),
        canCancel: json['canCancel'] as bool? ?? false,
        isCommitteeMember: json['isCommitteeMember'] as bool? ?? false,
      );
  final String id;
  final String? caseNumber;
  final String title;
  final String? description;
  final String caseType;
  final String status;
  final String severity;
  final String? respondentName;
  final DateTime openedAt;
  final bool canCancel;
  final bool isCommitteeMember;
}

class DisputeDirectoryEmployee {
  const DisputeDirectoryEmployee({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.department,
  });
  factory DisputeDirectoryEmployee.fromJson(Map<String, dynamic> json) =>
      DisputeDirectoryEmployee(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'موظف',
        employeeCode: json['employeeCode'] as String?,
        department: json['department'] as String?,
      );
  final String id;
  final String name;
  final String? employeeCode;
  final String? department;
}

class MobileDisputeDecision {
  const MobileDisputeDecision({
    required this.id,
    required this.caseId,
    required this.decisionNumber,
    required this.decisionText,
    required this.rationale,
    required this.outcomeType,
    required this.status,
    required this.issuedAt,
    required this.canAppeal,
  });
  factory MobileDisputeDecision.fromJson(Map<String, dynamic> json) =>
      MobileDisputeDecision(
        id: json['id'] as String,
        caseId: json['caseId'] as String,
        decisionNumber: json['decisionNumber'] as String? ?? '',
        decisionText: json['decisionText'] as String? ?? '',
        rationale: json['rationale'] as String? ?? '',
        outcomeType: json['outcomeType'] as String? ?? 'other',
        status: json['status'] as String? ?? 'issued',
        issuedAt: json['issuedAt'] == null
            ? null
            : DateTime.parse(json['issuedAt'] as String),
        canAppeal: json['canAppeal'] as bool? ?? false,
      );
  final String id;
  final String caseId;
  final String decisionNumber;
  final String decisionText;
  final String rationale;
  final String outcomeType;
  final String status;
  final DateTime? issuedAt;
  final bool canAppeal;
}

class MobileDisputeAppeal {
  const MobileDisputeAppeal({
    required this.id,
    required this.caseId,
    required this.decisionId,
    required this.reason,
    required this.status,
    required this.submittedAt,
    required this.resolution,
  });
  factory MobileDisputeAppeal.fromJson(Map<String, dynamic> json) =>
      MobileDisputeAppeal(
        id: json['id'] as String,
        caseId: json['caseId'] as String,
        decisionId: json['decisionId'] as String,
        reason: json['reason'] as String? ?? '',
        status: json['status'] as String? ?? 'submitted',
        submittedAt: DateTime.parse(json['submittedAt'] as String),
        resolution: json['resolution'] as String?,
      );
  final String id;
  final String caseId;
  final String decisionId;
  final String reason;
  final String status;
  final DateTime submittedAt;
  final String? resolution;
}

class MobileDisputePortal {
  const MobileDisputePortal({
    required this.cases,
    required this.decisions,
    required this.appeals,
  });
  factory MobileDisputePortal.fromJson(Map<String, dynamic> json) =>
      MobileDisputePortal(
        cases: (json['cases'] as List<dynamic>? ?? const [])
            .map(
              (e) => MobileDisputeCase.fromJson(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        decisions: (json['decisions'] as List<dynamic>? ?? const [])
            .map(
              (e) => MobileDisputeDecision.fromJson(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        appeals: (json['appeals'] as List<dynamic>? ?? const [])
            .map(
              (e) => MobileDisputeAppeal.fromJson(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
      );
  final List<MobileDisputeCase> cases;
  final List<MobileDisputeDecision> decisions;
  final List<MobileDisputeAppeal> appeals;
}

class MobileClearanceItem {
  const MobileClearanceItem({
    required this.id,
    required this.category,
    required this.title,
    required this.status,
    required this.dueAt,
    required this.completionNote,
  });
  factory MobileClearanceItem.fromJson(Map<String, dynamic> json) =>
      MobileClearanceItem(
        id: json['id'] as String,
        category: json['category'] as String? ?? 'other',
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String),
        completionNote: json['completionNote'] as String?,
      );
  final String id;
  final String category;
  final String title;
  final String status;
  final DateTime? dueAt;
  final String? completionNote;
}

class MobileOffboardingPortal {
  const MobileOffboardingPortal({
    required this.caseData,
    required this.clearance,
    required this.assignedAssets,
  });
  factory MobileOffboardingPortal.fromJson(Map<String, dynamic> json) =>
      MobileOffboardingPortal(
        caseData: json['case'] == null
            ? null
            : Map<String, dynamic>.from(json['case'] as Map<dynamic, dynamic>),
        clearance: (json['clearance'] as List<dynamic>? ?? const [])
            .map(
              (e) => MobileClearanceItem.fromJson(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        assignedAssets: (json['assignedAssets'] as List<dynamic>? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
            .toList(growable: false),
      );
  final Map<String, dynamic>? caseData;
  final List<MobileClearanceItem> clearance;
  final List<Map<String, dynamic>> assignedAssets;
}

class MobileLearningItem {
  const MobileLearningItem({
    required this.id,
    required this.courseId,
    required this.title,
    required this.category,
    required this.deliveryMode,
    required this.durationMinutes,
    required this.mandatory,
    required this.status,
    required this.progress,
    required this.score,
    required this.completedAt,
    required this.expiresAt,
  });
  factory MobileLearningItem.fromJson(Map<String, dynamic> json) =>
      MobileLearningItem(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? 'عام',
        deliveryMode: json['deliveryMode'] as String? ?? 'online',
        durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
        mandatory: json['mandatory'] as bool? ?? false,
        status: json['status'] as String? ?? 'enrolled',
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble(),
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.parse(json['completedAt'] as String),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
      );
  final String id;
  final String courseId;
  final String title;
  final String category;
  final String deliveryMode;
  final int durationMinutes;
  final bool mandatory;
  final String status;
  final int progress;
  final double? score;
  final DateTime? completedAt;
  final DateTime? expiresAt;
}

class MobileLearningCatalog {
  const MobileLearningCatalog({
    required this.items,
    required this.lastUpdatedAt,
  });
  factory MobileLearningCatalog.fromJson(Map<String, dynamic> json) =>
      MobileLearningCatalog(
        items: (json['items'] as List<dynamic>? ?? const [])
            .map(
              (item) => MobileLearningItem.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        lastUpdatedAt: json['lastUpdatedAt'] == null
            ? null
            : DateTime.parse(json['lastUpdatedAt'] as String),
      );
  final List<MobileLearningItem> items;
  final DateTime? lastUpdatedAt;
}

class MobileServiceCatalogItem {
  const MobileServiceCatalogItem({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.category,
    required this.slaHours,
  });
  factory MobileServiceCatalogItem.fromJson(Map<String, dynamic> json) =>
      MobileServiceCatalogItem(
        id: json['id'] as String,
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        category: json['category'] as String? ?? 'عام',
        slaHours: (json['slaHours'] as num?)?.toInt() ?? 24,
      );
  final String id;
  final String code;
  final String name;
  final String? description;
  final String category;
  final int slaHours;
}

class MobileServiceRequest {
  const MobileServiceRequest({
    required this.id,
    required this.number,
    required this.serviceName,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.dueAt,
    required this.createdAt,
    required this.satisfactionScore,
  });
  factory MobileServiceRequest.fromJson(Map<String, dynamic> json) =>
      MobileServiceRequest(
        id: json['id'] as String,
        number: (json['number'] as num?)?.toInt() ?? 0,
        serviceName: json['serviceName'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        priority: json['priority'] as String? ?? 'normal',
        status: json['status'] as String? ?? 'submitted',
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        satisfactionScore: (json['satisfactionScore'] as num?)?.toInt(),
      );
  final String id;
  final int number;
  final String serviceName;
  final String title;
  final String? description;
  final String priority;
  final String status;
  final DateTime? dueAt;
  final DateTime createdAt;
  final int? satisfactionScore;
}

class MobileServicePortal {
  const MobileServicePortal({
    required this.catalog,
    required this.requests,
    required this.lastUpdatedAt,
  });
  factory MobileServicePortal.fromJson(Map<String, dynamic> json) =>
      MobileServicePortal(
        catalog: (json['catalog'] as List<dynamic>? ?? const [])
            .map(
              (e) => MobileServiceCatalogItem.fromJson(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        requests: (json['requests'] as List<dynamic>? ?? const [])
            .map(
              (e) => MobileServiceRequest.fromJson(
                Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              ),
            )
            .toList(growable: false),
        lastUpdatedAt: json['lastUpdatedAt'] == null
            ? null
            : DateTime.parse(json['lastUpdatedAt'] as String),
      );
  final List<MobileServiceCatalogItem> catalog;
  final List<MobileServiceRequest> requests;
  final DateTime? lastUpdatedAt;
}

class MobilePayslipLine {
  const MobilePayslipLine({
    required this.id,
    required this.code,
    required this.name,
    required this.lineType,
    required this.amount,
  });
  factory MobilePayslipLine.fromJson(Map<String, dynamic> json) =>
      MobilePayslipLine(
        id: json['id'] as String,
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        lineType: json['lineType'] as String? ?? 'earning',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
  final String id;
  final String code;
  final String name;
  final String lineType;
  final double amount;
}

class MobilePayslip {
  const MobilePayslip({
    required this.id,
    required this.periodMonth,
    required this.currency,
    required this.grossAmount,
    required this.deductionAmount,
    required this.netAmount,
    required this.status,
    required this.issuedAt,
    required this.paidAt,
    required this.storagePath,
    required this.lines,
  });
  factory MobilePayslip.fromJson(Map<String, dynamic> json) => MobilePayslip(
    id: json['id'] as String,
    periodMonth: DateTime.parse(json['periodMonth'] as String),
    currency: json['currency'] as String? ?? 'EGP',
    grossAmount: (json['grossAmount'] as num?)?.toDouble() ?? 0,
    deductionAmount: (json['deductionAmount'] as num?)?.toDouble() ?? 0,
    netAmount: (json['netAmount'] as num?)?.toDouble() ?? 0,
    status: json['status'] as String? ?? 'issued',
    issuedAt: json['issuedAt'] == null
        ? null
        : DateTime.parse(json['issuedAt'] as String),
    paidAt: json['paidAt'] == null
        ? null
        : DateTime.parse(json['paidAt'] as String),
    storagePath: json['storagePath'] as String?,
    lines: (json['lines'] as List<dynamic>? ?? const [])
        .map(
          (e) => MobilePayslipLine.fromJson(
            Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
          ),
        )
        .toList(growable: false),
  );
  final String id;
  final DateTime periodMonth;
  final String currency;
  final double grossAmount;
  final double deductionAmount;
  final double netAmount;
  final String status;
  final DateTime? issuedAt;
  final DateTime? paidAt;
  final String? storagePath;
  final List<MobilePayslipLine> lines;
}

// ── AttendanceTodayEmployee ───────────────────────────────────────────────
// موظف مع حالة حضوره اليوم — يُستخدم في لوحة الحضور التنفيذية.
class AttendanceTodayEmployee {
  const AttendanceTodayEmployee({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.jobTitle,
    required this.department,
    required this.attendanceStatus,
    required this.firstCheckIn,
    required this.lastCheckOut,
    required this.lateMinutes,
    required this.isOnMission,
    required this.lastLatitude,
    required this.lastLongitude,
    required this.lastRecordedAt,
  });
  factory AttendanceTodayEmployee.fromJson(Map<String, dynamic> json) =>
      AttendanceTodayEmployee(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'موظف',
        employeeCode: json['employeeCode'] as String?,
        jobTitle: json['jobTitle'] as String?,
        department: json['department'] as String?,
        attendanceStatus: json['attendanceStatus'] as String? ?? 'absent',
        firstCheckIn: json['firstCheckIn'] == null
            ? null
            : DateTime.parse(json['firstCheckIn'] as String),
        lastCheckOut: json['lastCheckOut'] == null
            ? null
            : DateTime.parse(json['lastCheckOut'] as String),
        lateMinutes: (json['lateMinutes'] as num?)?.toInt() ?? 0,
        isOnMission: json['isOnMission'] as bool? ?? false,
        lastLatitude: (json['lastLatitude'] as num?)?.toDouble(),
        lastLongitude: (json['lastLongitude'] as num?)?.toDouble(),
        lastRecordedAt: json['lastRecordedAt'] == null
            ? null
            : DateTime.parse(json['lastRecordedAt'] as String),
      );
  final String id;
  final String name;
  final String? employeeCode;
  final String? jobTitle;
  final String? department;
  final String attendanceStatus;
  final DateTime? firstCheckIn;
  final DateTime? lastCheckOut;
  final int lateMinutes;
  final bool isOnMission;
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime? lastRecordedAt;

  String get statusAr {
    if (isOnMission) return 'مأمورية خارجية';
    return switch (attendanceStatus) {
      'present'  => 'حضر',
      'late'     => 'متأخر',
      'absent'   => 'غائب',
      'on_leave' => 'إجازة',
      'holiday'  => 'عطلة',
      'weekend'  => 'إجازة أسبوعية',
      'partial'  => 'حضور جزئي',
      'pending'  => 'في انتظار التحقق',
      _          => attendanceStatus,
    };
  }
}
