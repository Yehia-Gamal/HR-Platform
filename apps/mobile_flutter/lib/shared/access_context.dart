enum WorkspaceId {
  employee,
  manager,
  executive,
  hr,
  mainAdmin,
  committee,
  fieldOperations;

  static WorkspaceId fromWire(String value) => switch (value) {
    'employee' => WorkspaceId.employee,
    'manager' => WorkspaceId.manager,
    'executive' => WorkspaceId.executive,
    'hr' => WorkspaceId.hr,
    'main_admin' => WorkspaceId.mainAdmin,
    'committee' => WorkspaceId.committee,
    'field_operations' => WorkspaceId.fieldOperations,
    _ => throw FormatException('Unknown workspace: $value'),
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
  });

  factory AccessContext.fromJson(Map<String, dynamic> json) {
    return AccessContext(
      userId: json['userId'] as String,
      employeeId: json['employeeId'] as String?,
      displayName: json['displayName'] as String,
      employeeCode: json['employeeCode'] as String?,
      photoUrl: json['photoUrl'] as String?,
      roles: List<String>.from(json['roles'] as List<dynamic>? ?? const []),
      permissions: List<String>.from(
        json['permissions'] as List<dynamic>? ?? const [],
      ),
      workspaces: (json['workspaces'] as List<dynamic>? ?? const [])
          .map((value) => WorkspaceId.fromWire(value as String))
          .toList(growable: false),
      defaultWorkspace: WorkspaceId.fromWire(
        json['defaultWorkspace'] as String,
      ),
      attendancePolicy: AttendancePolicy.fromJson(
        Map<String, dynamic>.from(
          json['attendancePolicy'] as Map<dynamic, dynamic>,
        ),
      ),
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

  bool hasPermission(String code) =>
      permissions.contains('*') || permissions.contains(code);

  bool hasAnyPermission(Iterable<String> codes) =>
      permissions.contains('*') || codes.any(permissions.contains);
}
