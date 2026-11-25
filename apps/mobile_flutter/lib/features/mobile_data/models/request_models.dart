import 'package:ahla_shabab_management_os/features/mobile_data/models/json_parse.dart';

class MobileRequest {
  const MobileRequest({
    required this.id,
    required this.number,
    required this.type,
    required this.employeeId,
    required this.employeeName,
    required this.employeePhotoUrl,
    required this.title,
    required this.reason,
    required this.status,
    required this.workflowStatus,
    required this.activeStepName,
    required this.createdAt,
    this.employeeDepartment,
    this.employeeJobTitle,
    this.activeStepRole,
    this.activeStepStatus,
    this.activeStepDueAt,
    this.decisionDueAt,
    this.decidedAt,
    this.decidedByName,
    this.payload = const {},
    this.isMine,
    this.canDecide,
    this.awaitingMe,
    this.missionExecution,
  });
  factory MobileRequest.fromJson(Map<String, dynamic> json) => MobileRequest(
    id: asString(json['id']),
    number: asInt(json['requestNumber'], 0),
    type: asString(json['requestType']),
    employeeId: asNullableString(json['employeeId']),
    employeeName: asString(json['employeeName'], 'موظف'),
    employeePhotoUrl: asNullableString(json['employeePhotoUrl']),
    title: asNullableString(json['title']),
    reason: asNullableString(json['reason']),
    status: asString(json['status'], 'pending'),
    workflowStatus: asString(json['workflowStatus'], 'submitted'),
    activeStepName: asNullableString(json['activeStepName']),
    createdAt: reqDate(json['createdAt']),
    employeeDepartment: asNullableString(json['employeeDepartment']),
    employeeJobTitle: asNullableString(json['employeeJobTitle']),
    activeStepRole: asNullableString(json['activeStepRole']),
    activeStepStatus: asNullableString(json['activeStepStatus']),
    activeStepDueAt: optDate(json['activeStepDueAt']),
    decisionDueAt: optDate(json['decisionDueAt']),
    decidedAt: optDate(json['decidedAt']),
    decidedByName: asNullableString(json['decidedByName']),
    payload: json['payload'] is Map
        ? asMap(json['payload'])
        : const {},
    isMine: asNullableBool(json['isMine']),
    canDecide: asNullableBool(json['canDecide']),
    awaitingMe: asNullableBool(json['awaitingMe']),
    missionExecution: json['missionExecution'] is Map
        ? MobileMissionExecution.fromJson(
            asMap(json['missionExecution']),
          )
        : null,
  );
  final String id;
  final int number;
  final String type;
  final String? employeeId;
  final String employeeName;
  final String? employeePhotoUrl;
  final String? title;
  final String? reason;
  final String status;
  final String workflowStatus;
  final String? activeStepName;
  final DateTime createdAt;

  /// 0646: بيانات العرض والقرار — اختيارية حتى تعمل الواجهة مع الخادم الأقدم.
  final String? employeeDepartment;
  final String? employeeJobTitle;
  final String? activeStepRole;
  final String? activeStepStatus;
  final DateTime? activeStepDueAt;
  final DateTime? decisionDueAt;
  final DateTime? decidedAt;
  final String? decidedByName;
  final Map<String, dynamic> payload;

  /// null عند الخادم الأقدم — تُحسب الملكية حينها بمقارنة employeeId.
  final bool? isMine;
  final bool? canDecide;
  final bool? awaitingMe;
  final MobileMissionExecution? missionExecution;

  bool isMineFor(String? myEmployeeId) =>
      isMine ?? (myEmployeeId != null && employeeId == myEmployeeId);

  /// مهلة القرار الفعلية: مهلة المرحلة الحالية ثم مهلة الطلب.
  DateTime? get effectiveDueAt => activeStepDueAt ?? decisionDueAt;
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
    this.roleSlug,
    this.escalatedAt,
    this.isCurrent,
  });
  factory MobileRequestStep.fromJson(Map<String, dynamic> json) =>
      MobileRequestStep(
        id: asString(json['id']),
        order: asInt(json['order'], 0),
        name: asString(json['name'], 'مرحلة اعتماد'),
        status: asString(json['status'], 'pending'),
        decision: asNullableString(json['decision']),
        comment: asNullableString(json['comment']),
        decidedAt: optDate(json['decidedAt']),
        dueAt: optDate(json['dueAt']),
        actorName: asNullableString(json['actorName']),
        roleSlug: asNullableString(json['roleSlug']),
        escalatedAt: optDate(json['escalatedAt']),
        isCurrent: asNullableBool(json['isCurrent']),
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

  /// 0646: دور المرحلة (مثل operations-manager-1) ووقت تصعيدها وكونها الحالية.
  final String? roleSlug;
  final DateTime? escalatedAt;
  final bool? isCurrent;
}

/// 0646: سياق القرار للمعتمِد — رصيد الإجازة، طلبات الشهر، والزملاء خارج المقر.
class MobileRequestInsights {
  const MobileRequestInsights({
    this.leaveName,
    this.leaveAvailable,
    this.leaveReserved,
    this.leaveConsumed,
    this.monthTotal = 0,
    this.monthMissions = 0,
    this.monthLeaves = 0,
    this.monthPermits = 0,
    this.monthRejected = 0,
    this.monthPending = 0,
    this.teamSize = 0,
    this.teamAway = const [],
  });

  factory MobileRequestInsights.fromJson(Map<String, dynamic> json) {
    final balance = json['leaveBalance'] is Map
        ? asMap(json['leaveBalance'])
        : null;
    final month = json['month'] is Map
        ? asMap(json['month'])
        : const <String, dynamic>{};
    int n(Object? v) => asInt(v, 0);
    return MobileRequestInsights(
      leaveName: asNullableString(balance?['name']),
      leaveAvailable: asNullableDouble(balance?['available']),
      leaveReserved: asNullableDouble(balance?['reserved']),
      leaveConsumed: asNullableDouble(balance?['consumed']),
      monthTotal: n(month['total']),
      monthMissions: n(month['missions']),
      monthLeaves: n(month['leaves']),
      monthPermits: n(month['permits']),
      monthRejected: n(month['rejected']),
      monthPending: n(month['pending']),
      teamSize: n(json['teamSize']),
      teamAway: asList(json['teamAway'])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (m) => (
              name: asString(m['name'], 'موظف'),
              type: asString(m['type'], ''),
              status: asString(m['status'], ''),
            ),
          )
          .toList(growable: false),
    );
  }

  final String? leaveName;
  final double? leaveAvailable;
  final double? leaveReserved;
  final double? leaveConsumed;
  final int monthTotal;
  final int monthMissions;
  final int monthLeaves;
  final int monthPermits;
  final int monthRejected;
  final int monthPending;
  final int teamSize;
  final List<({String name, String type, String status})> teamAway;
}

/// 0646: حدث في سجل الطلب (تقديم، تصعيد، قرار، سحب، إعادة رفع).
class MobileRequestHistoryEntry {
  const MobileRequestHistoryEntry({
    required this.action,
    required this.at,
    this.actorName,
    this.comment,
    this.stepOrder,
    this.stepName,
    this.stepRole,
    this.targetRole,
    this.repeat,
    this.isResubmit = false,
  });

  factory MobileRequestHistoryEntry.fromJson(Map<String, dynamic> json) =>
      MobileRequestHistoryEntry(
        action: asString(json['action'], ''),
        at: reqDate(json['at']),
        actorName: asNullableString(json['actorName']),
        comment: asNullableString(json['comment']),
        stepOrder: asNullableInt(json['stepOrder']),
        stepName: asNullableString(json['stepName']),
        stepRole: asNullableString(json['stepRole']),
        targetRole: asNullableString(json['targetRole']),
        repeat: asNullableInt(json['repeat']),
        isResubmit: asBool(json['isResubmit'], false),
      );

  final String action;
  final DateTime at;
  final String? actorName;
  final String? comment;
  final int? stepOrder;
  final String? stepName;
  final String? stepRole;
  final String? targetRole;
  final int? repeat;
  final bool isResubmit;
}

class MobileRequestAttachment {
  const MobileRequestAttachment({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  });

  factory MobileRequestAttachment.fromJson(Map<String, dynamic> json) =>
      MobileRequestAttachment(
        path: asString(json['path']),
        mimeType: asString(json['mimeType'], 'application/octet-stream'),
        sizeBytes: asInt(json['sizeBytes'], 0),
      );

  final String path;
  final String mimeType;
  final int sizeBytes;
}

class MobileMissionExecution {
  const MobileMissionExecution({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.actualMinutes,
    required this.report,
    required this.outcome,
    this.autoClosedAt,
  });

  factory MobileMissionExecution.fromJson(Map<String, dynamic> json) =>
      MobileMissionExecution(
        id: asString(json['id']),
        status: asString(json['status'], 'not_started'),
        startedAt: optDate(json['startedAt']),
        endedAt: optDate(json['endedAt']),
        actualMinutes: asNullableInt(json['actualMinutes']),
        report: asNullableString(json['report']),
        outcome: asNullableString(json['outcome']),
        autoClosedAt: DateTime.tryParse(json['autoClosedAt']?.toString() ?? ''),
      );

  /// نص الخادم (0658) لمأمورية أغلقها النظام قبل أن يكتب صاحبها تقريرها.
  static const autoClosedReport =
      'أُغلقت تلقائيًا بعد انقضاء يومها دون تقرير من الموظف';

  /// مهلة كتابة تقرير المأمورية المغلقة تلقائيًا (submit_my_mission_report).
  static const reportWindow = Duration(days: 14);

  final String id;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? actualMinutes;
  final String? report;
  final String? outcome;

  /// أغلقها النظام لانقضاء يومها دون إنهاء (0658).
  final DateTime? autoClosedAt;

  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isAutoClosed => autoClosedAt != null;

  /// أُغلقت تلقائيًا ولم يكتب صاحبها تقريرًا بعد.
  bool get awaitsReport {
    final text = report?.trim() ?? '';
    return isAutoClosed && (text.isEmpty || text == autoClosedReport);
  }

  /// آخر موعد لكتابة التقرير.
  DateTime? get reportDeadline => autoClosedAt?.add(reportWindow);
}

class MobileRequestDetail {
  const MobileRequestDetail({
    required this.id,
    required this.number,
    required this.type,
    this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.employeePhotoUrl,
    required this.title,
    required this.reason,
    required this.status,
    required this.workflowStatus,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    required this.canDecide,
    required this.canCancel,
    required this.canResubmit,
    required this.steps,
    required this.attachments,
    required this.substituteName,
    required this.conflicts,
    required this.decisionActorName,
    required this.decisionMode,
    required this.decisionOnBehalfOfExecutive,
    required this.missionExecution,
    this.employeeDepartment,
    this.employeeJobTitle,
    this.decisionDueAt,
    this.decidedAt,
    this.decidedByName,
    this.cancelledAt,
    this.cancelReason,
    this.cancelledByName,
    this.isMine,
    this.awaitingMe,
    this.history,
    this.insights,
  });
  factory MobileRequestDetail.fromJson(Map<String, dynamic> json) =>
      MobileRequestDetail(
        insights: json['insights'] is Map
            ? MobileRequestInsights.fromJson(
                asMap(json['insights']),
              )
            : null,
        employeeDepartment: asNullableString(json['employeeDepartment']),
        employeeJobTitle: asNullableString(json['employeeJobTitle']),
        decisionDueAt: optDate(json['decisionDueAt']),
        decidedAt: optDate(json['decidedAt']),
        decidedByName: asNullableString(json['decidedByName']),
        cancelledAt: optDate(json['cancelledAt']),
        cancelReason: asNullableString(json['cancelReason']),
        cancelledByName: asNullableString(json['cancelledByName']),
        isMine: asNullableBool(json['isMine']),
        awaitingMe: asNullableBool(json['awaitingMe']),
        // null عند الخادم الأقدم (قبل 0646) فيُبنى السجل من المراحل
        history: json['history'] is List
            ? asMapList(json['history'])
                  .map(MobileRequestHistoryEntry.fromJson)
                  .toList(growable: false)
            : null,
        id: asString(json['id']),
        number: asInt(json['requestNumber'], 0),
        type: asString(json['requestType'], 'leave'),
        employeeId: asNullableString(json['employeeId']),
        employeeName: asString(json['employeeName'], 'موظف'),
        employeeCode: asNullableString(json['employeeCode']),
        employeePhotoUrl: asNullableString(json['employeePhotoUrl']),
        title: asNullableString(json['title']),
        reason: asNullableString(json['reason']),
        status: asString(json['status'], 'pending'),
        workflowStatus: asString(json['workflowStatus'], 'submitted'),
        payload: asMap(json['payload']),
        createdAt: reqDate(json['createdAt']),
        updatedAt: optDate(json['updatedAt']),
        canDecide: asBool(json['canDecide'], false),
        canCancel: asBool(json['canCancel'], false),
        canResubmit: asBool(json['canResubmit'], false),
        steps: asList(json['steps'])
            .map(
              (item) => MobileRequestStep.fromJson(
                asMap(item),
              ),
            )
            .toList(growable: false),
        attachments: asList(json['attachments'])
            .map(
              (item) => MobileRequestAttachment.fromJson(
                asMap(item),
              ),
            )
            .toList(growable: false),
        substituteName: asNullableString(
          asNullableMap(asNullableMap(json['decisionContext'])?['substitute'])?['name'],
        ),
        conflicts: asMapList(
          asNullableMap(json['decisionContext'])?['conflicts'],
        )
            .map((item) => asString(item['message']))
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        decisionActorName: asNullableString(json['decisionActorName']),
        decisionMode: asNullableString(json['decisionMode']),
        decisionOnBehalfOfExecutive:
            asBool(json['decisionOnBehalfOfExecutive'], false),
        missionExecution: asNullableMap(json['missionExecution']) == null
            ? null
            : MobileMissionExecution.fromJson(asMap(json['missionExecution'])),
      );
  final String id;
  final int number;
  final String type;
  final String employeeName;
  final String? employeeCode;
  final String? employeePhotoUrl;
  final String? title;
  final String? reason;
  final String status;
  final String workflowStatus;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool canDecide;
  final bool canCancel;

  /// 0451: هل يمكن للمالك تعديل الطلب المرفوض/المُرجَع ورفعه مجدداً؟
  final bool canResubmit;
  final List<MobileRequestStep> steps;
  final List<MobileRequestAttachment> attachments;
  final String? substituteName;
  final List<String> conflicts;
  final String? decisionActorName;
  final String? decisionMode;
  final bool decisionOnBehalfOfExecutive;
  final String? employeeId;
  final MobileMissionExecution? missionExecution;

  /// 0646: الإدارة والوظيفة، القرار والسحب، وسجل الإجراءات.
  final String? employeeDepartment;
  final String? employeeJobTitle;
  final DateTime? decisionDueAt;
  final DateTime? decidedAt;
  final String? decidedByName;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final String? cancelledByName;
  final bool? isMine;
  final bool? awaitingMe;
  final List<MobileRequestHistoryEntry>? history;

  /// للمعتمِد فقط (لا تُرسل لصاحب الطلب).
  final MobileRequestInsights? insights;

  bool isMineFor(String? myEmployeeId) =>
      isMine ?? (myEmployeeId != null && employeeId == myEmployeeId);
}

/// نموذج بيانات تفويض الاعتماد الإداري
class ApprovalDelegation {
  const ApprovalDelegation({
    required this.id,
    required this.managerEmployeeId,
    required this.managerName,
    required this.managerCode,
    required this.delegateEmployeeId,
    required this.delegateName,
    required this.delegateCode,
    required this.startsAt,
    required this.endsAt,
    this.reason,
    this.cancelledAt,
    required this.createdAt,
    required this.isMine,
    required this.isActive,
    required this.status,
  });

  factory ApprovalDelegation.fromJson(Map<String, dynamic> json) =>
      ApprovalDelegation(
        id: asString(json['id'], ''),
        managerEmployeeId: asString(json['manager_employee_id'], ''),
        managerName: asString(json['manager_name'], ''),
        managerCode: asString(json['manager_code'], ''),
        delegateEmployeeId: asString(json['delegate_employee_id'], ''),
        delegateName: asString(json['delegate_name'], ''),
        delegateCode: asString(json['delegate_code'], ''),
        startsAt: asString(json['starts_at'], ''),
        endsAt: asString(json['ends_at'], ''),
        reason: asNullableString(json['reason']),
        cancelledAt: json['cancelled_at'] != null
            ? DateTime.tryParse(json['cancelled_at'].toString())
            : null,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        isMine: asBool(json['is_mine'], false),
        isActive: asBool(json['is_active'], false),
        status: asString(json['status'], 'active'),
      );

  final String id;
  final String managerEmployeeId;
  final String managerName;
  final String managerCode;
  final String delegateEmployeeId;
  final String delegateName;
  final String delegateCode;
  final String startsAt;
  final String endsAt;
  final String? reason;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final bool isMine;
  final bool isActive;
  final String status;
}
