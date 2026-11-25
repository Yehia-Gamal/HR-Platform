import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/models/json_parse.dart';

class MobileFeedItem {
  const MobileFeedItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.priority,
    required this.requiresAcknowledgement,
    required this.myAcknowledged,
    required this.viewCount,
    required this.reactionCount,
    required this.reactionSummary,
    required this.publishedAt,
    this.imageUrl,
    this.postType,
    this.authorName,
    this.authorPhotoUrl,
    this.myReaction,
  });
  factory MobileFeedItem.fromJson(Map<String, dynamic> json) => MobileFeedItem(
    id: asString(json['id']),
    kind: asString(json['kind'], 'announcement'),
    title: asString(json['title'], ''),
    body: asString(json['body'], ''),
    priority: asString(json['priority'], 'normal'),
    requiresAcknowledgement: asBool(json['requiresAcknowledgement'], false),
    myAcknowledged: asBool(json['myAcknowledged'], false),
    viewCount: asInt(json['viewCount'], 0),
    reactionCount: asInt(json['reactionCount'], 0),
    reactionSummary: asMap(json['reactionSummary']).map(
      (key, value) => MapEntry(key, asInt(value)),
    ),
    publishedAt: optDate(json['publishedAt']),
    imageUrl: asNullableString(json['imageUrl']),
    postType: asNullableString(json['postType']),
    authorName: asNullableString(json['authorName']),
    authorPhotoUrl: asNullableString(json['authorPhotoUrl']),
    myReaction: asNullableString(json['myReaction']),
  );
  final String id;
  final String kind;
  final String title;
  final String body;
  final String priority;
  final bool requiresAcknowledgement;
  final bool myAcknowledged;
  final int viewCount;
  final int reactionCount;
  final Map<String, int> reactionSummary;
  final DateTime? publishedAt;
  final String? imageUrl;
  final String? postType;
  final String? authorName;
  final String? authorPhotoUrl;
  final String? myReaction;

  /// تسمية نوع المنشور بالعربية
  String get postTypeLabel => switch (postType ?? kind) {
    'announcement' => 'إعلان',
    'decision' => 'قرار إداري',
    'alert' => 'تنبيه',
    'poll' => 'تصويت',
    'meeting' => 'اجتماع',
    'holiday_notice' => 'إشعار عطلة',
    'kpi_notice' => 'إشعار أداء',
    'attendance_notice' => 'إشعار حضور',
    _ => kind,
  };
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
    this.employeeName,
    this.photoUrl,
    this.requestType,
    this.requestNumber,
    this.requestTitle,
    this.requestReason,
  });
  factory MobileActionItem.fromJson(Map<String, dynamic> json) =>
      MobileActionItem(
        id: asString(json['id']),
        kind: asString(json['kind'], 'task'),
        title: asString(json['title'], ''),
        subtitle: asNullableString(json['subtitle']),
        priority: asString(json['priority'], 'normal'),
        status: asString(json['status'], ''),
        dueAt: optDate(json['dueAt']),
        employeeName: asNullableString(json['employeeName']),
        photoUrl: asNullableString(json['photoUrl']),
        requestType: asNullableString(json['requestType']),
        requestNumber: asNullableInt(json['requestNumber']),
        requestTitle: asNullableString(json['requestTitle']),
        requestReason: asNullableString(json['requestReason']),
      );
  final String id;
  final String kind;
  final String title;
  final String? subtitle;
  final String priority;
  final String status;
  final DateTime? dueAt;
  final String? employeeName;
  final String? photoUrl;
  final String? requestType;
  final int? requestNumber;
  final String? requestTitle;
  final String? requestReason;

  // مفتاح mobileActionTargetProvider (family): بدون مساواة قيمية يُنشأ مزوّد
  // جديد في كل إعادة بناء (مثل كل حدث من onAuthStateChange عند الإقلاع)
  // فيعود إلى «جاري فتح الإشعار...» ويُطلق RPC جديداً دون أن يستقر أبداً.
  @override
  bool operator ==(Object other) =>
      other is MobileActionItem && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
}

class MobileActionTarget {
  const MobileActionTarget({
    required this.kind,
    required this.recordId,
    required this.mobileRoute,
  });
  factory MobileActionTarget.fromJson(Map<String, dynamic> json) =>
      MobileActionTarget(
        kind: asString(json['kind'], ''),
        recordId: asString(json['recordId']),
        mobileRoute: asString(json['mobileRoute'], ''),
      );
  final String kind;
  final String recordId;
  final String mobileRoute;
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
    id: asString(json['id']),
    sourceType: asString(json['sourceType'], 'task'),
    title: asString(json['title'], 'مهمة'),
    description: asNullableString(json['description']),
    priority: asString(json['priority'], 'medium'),
    status: asString(json['status'], 'pending'),
    dueDate: optDate(json['dueDate']),
    createdAt: reqDate(json['createdAt']),
    createdByName: asNullableString(json['createdByName']),
    isOverdue: asBool(json['isOverdue'], false),
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
        id: asString(json['id']),
        employeeId: asString(json['employeeId']),
        employeeName: asString(json['employeeName'], 'موظف'),
        reportDate: reqDate(json['reportDate']),
        achievements: asNullableString(json['achievements']),
        blockers: asNullableString(json['blockers']),
        tomorrowPlan: asNullableString(json['tomorrowPlan']),
        managerComment: asNullableString(json['managerComment']),
        reviewerName: asNullableString(json['reviewerName']),
        reviewedAt: optDate(json['reviewedAt']),
        createdAt: reqDate(json['createdAt']),
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
    this.metadata = const {},
  });

  factory MobileNotificationItem.fromJson(Map<String, dynamic> json) =>
      MobileNotificationItem(
        id: asString(json['id']),
        title: asString(json['title'], ''),
        body: asNullableString(json['body']),
        category: asString(json['category'], 'general'),
        priority: asString(json['priority'], 'normal'),
        actionUrl: asNullableString(json['actionUrl']),
        entityType: asNullableString(json['entityType']),
        entityId: asNullableString(json['entityId']),
        isRead: asBool(json['isRead'], false),
        createdAt: reqDate(json['createdAt']),
        metadata: json['metadata'] is Map
            ? asMap(json['metadata'])
            : const {},
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

  /// سياق الحدث الذي يفتحه الإشعار (workDate / employeeId / evaluationId …).
  /// تعيده get_my_notifications منذ migration 0523 — بدونه كان التطبيق يفتح
  /// الصفحة العامة بدل الحدث نفسه.
  final Map<String, dynamic> metadata;

  /// قراءة آمنة لحقل نصي من [metadata].
  String? meta(String key) {
    final value = metadata[key];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  /// اسم النوع الموحّد (بعد تطبيع صيغ الخلفية مثل live_location_requests → live_location_request).
  String? get canonicalType => canonicalNotificationEntityType(entityType);

  /// أنواع تُحل عبر resolve_mobile_action_target (تحقق صلاحيات على الخادم).
  static const _serverResolvedTypes = {
    'request',
    'kpi',
    'decision',
    'announcement',
    'dispute',
    'task',
    'attendance',
    'attendance_correction',
    'attendance_corrections',
    'recognition',
    'live_location_request',
  };

  /// أنواع لها صفحة موبايل مباشرة — لا يعرفها الـ RPC، وكان النقر عليها
  /// لا يفتح شيئاً رغم وجود الصفحة في التطبيق.
  static const _localRouteTypes = {
    'instant_penalty',
    'daily_report',
    'device',
    'attendance_correction',
    'attendance_corrections',
    'association_project',
    'weekly_executive_summary',
  };

  bool get hasSupportedAction =>
      entityId != null &&
      (_serverResolvedTypes.contains(canonicalType) ||
          _localRouteTypes.contains(canonicalType));

  /// هل يُفتح هذا الإشعار بصفحة محلية بدل RPC؟
  bool get hasLocalRoute => _localRouteTypes.contains(canonicalType);

  /// هل الإشعار من الأنواع المعلوماتية (لا صفحة موبايل محددة)؟
  /// هذه الأنواع تُعلَّم مقروءة عند النقر وتُعرض في القائمة دون فتح مسار.
  bool get isInformational => const {
    'attendance_manager_notify',
    'broadcast_alert',
    'fellowship_fund',
    'work_assignments',
    'kpi_appeals',
    'break_glass_requests',
    'offboarding_cases',
    'privacy_requests',
    'service_requests',
    'wellbeing_requests',
    'document_signature_requests',
    'employee_device',
    'public_holiday',
    'role',
  }.contains(canonicalType);
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
        leaveTypeId: asString(json['leave_type_id']),
        code: asString(json['code'], ''),
        name: asString(json['name_ar'], 'إجازة'),
        availableUnits: asDouble(json['available_units'], 0),
        reservedUnits: asDouble(json['reserved_units'], 0),
        consumedUnits: asDouble(json['consumed_units'], 0),
        expiresAt: optDate(json['expires_at']),
      );

  final String leaveTypeId;
  final String code;
  final String name;
  final double availableUnits;
  final double reservedUnits;
  final double consumedUnits;
  final DateTime? expiresAt;
}

class MobilePermitItem {
  const MobilePermitItem({
    required this.id,
    required this.date,
    required this.kind,
    required this.kindLabel,
    required this.minutes,
    required this.status,
    required this.title,
  });

  factory MobilePermitItem.fromJson(Map<String, dynamic> json) =>
      MobilePermitItem(
        id: asString(json['id'], ''),
        date: asString(json['date'], ''),
        kind: asString(json['kind'], ''),
        kindLabel: asString(json['kind_label'], 'إذن'),
        minutes: asInt(json['minutes'], 120),
        status: asString(json['status'], 'pending'),
        title: asString(json['title'], ''),
      );

  final String id;
  final String date;
  final String kind;
  final String kindLabel;
  final int minutes;
  final String status;
  final String title;
}

/// رصيد أذونات الموظف الشهري (الحد الأقصى 4 أذونات = 8 ساعات شهريًا).
class MobilePermitBalance {
  const MobilePermitBalance({
    required this.month,
    required this.maxPermits,
    required this.maxHours,
    required this.usedApproved,
    required this.usedPending,
    required this.totalUsed,
    required this.remainingPermits,
    required this.remainingHours,
    required this.minutesPerPermit,
    required this.hasRemaining,
    required this.items,
  });

  factory MobilePermitBalance.fromJson(Map<String, dynamic> json) =>
      MobilePermitBalance(
        month: asString(json['month'], ''),
        maxPermits: asInt(json['max_permits'], 4),
        maxHours: asInt(json['max_hours'], 8),
        usedApproved: asInt(json['used_approved'], 0),
        usedPending: asInt(json['used_pending'], 0),
        totalUsed: asInt(json['total_used'], 0),
        remainingPermits: asInt(json['remaining_permits'], 4),
        remainingHours: asInt(json['remaining_hours'], 8),
        minutesPerPermit: asInt(json['minutes_per_permit'], 120),
        hasRemaining: (asNullableBool(json['has_remaining'])) ?? true,
        items: asList(json['items'])
            .map((e) => MobilePermitItem.fromJson(asMap(e)))
            .toList(growable: false),
      );

  final String month;
  final int maxPermits;
  final int maxHours;
  final int usedApproved;
  final int usedPending;
  final int totalUsed;
  final int remainingPermits;
  final int remainingHours;
  final int minutesPerPermit;
  final bool hasRemaining;
  final List<MobilePermitItem> items;
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
        id: asString(json['id']),
        category: asString(json['category'], 'other'),
        title: asString(json['title'], ''),
        status: asString(json['status'], 'pending'),
        dueAt: optDate(json['dueAt']),
        completionNote: asNullableString(json['completionNote']),
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
            : asMap(json['case']),
        clearance: asList(json['clearance'])
            .map(
              (e) => MobileClearanceItem.fromJson(
                asMap(e),
              ),
            )
            .toList(growable: false),
        assignedAssets: asList(json['assignedAssets'])
            .map((e) => asMap(e))
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
        id: asString(json['id']),
        courseId: asString(json['courseId']),
        title: asString(json['title'], ''),
        category: asString(json['category'], 'عام'),
        deliveryMode: asString(json['deliveryMode'], 'online'),
        durationMinutes: asInt(json['durationMinutes'], 0),
        mandatory: asBool(json['mandatory'], false),
        status: asString(json['status'], 'enrolled'),
        progress: asInt(json['progress'], 0),
        score: asNullableDouble(json['score']),
        completedAt: optDate(json['completedAt']),
        expiresAt: optDate(json['expiresAt']),
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

/// مقالة معرفة منشورة (0352) — قراءة فقط على الموبايل.
/// الحقول snake_case لأن الـ RPC يبني الصفوف بـ row_to_json.
class KnowledgeArticle {
  const KnowledgeArticle({
    required this.id,
    required this.title,
    required this.category,
    required this.categoryName,
    required this.body,
    this.updatedAt,
  });

  factory KnowledgeArticle.fromJson(Map<String, dynamic> json) =>
      KnowledgeArticle(
        id: asString(json['id']),
        title: asString(json['title'], ''),
        category: asString(json['category'], ''),
        categoryName: asString(json['category_name'], ''),
        body: asString(json['body'], ''),
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.tryParse(json['updated_at'].toString()),
      );

  final String id;
  final String title;
  final String category;
  final String categoryName;
  final String body;
  final DateTime? updatedAt;
}

/// تصنيف معرفة (0352).
class KnowledgeCategory {
  const KnowledgeCategory({required this.id, required this.name});

  factory KnowledgeCategory.fromJson(Map<String, dynamic> json) =>
      KnowledgeCategory(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );

  final String id;
  final String name;
}

class MobileLearningCatalog {
  const MobileLearningCatalog({
    required this.items,
    required this.lastUpdatedAt,
  });
  factory MobileLearningCatalog.fromJson(Map<String, dynamic> json) =>
      MobileLearningCatalog(
        items: asList(json['items'])
            .map(
              (item) => MobileLearningItem.fromJson(
                asMap(item),
              ),
            )
            .toList(growable: false),
        lastUpdatedAt: optDate(json['lastUpdatedAt']),
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
        id: asString(json['id']),
        code: asString(json['code'], ''),
        name: asString(json['name'], ''),
        description: asNullableString(json['description']),
        category: asString(json['category'], 'عام'),
        slaHours: asInt(json['slaHours'], 24),
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
        id: asString(json['id']),
        number: asInt(json['number'], 0),
        serviceName: asString(json['serviceName'], ''),
        title: asString(json['title'], ''),
        description: asNullableString(json['description']),
        priority: asString(json['priority'], 'normal'),
        status: asString(json['status'], 'submitted'),
        dueAt: optDate(json['dueAt']),
        createdAt: reqDate(json['createdAt']),
        satisfactionScore: asNullableInt(json['satisfactionScore']),
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
        catalog: asList(json['catalog'])
            .map(
              (e) => MobileServiceCatalogItem.fromJson(
                asMap(e),
              ),
            )
            .toList(growable: false),
        requests: asList(json['requests'])
            .map(
              (e) => MobileServiceRequest.fromJson(
                asMap(e),
              ),
            )
            .toList(growable: false),
        lastUpdatedAt: optDate(json['lastUpdatedAt']),
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
        id: asString(json['id']),
        code: asString(json['code'], ''),
        name: asString(json['name'], ''),
        lineType: asString(json['lineType'], 'earning'),
        amount: asDouble(json['amount'], 0),
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
    id: asString(json['id']),
    periodMonth: reqDate(json['periodMonth']),
    currency: asString(json['currency'], 'EGP'),
    grossAmount: asDouble(json['grossAmount'], 0),
    deductionAmount: asDouble(json['deductionAmount'], 0),
    netAmount: asDouble(json['netAmount'], 0),
    status: asString(json['status'], 'issued'),
    issuedAt: optDate(json['issuedAt']),
    paidAt: optDate(json['paidAt']),
    storagePath: asNullableString(json['storagePath']),
    lines: asList(json['lines'])
        .map(
          (e) => MobilePayslipLine.fromJson(
            asMap(e),
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

/// نموذج بيانات الموظف في لوحة الشرف ومنصة التتويج الشرفية
class HonoreeItem {
  const HonoreeItem({
    required this.rank,
    required this.name,
    required this.department,
    required this.achievement,
    required this.metric,
    this.photoUrl,
  });

  factory HonoreeItem.fromJson(Map<String, dynamic> json) => HonoreeItem(
        rank: asInt(json['rank'], 1),
        name: asString(json['name'], asNullableString(json['full_name_ar']) ?? ''),
        department: asString(json['department'], ''),
        achievement: asString(json['achievement'], ''),
        metric: asString(json['metric'], (json['score'] != null ? '${json['score']}% انضباط' : '')),
        photoUrl: asNullableString(json['photo_url']),
      );

  final int rank;
  final String name;
  final String department;
  final String achievement;
  final String metric;
  final String? photoUrl;
}
