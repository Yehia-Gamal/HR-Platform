import 'package:ahla_shabab_management_os/features/mobile_data/models/json_parse.dart';

class MobileKpiEvaluation {
  const MobileKpiEvaluation({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.employeePhotoUrl,
    required this.periodMonth,
    required this.currentStage,
    required this.workflowStatus,
    required this.deadlineAt,
    required this.finalScore,
    required this.finalRating,
    required this.relation,
  });
  factory MobileKpiEvaluation.fromJson(Map<String, dynamic> json) =>
      MobileKpiEvaluation(
        id: asString(json['id']),
        employeeId: asString(json['employeeId']),
        employeeName: asString(json['employeeName'], 'موظف'),
        employeeCode: asNullableString(json['employeeCode']),
        employeePhotoUrl: asNullableString(json['employeePhotoUrl']),
        periodMonth: reqDate(json['periodMonth']),
        currentStage: asString(json['currentStage'], 'self'),
        workflowStatus: asString(json['workflowStatus'], 'NOT_STARTED'),
        deadlineAt: optDate(json['deadlineAt']),
        finalScore: asNullableDouble(json['finalScore']),
        finalRating: asNullableString(json['finalRating']),
        relation: asNullableString(json['relation']),
      );
  final String id;
  final String employeeId;
  final String employeeName;
  final String? employeeCode;
  final String? employeePhotoUrl;
  final DateTime periodMonth;
  final String currentStage;
  final String workflowStatus;
  final DateTime? deadlineAt;
  final double? finalScore;
  final String? finalRating;

  /// 0204: relation — self (تقييمي) / team (فريقي) / review (مهام)
  final String? relation;
}

class KpiStageScore {
  const KpiStageScore({required this.score, required this.note});
  factory KpiStageScore.fromJson(Map<String, dynamic> json) => KpiStageScore(
    score: asNullableDouble(json['score']),
    note: asNullableString(json['note']),
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
    final rawScores = asMap(json['stageScores']);
    return KpiCriterionForm(
      id: asString(json['id']),
      code: asString(json['code'], ''),
      name: asString(json['name'], 'معيار'),
      weight: asDouble(json['weight'], 0),
      maxScore: asDouble(json['maxScore'], 100),
      sortOrder: asInt(json['sortOrder'], 0),
      stageScores: rawScores.map(
        (key, value) => MapEntry(
          key,
          KpiStageScore.fromJson(
            asMap(value),
          ),
        ),
      ),
      description: asNullableString(json['description']),
      sourceType: asString(json['sourceType'], 'manual'),
      evaluatorStage: asNullableString(json['evaluatorStage']),
      calculationMethod: asString(json['calculationMethod'], 'manual'),
      editable: asBool(json['editable'], false),
      effectiveScore: asNullableDouble(json['effectiveScore']),
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
    id: asString(json['id']),
    title: asString(json['title'], 'هدف'),
    targetValue: asDouble(json['targetValue'], 0),
    achievedValue: asDouble(json['achievedValue'], 0),
    unit: asString(json['unit'], ''),
    weight: asDouble(json['weight'], 0),
    status: asString(json['status'], 'NOT_STARTED'),
    calculatedScore: asDouble(json['calculatedScore'], 0),
    evidenceSource: asNullableString(json['evidenceSource']),
    employeeNote: asNullableString(json['employeeNote']),
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
        metric: asString(json['metric']),
        requiredCount: asInt(json['requiredCount'], 0),
        actualCount: asInt(json['actualCount'], 0),
        exemptCount: asInt(json['exemptCount'], 0),
        cancelledCount: asInt(json['cancelledCount'], 0),
        score: asDouble(json['score'], 0),
        note: asNullableString(json['note']),
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
        lateCount: asInt(json['lateCount'], 0),
        earlyLeaveCount: asInt(json['earlyLeaveCount'], 0),
        unexcusedAbsenceCount:
            asInt(json['unexcusedAbsenceCount'], 0),
        shortagePenalty: asDouble(json['shortagePenalty'], 0),
        missingPunchCount: asInt(json['missingPunchCount'], 0),
        score: asDouble(json['score'], 0),
        hasPendingItems: asBool(json['hasPendingItems'], false),
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
    this.parallelFlow = false,
    this.complianceEditable = false,
    this.hrCompleted = false,
    this.managerCompleted = false,
    this.version = 1,
    this.relation,
  });
  factory KpiEvaluationForm.fromJson(Map<String, dynamic> json) =>
      KpiEvaluationForm(
        id: asString(json['id']),
        employeeId: asString(json['employeeId']),
        employeeName: asString(json['employeeName'], 'موظف'),
        employeeCode: asNullableString(json['employeeCode']),
        periodMonth: reqDate(json['periodMonth']),
        currentStage: asString(json['currentStage'], 'self'),
        workflowStatus: asString(json['workflowStatus'], 'NOT_STARTED'),
        editableStage: asNullableString(json['editableStage']),
        locked: asBool(json['locked'], false),
        finalScore: asNullableDouble(json['finalScore']),
        finalRating: asNullableString(json['finalRating']),
        relation: asNullableString(json['relation']),
        criteria: asList(json['criteria'])
            .map(
              (item) => KpiCriterionForm.fromJson(
                asMap(item),
              ),
            )
            .toList(growable: false),
        goals: asList(json['goals'])
            .map(
              (item) => KpiGoalForm.fromJson(
                asMap(item),
              ),
            )
            .toList(growable: false),
        compliance: asList(json['compliance'])
            .map(
              (item) => KpiComplianceForm.fromJson(
                asMap(item),
              ),
            )
            .toList(growable: false),
        attendance: asNullableMap(json['attendance']) == null
            ? null
            : KpiAttendanceSummary.fromJson(asMap(json['attendance'])),
        validationErrors:
            asList(json['validationErrors'])
                .map((item) => item.toString())
                .toList(growable: false),
        parallelFlow: asBool(json['parallelFlow'], false),
        complianceEditable: asBool(json['complianceEditable'], false),
        hrCompleted: asBool(json['hrCompleted'], false),
        managerCompleted: asBool(json['managerCompleted'], false),
        version: asInt(json['version'], 1),
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
  // V23: حقول المسار المتوازي.
  final bool parallelFlow;
  // 0470: HR يدخل الاستثناءات في أي مرحلة قبل القفل.
  final bool complianceEditable;
  final bool hrCompleted;
  final bool managerCompleted;
  final int version;

  /// 0204: relation — self/team/review
  final String? relation;
}
