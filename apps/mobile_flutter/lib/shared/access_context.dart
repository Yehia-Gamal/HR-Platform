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
    this.isSuspended = false,
    this.suspensionReason,
    this.suspensionMessage,
    this.suspensionAmount,
  });

  factory AccessContext.fromJson(Map<String, dynamic> json) {
    final defaultWorkspaceRaw = json['defaultWorkspace'];
    return AccessContext(
      userId: json['userId'] as String? ?? '',
      employeeId: json['employeeId'] as String?,
      displayName: json['displayName'] as String? ?? '',
      employeeCode: json['employeeCode'] as String?,
      photoUrl: json['photoUrl'] as String?,
      roles: List<String>.from(json['roles'] as List<dynamic>? ?? const []),
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
      isSuspended: json['isSuspended'] as bool? ?? false,
      suspensionReason: json['suspensionReason'] as String?,
      suspensionMessage: json['suspensionMessage'] as String?,
      suspensionAmount: (json['suspensionAmount'] as num?)?.toDouble(),
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
  final bool isSuspended;
  final String? suspensionReason;
  final String? suspensionMessage;
  final double? suspensionAmount;

  bool hasPermission(String code) =>
      permissions.contains('*') || permissions.contains(code);

  bool hasAnyPermission(Iterable<String> codes) =>
      permissions.contains('*') || codes.any(permissions.contains);
}
