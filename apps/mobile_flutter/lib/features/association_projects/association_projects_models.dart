// نماذج مشاريع الجمعية (0553 + فريق المشروع 0645) — مطابقة لعقد الويب في
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

/// صفة المستخدم في المشروع (0645).
const projectRoleLabels = {
  'leader': 'أنت قائد هذا المشروع',
  'member': 'أنت عضو في فريق المشروع',
  'dept_manager': 'إدارتك مسؤولة عن المشروع (بصفتك مديرها)',
  'dept_staff': 'إدارتك مسؤولة عن المشروع',
  'creator': 'أنشأت هذا المشروع',
};

/// عضو في فريق المشروع — واحد فقط قائد.
class ProjectMember {
  const ProjectMember({
    required this.employeeId,
    required this.name,
    required this.jobTitle,
    required this.departmentName,
    required this.isLeader,
  });

  factory ProjectMember.fromJson(Map<String, dynamic> j) => ProjectMember(
        employeeId: _str(j['employeeId']),
        name: _str(j['name']),
        jobTitle: _strOrNull(j['jobTitle']),
        departmentName: _strOrNull(j['departmentName']),
        isLeader: _bool(j['isLeader']),
      );

  final String employeeId;
  final String name;
  final String? jobTitle;
  final String? departmentName;
  final bool isLeader;

  String get subtitle =>
      isLeader ? 'قائد المشروع' : [jobTitle, departmentName].whereType<String>().join(' • ');
}

class ProjectDepartment {
  const ProjectDepartment({required this.id, required this.name});

  factory ProjectDepartment.fromJson(Map<String, dynamic> j) =>
      ProjectDepartment(id: _str(j['id']), name: _str(j['name']));

  final String id;
  final String name;
}

class AssociationProject {
  const AssociationProject({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.departmentId,
    required this.departmentName,
    required this.departments,
    required this.ownerId,
    required this.ownerName,
    required this.leaderName,
    required this.members,
    required this.myRole,
    required this.canEdit,
    required this.status,
    required this.approvalStatus,
    required this.priority,
    required this.progress,
    required this.startDate,
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
        departmentId: _strOrNull(j['departmentId']),
        departmentName: _str(j['departmentName']),
        departments: _list(j['departments']).map(ProjectDepartment.fromJson).toList(growable: false),
        ownerId: _str(j['leaderId'] ?? j['ownerId']),
        ownerName: _str(j['ownerName']),
        leaderName: _str(j['leaderName'] ?? j['ownerName']),
        members: _list(j['members']).map(ProjectMember.fromJson).toList(growable: false),
        myRole: _strOrNull(j['myRole']),
        canEdit: _bool(j['canEdit']),
        status: _str(j['status'], 'planned'),
        approvalStatus: _str(j['approvalStatus'], 'draft'),
        priority: _str(j['priority'], 'medium'),
        progress: _double(j['progress']),
        startDate: _date(j['startDate']),
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
  final String? departmentId;

  /// أسماء الإدارات المرتبطة مفصولة بـ«، » — فارغ لمشروع فريق بلا إدارة.
  final String departmentName;
  final List<ProjectDepartment> departments;

  /// القائد (owner = leader للتوافق مع ما قبل 0645).
  final String ownerId;
  final String ownerName;
  final String leaderName;
  final List<ProjectMember> members;
  final String? myRole;
  final bool canEdit;
  final String status;
  final String approvalStatus;
  final String priority;
  final double progress;
  final DateTime? startDate;
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
  bool get isMine => myRole == 'leader' || myRole == 'member';

  /// الفريق كما يُعرض — استجابة ما قبل 0645 بلا أعضاء: القائد وحده.
  List<ProjectMember> get team => members.isNotEmpty
      ? members
      : [ProjectMember(employeeId: ownerId, name: leaderName, jobTitle: null, departmentName: null, isLeader: true)];

  /// «إدارة الإعلام» أو «فريق من 4» لمشروع بلا إدارة.
  String get scopeLabel => departmentName.isNotEmpty ? departmentName : 'فريق من ${team.length}';

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
    required this.assigneeId,
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
        assigneeId: _strOrNull(j['assigneeId']),
        assigneeName: _strOrNull(j['assigneeName']),
        completedAt: _date(j['completedAt']),
      );

  final String id;
  final String title;
  final String? description;
  final int sortOrder;
  final String status;
  final DateTime? dueDate;
  final String? assigneeId;
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
    required this.canEdit,
    required this.canEditCore,
    required this.canEditTeam,
    required this.canSubmit,
    required this.canUpdate,
    required this.canDelete,
  });

  /// قبل نشر 0553/0645 لا تصل الصلاحيات كاملة — تُشتق بنفس قاعدة الخادم.
  factory AssociationProjectPermissions.fromJson(Object? raw, AssociationProject p, bool isFullAccess) {
    if (raw is Map) {
      final canEdit = _bool(raw['canEdit']);
      return AssociationProjectPermissions(
        canManage: _bool(raw['canManage']),
        canApprove: _bool(raw['canApprove']),
        canEdit: canEdit,
        canEditCore: raw.containsKey('canEditCore') ? _bool(raw['canEditCore']) : canEdit,
        canEditTeam: raw.containsKey('canEditTeam') ? _bool(raw['canEditTeam']) : canEdit,
        canSubmit: _bool(raw['canSubmit']),
        canUpdate: _bool(raw['canUpdate']),
        canDelete: _bool(raw['canDelete']),
      );
    }
    final canEdit = isFullAccess || (p.canEdit && p.isEditableDraft);
    return AssociationProjectPermissions(
      canManage: isFullAccess || p.canManage,
      canApprove: isFullAccess && p.approvalStatus == 'pending_approval',
      canEdit: canEdit,
      canEditCore: canEdit,
      canEditTeam: canEdit,
      canSubmit: p.isEditableDraft,
      canUpdate: p.isApproved,
      canDelete: isFullAccess || p.isEditableDraft,
    );
  }

  final bool canManage;
  final bool canApprove;
  final bool canEdit;

  /// الاسم والوصف — يُقفلان بعد الإرسال للاعتماد لغير المدير التنفيذي.
  final bool canEditCore;

  /// القائد والأعضاء والإدارات والأولوية والمواعيد.
  final bool canEditTeam;
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
    required this.myEmployeeId,
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
      myEmployeeId: _strOrNull(j['myEmployeeId']),
      warningDays: _intOrNull(settings['warningDays']) ?? 7,
      criticalDays: _intOrNull(settings['criticalDays']) ?? 14,
    );
  }

  final List<AssociationProject> projects;
  final bool isFullAccess;
  final bool canCreate;
  final String? myDepartmentId;
  final String? myEmployeeId;
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

/// موظف في قائمة اختيار الفريق (get_association_project_pickers).
class PickerEmployee {
  const PickerEmployee({
    required this.id,
    required this.name,
    required this.jobTitle,
    required this.departmentId,
    required this.departmentName,
  });

  factory PickerEmployee.fromJson(Map<String, dynamic> j) => PickerEmployee(
        id: _str(j['id']),
        name: _str(j['name']),
        jobTitle: _strOrNull(j['jobTitle']),
        departmentId: _strOrNull(j['departmentId']),
        departmentName: _strOrNull(j['departmentName']),
      );

  final String id;
  final String name;
  final String? jobTitle;
  final String? departmentId;
  final String? departmentName;

  String get subtitle => [jobTitle, departmentName].whereType<String>().join(' • ');
}

class ProjectPickers {
  const ProjectPickers({required this.employees, required this.departments});

  factory ProjectPickers.fromJson(Object? raw) {
    final j = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return ProjectPickers(
      employees: _list(j['employees']).map(PickerEmployee.fromJson).toList(growable: false),
      departments: _list(j['departments']).map(ProjectDepartment.fromJson).toList(growable: false),
    );
  }

  final List<PickerEmployee> employees;
  final List<ProjectDepartment> departments;

  PickerEmployee? byId(String id) {
    for (final e in employees) {
      if (e.id == id) return e;
    }
    return null;
  }
}

/// تطبيع بسيط للبحث بالعربية (همزات/تاء مربوطة/ياء/تشكيل).
String normalizeArabic(String text) => text
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp('[ً-ْ]'), '')
    .toLowerCase()
    .trim();

/// «منذ 3 أيام» — لآخر نشاط.
String daysAgoLabel(int? days) {
  if (days == null) return 'لا يوجد نشاط بعد';
  if (days <= 0) return 'اليوم';
  if (days == 1) return 'أمس';
  if (days == 2) return 'منذ يومين';
  if (days <= 10) return 'منذ $days أيام';
  return 'منذ $days يوماً';
}
