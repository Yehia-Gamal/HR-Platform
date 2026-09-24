// نماذج مشاريع الجمعية (0553) — مطابقة لعقد الويب في
// packages/shared-contracts/src/associationProjects.ts.

String _str(Object? v, [String fallback = '']) => v == null ? fallback : v.toString();
String? _strOrNull(Object? v) => v == null || v.toString().isEmpty ? null : v.toString();
int _int(Object? v) => v is num ? v.toInt() : int.tryParse(_str(v)) ?? 0;
int? _intOrNull(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
double _double(Object? v) => v is num ? v.toDouble() : double.tryParse(_str(v)) ?? 0;
bool _bool(Object? v) => v == true;
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
List<Map<String, dynamic>> _list(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

/// لمبة حالة المشروع: active أخضر، halted أحمر ثابت، critical أحمر يومض.
enum ProjectLed {
  active('يعمل بانتظام'),
  halted('متوقف'),
  critical('يحتاج تدخل'),
  completed('مكتمل'),
  stale('ملغى'),
  pending('بانتظار الاعتماد'),
  rejected('أُعيد للتعديل'),
  draft('مسودة');

  const ProjectLed(this.label);
  final String label;

  static ProjectLed parse(Object? v) =>
      ProjectLed.values.firstWhere((e) => e.name == v, orElse: () => ProjectLed.stale);

  /// ترتيب «الأحوج للمتابعة أولاً».
  int get urgency => switch (this) {
        critical => 0,
        halted => 1,
        active => 2,
        pending => 3,
        rejected => 4,
        draft => 5,
        completed => 6,
        stale => 7,
      };
}

const projectStatusLabels = {
  'planned': 'لم يبدأ',
  'active': 'قيد التنفيذ',
  'on_hold': 'متوقف',
  'completed': 'مكتمل',
  'cancelled': 'ملغى',
};

const projectPriorityLabels = {
  'low': 'منخفضة',
  'medium': 'متوسطة',
  'high': 'عالية',
  'critical': 'حرجة',
};

const stepStatusLabels = {
  'pending': 'لم تبدأ',
  'in_progress': 'جارية',
  'done': 'تمت',
  'blocked': 'متعثرة',
};

const approvalLabels = {
  'draft': 'مسودة',
  'pending_approval': 'بانتظار الاعتماد',
  'approved': 'معتمد',
  'rejected': 'أُعيد للتعديل',
};

class AssociationProject {
  const AssociationProject({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.departmentId,
    required this.departmentName,
    required this.ownerName,
    required this.status,
    required this.approvalStatus,
    required this.priority,
    required this.progress,
    required this.targetEndDate,
    required this.lastActivityAt,
    required this.daysSinceActivity,
    required this.rejectionReason,
    required this.totalSteps,
    required this.completedSteps,
    required this.blockedSteps,
    required this.overdueSteps,
    required this.currentStepTitle,
    required this.isOverdue,
    required this.canManage,
    required this.led,
  });

  factory AssociationProject.fromJson(Map<String, dynamic> j) => AssociationProject(
        id: _str(j['id']),
        code: _str(j['code']),
        name: _str(j['name']),
        description: _strOrNull(j['description']),
        departmentId: _str(j['departmentId']),
        departmentName: _str(j['departmentName']),
        ownerName: _str(j['ownerName']),
        status: _str(j['status'], 'planned'),
        approvalStatus: _str(j['approvalStatus'], 'draft'),
        priority: _str(j['priority'], 'medium'),
        progress: _double(j['progress']),
        targetEndDate: _date(j['targetEndDate']),
        lastActivityAt: _date(j['lastActivityAt'] ?? j['lastUpdateAt']),
        daysSinceActivity: _intOrNull(j['daysSinceActivity']),
        rejectionReason: _strOrNull(j['rejectionReason']),
        totalSteps: _int(j['totalSteps']),
        completedSteps: _int(j['completedSteps']),
        blockedSteps: _int(j['blockedSteps']),
        overdueSteps: _int(j['overdueSteps']),
        currentStepTitle: _strOrNull(j['currentStepTitle']),
        isOverdue: _bool(j['isOverdue']),
        canManage: _bool(j['canManage']),
        led: ProjectLed.parse(j['ledStatus']),
      );

  final String id;
  final String code;
  final String name;
  final String? description;
  final String departmentId;
  final String departmentName;
  final String ownerName;
  final String status;
  final String approvalStatus;
  final String priority;
  final double progress;
  final DateTime? targetEndDate;
  final DateTime? lastActivityAt;
  final int? daysSinceActivity;
  final String? rejectionReason;
  final int totalSteps;
  final int completedSteps;
  final int blockedSteps;
  final int overdueSteps;
  final String? currentStepTitle;
  final bool isOverdue;
  final bool canManage;
  final ProjectLed led;

  bool get isApproved => approvalStatus == 'approved';
  bool get isEditableDraft => approvalStatus == 'draft' || approvalStatus == 'rejected';
  bool get isClosed => status == 'completed' || status == 'cancelled';

  int? get activityDays =>
      daysSinceActivity ?? (lastActivityAt == null ? null : DateTime.now().difference(lastActivityAt!).inDays);
}

class AssociationProjectStep {
  const AssociationProjectStep({
    required this.id,
    required this.title,
    required this.description,
    required this.sortOrder,
    required this.status,
    required this.dueDate,
    required this.assigneeName,
    required this.completedAt,
  });

  factory AssociationProjectStep.fromJson(Map<String, dynamic> j) => AssociationProjectStep(
        id: _str(j['id']),
        title: _str(j['title']),
        description: _strOrNull(j['description']),
        sortOrder: _int(j['sortOrder']),
        status: _str(j['status'], 'pending'),
        dueDate: _date(j['dueDate']),
        assigneeName: _strOrNull(j['assigneeName']),
        completedAt: _date(j['completedAt']),
      );

  final String id;
  final String title;
  final String? description;
  final int sortOrder;
  final String status;
  final DateTime? dueDate;
  final String? assigneeName;
  final DateTime? completedAt;

  bool get isDone => status == 'done';

  bool get isOverdue {
    if (isDone || dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.isBefore(DateTime(now.year, now.month, now.day));
  }
}

class AssociationProjectUpdate {
  const AssociationProjectUpdate({
    required this.id,
    required this.note,
    required this.statusChange,
    required this.authorName,
    required this.createdAt,
  });

  factory AssociationProjectUpdate.fromJson(Map<String, dynamic> j) => AssociationProjectUpdate(
        id: _str(j['id']),
        note: _str(j['note']),
        statusChange: _strOrNull(j['statusChange']),
        authorName: _str(j['authorName']),
        createdAt: _date(j['createdAt']),
      );

  final String id;
  final String note;
  final String? statusChange;
  final String authorName;
  final DateTime? createdAt;
}

class AssociationProjectPermissions {
  const AssociationProjectPermissions({
    required this.canManage,
    required this.canApprove,
    required this.canSubmit,
    required this.canUpdate,
    required this.canDelete,
  });

  /// قبل نشر 0553 لا تصل الصلاحيات — تُشتق بنفس قاعدة الخادم.
  factory AssociationProjectPermissions.fromJson(Object? raw, AssociationProject p, bool isFullAccess) {
    if (raw is Map) {
      return AssociationProjectPermissions(
        canManage: _bool(raw['canManage']),
        canApprove: _bool(raw['canApprove']),
        canSubmit: _bool(raw['canSubmit']),
        canUpdate: _bool(raw['canUpdate']),
        canDelete: _bool(raw['canDelete']),
      );
    }
    return AssociationProjectPermissions(
      canManage: isFullAccess || p.canManage,
      canApprove: isFullAccess && p.approvalStatus == 'pending_approval',
      canSubmit: p.isEditableDraft,
      canUpdate: p.isApproved,
      canDelete: isFullAccess || p.isEditableDraft,
    );
  }

  final bool canManage;
  final bool canApprove;
  final bool canSubmit;
  final bool canUpdate;
  final bool canDelete;
}

class AssociationProjectDetail {
  const AssociationProjectDetail({
    required this.project,
    required this.steps,
    required this.updates,
    required this.permissions,
  });

  factory AssociationProjectDetail.fromJson(Map<String, dynamic> j, {required bool isFullAccess}) {
    final project = AssociationProject.fromJson(Map<String, dynamic>.from(j['project'] as Map));
    return AssociationProjectDetail(
      project: project,
      steps: _list(j['steps']).map(AssociationProjectStep.fromJson).toList(growable: false),
      updates: _list(j['updates']).map(AssociationProjectUpdate.fromJson).toList(growable: false),
      permissions: AssociationProjectPermissions.fromJson(j['permissions'], project, isFullAccess),
    );
  }

  final AssociationProject project;
  final List<AssociationProjectStep> steps;
  final List<AssociationProjectUpdate> updates;
  final AssociationProjectPermissions permissions;

  AssociationProjectStep? get currentStep {
    for (final s in steps) {
      if (!s.isDone) return s;
    }
    return null;
  }
}

class AssociationProjectsCatalog {
  const AssociationProjectsCatalog({
    required this.projects,
    required this.isFullAccess,
    required this.canCreate,
    required this.myDepartmentId,
    required this.warningDays,
    required this.criticalDays,
  });

  factory AssociationProjectsCatalog.fromJson(Object? raw) {
    final j = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final settings = j['settings'] is Map ? Map<String, dynamic>.from(j['settings'] as Map) : const <String, dynamic>{};
    return AssociationProjectsCatalog(
      projects: _list(j['projects']).map(AssociationProject.fromJson).toList(growable: false),
      isFullAccess: _bool(j['isFullAccess']),
      canCreate: j['canCreate'] != false,
      myDepartmentId: _strOrNull(j['myDepartmentId']),
      warningDays: _intOrNull(settings['warningDays']) ?? 7,
      criticalDays: _intOrNull(settings['criticalDays']) ?? 14,
    );
  }

  final List<AssociationProject> projects;
  final bool isFullAccess;
  final bool canCreate;
  final String? myDepartmentId;
  final int warningDays;
  final int criticalDays;

  List<AssociationProject> get board =>
      projects.where((p) => p.isApproved).toList()..sort(_byUrgency);

  List<AssociationProject> get requests =>
      projects.where((p) => !p.isApproved).toList()..sort(_byUrgency);

  static int _byUrgency(AssociationProject a, AssociationProject b) {
    final c = a.led.urgency.compareTo(b.led.urgency);
    if (c != 0) return c;
    return (b.activityDays ?? 9999).compareTo(a.activityDays ?? 9999);
  }
}

/// «منذ 3 أيام» — لآخر نشاط.
String daysAgoLabel(int? days) {
  if (days == null) return 'لا يوجد نشاط بعد';
  if (days <= 0) return 'اليوم';
  if (days == 1) return 'أمس';
  if (days == 2) return 'منذ يومين';
  if (days <= 10) return 'منذ $days أيام';
  return 'منذ $days يوماً';
}
