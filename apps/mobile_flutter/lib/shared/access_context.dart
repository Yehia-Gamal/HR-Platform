enum WorkspaceId {
  employee,
  manager,
  executive,
  hr,
  mainAdmin,
  committee,
  fieldOperations;

  static WorkspaceId? fromWire(String value) => switch (value) {
    'employee' => WorkspaceId.employee,
    'manager' => WorkspaceId.manager,
    'executive' => WorkspaceId.executive,
    'hr' => WorkspaceId.hr,
    'main_admin' => WorkspaceId.mainAdmin,
    'committee' => WorkspaceId.committee,
    'field_operations' => WorkspaceId.fieldOperations,
    _ => null,
  };
}

class AttendancePolicy {
  const AttendancePolicy({
    required this.attendanceRequired,
    required this.selfPunchEnabled,
    required this.liveLocationResponseEnabled,
  });

  factory AttendancePolicy.fromJson(Map<String, dynamic> json) {
    return AttendancePolicy(
      attendanceRequired: json['attendanceRequired'] as bool? ?? false,
      selfPunchEnabled: json['selfPunchEnabled'] as bool? ?? false,
      liveLocationResponseEnabled:
          json['liveLocationResponseEnabled'] as bool? ?? false,
    );
  }

  final bool attendanceRequired;
  final bool selfPunchEnabled;
  final bool liveLocationResponseEnabled;
}

class AccessContext {
  const AccessContext({
    required this.userId,
    required this.employeeId,
    required this.displayName,
    required this.employeeCode,
    this.photoUrl,
    required this.roles,
    required this.permissions,
    required this.workspaces,
    required this.defaultWorkspace,
    required this.attendancePolicy,
    this.status = 'active',
    this.isSuspended = false,
    this.suspensionReason,
    this.suspensionMessage,
    this.suspensionAmount,
    this.isClinicStaff = false,
  });

  factory AccessContext.fromJson(Map<String, dynamic> json) {
    final defaultWorkspaceRaw = json['defaultWorkspace'];
    final isSuspendedVal = (json['isSuspended'] as bool? ?? false) ||
        json['status'] == 'suspended' ||
        (json['suspensionReason'] != null &&
            json['suspensionReason'].toString().trim().isNotEmpty);

    final rolesList = List<String>.from(json['roles'] as List<dynamic>? ?? const []);
    final isClinic = (json['isClinicStaff'] as bool? ?? false) ||
        (rolesList.contains('clinic-staff') && !rolesList.contains('clinics-manager'));

    return AccessContext(
      userId: json['userId'] as String? ?? '',
      employeeId: json['employeeId'] as String?,
      displayName: json['displayName'] as String? ?? '',
      employeeCode: json['employeeCode'] as String?,
      photoUrl: json['photoUrl'] as String?,
      roles: rolesList,
      permissions: List<String>.from(
        json['permissions'] as List<dynamic>? ?? const [],
      ),
      workspaces: (json['workspaces'] as List<dynamic>? ?? const [])
          .map((value) => WorkspaceId.fromWire(value as String))
          .whereType<WorkspaceId>()
          .toList(growable: false),
      defaultWorkspace: defaultWorkspaceRaw == null
          ? WorkspaceId.employee
          : WorkspaceId.fromWire(defaultWorkspaceRaw as String) ??
              WorkspaceId.employee,
      attendancePolicy: AttendancePolicy.fromJson(
        Map<String, dynamic>.from(
          json['attendancePolicy'] as Map<dynamic, dynamic>? ?? const {},
        ),
      ),
      status: json['status'] as String? ?? (isSuspendedVal ? 'suspended' : 'active'),
      isSuspended: isSuspendedVal,
      suspensionReason: json['suspensionReason'] as String?,
      suspensionMessage: json['suspensionMessage'] as String?,
      suspensionAmount: (json['suspensionAmount'] as num?)?.toDouble(),
      isClinicStaff: isClinic,
    );
  }

  final String userId;
  final String? employeeId;
  final String displayName;
  final String? employeeCode;
  final String? photoUrl;
  final List<String> roles;
  final List<String> permissions;
  final List<WorkspaceId> workspaces;
  final WorkspaceId defaultWorkspace;
  final AttendancePolicy attendancePolicy;
  final String status;
  final bool isSuspended;
  final String? suspensionReason;
  final String? suspensionMessage;
  final double? suspensionAmount;
  final bool isClinicStaff;

  bool get isSuspendedAccount =>
      isSuspended ||
      status == 'suspended' ||
      (suspensionReason != null && suspensionReason!.trim().isNotEmpty);

  bool hasPermission(String code) =>
      permissions.contains('*') || permissions.contains(code);

  bool hasAnyPermission(Iterable<String> codes) =>
      permissions.contains('*') || codes.any(permissions.contains);

  /// أسماء الأدوار بالعربية للعرض، بلا تكرار ومرتبة من الأعلى — [roles]
  /// تحمل المعرّفات اللاتينية (executive-director…) التي لا تُعرض للمستخدم.
  List<String> get roleLabels {
    final labels = <String>{};
    for (final entry in _roleLabelsAr.entries) {
      if (roles.contains(entry.key)) labels.add(entry.value);
    }
    return labels.toList(growable: false);
  }
}

/// مطابقة لـ roles.name_ar في قاعدة البيانات، بترتيب الأولوية في العرض.
const _roleLabelsAr = <String, String>{
  'executive-director': 'المدير التنفيذي',
  'executive': 'المدير التنفيذي',
  'executive-secretary': 'السكرتير التنفيذي',
  'admin': 'مدير النظام',
  'system-admin': 'مسؤول تقني',
  'hr-manager': 'مدير الموارد البشرية',
  'operations-manager': 'مدير العمليات',
  'operations-manager-1': 'مدير التشغيل 1',
  'operations-manager-2': 'مدير التشغيل 2',
  'department-manager': 'مدير إدارة',
  'clinics-manager': 'مسؤول العيادات',
  'direct-manager': 'مدير مباشر',
  'hr-specialist': 'أخصائي موارد بشرية',
  'operations-officer': 'ضابط عمليات',
  'clinic-staff': 'موظف عيادات',
  'employee': 'موظف',
  'committee-chair': 'رئيس لجنة',
  'committee-secretary': 'مقرر لجنة حل المشكلات',
  'committee-member': 'عضو لجنة',
};
