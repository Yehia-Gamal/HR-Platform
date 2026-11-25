import 'package:ahla_shabab_management_os/features/mobile_data/models/json_parse.dart';

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
        id: asString(json['id']),
        type: asString(json['type'], 'other'),
        title: asString(json['title'], 'مستند'),
        expiryDate: optDate(json['expiryDate']),
        status: asString(json['status'], 'active'),
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
        id: asString(json['id']),
        assetName: asString(json['assetName'], 'عهدة'),
        assetType: asString(json['assetType'], 'other'),
        serial: asNullableString(json['serial']),
        assignedAt: optDate(json['assignedAt']),
        returnedAt: optDate(json['returnedAt']),
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
    id: asString(json['id']),
    employeeCode: asString(json['employeeCode'], ''),
    fullNameAr: asString(json['fullNameAr'], 'موظف'),
    fullNameEn: asNullableString(json['fullNameEn']),
    phoneE164: asNullableString(json['phoneE164']),
    photoUrl: asNullableString(json['photoUrl']),
    status: asString(json['status'], 'active'),
    hireDate: optDate(json['hireDate']),
    contractEnd: optDate(json['contractEnd']),
    jobTitle: asNullableString(json['jobTitle']),
    position: asNullableString(json['position']),
    grade: asNullableString(json['grade']),
    department: asNullableString(json['department']),
    team: asNullableString(json['team']),
    branch: asNullableString(json['branch']),
    workSite: asNullableString(json['workSite']),
    managerName: asNullableString(json['managerName']),
    documents: asList(json['documents'])
        .map(
          (item) => MobileDocumentSummary.fromJson(
            asMap(item),
          ),
        )
        .toList(growable: false),
    assets: asList(json['assets'])
        .map(
          (item) => MobileAssetSummary.fromJson(
            asMap(item),
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
    this.statusLabel,
    this.activityTitle,
    required this.lateMinutes,
    required this.firstCheckIn,
    required this.pendingRequests,
    required this.kpiStage,
    this.workMinutes = 0,
    this.overtimeMinutes = 0,
  });
  factory MobileTeamMember.fromJson(Map<String, dynamic> json) =>
      MobileTeamMember(
        id: asString(json['id']),
        employeeCode: asNullableString(json['employeeCode']),
        name: asString(json['name'], 'موظف'),
        photoUrl: asNullableString(json['photoUrl']),
        jobTitle: asNullableString(json['jobTitle']),
        department: asNullableString(json['department']),
        team: asNullableString(json['team']),
        attendanceStatus: asNullableString(json['attendanceStatus']),
        statusLabel: asNullableString(json['statusLabel']),
        activityTitle: asNullableString(json['activityTitle']),
        lateMinutes: asInt(json['lateMinutes'], 0),
        firstCheckIn: optDate(json['firstCheckIn']),
        pendingRequests: asInt(json['pendingRequests'], 0),
        kpiStage: asNullableString(json['kpiStage']),
        workMinutes: asInt(json['workMinutes'], 0),
        overtimeMinutes: asInt(json['overtimeMinutes'], 0),
      );
  final String id;
  final String? employeeCode;
  final String name;
  final String? photoUrl;
  final String? jobTitle;
  final String? department;
  final String? team;
  final String? attendanceStatus;
  final String? statusLabel;
  final String? activityTitle;
  final int lateMinutes;
  final DateTime? firstCheckIn;
  final int pendingRequests;
  final String? kpiStage;
  final int workMinutes;
  final int overtimeMinutes;
}

/// ملخص موظف من دليل الموظفين الإداري — get_employees_enriched (إدارة الموظفين).
class MobileEmployeeSummary {
  const MobileEmployeeSummary({
    required this.id,
    required this.employeeCode,
    required this.fullNameAr,
    required this.fullNameEn,
    required this.status,
    required this.isActive,
    required this.photoUrl,
    required this.department,
    required this.team,
    required this.branch,
    required this.jobTitle,
    this.statusToday = 'not_recorded',
    this.statusTodayLabel,
    this.activityTitle,
  });

  factory MobileEmployeeSummary.fromJson(Map<String, dynamic> json) =>
      MobileEmployeeSummary(
        id: asString(json['id']),
        employeeCode: asNullableString(json['employeeCode']),
        fullNameAr: asString(json['fullNameAr'], 'موظف'),
        fullNameEn: asNullableString(json['fullNameEn']),
        status: asString(json['status'], 'active'),
        isActive: asBool(json['isActive'], true),
        photoUrl: asNullableString(json['photoUrl']),
        department: asNullableString(json['department']),
        team: asNullableString(json['team']),
        branch: asNullableString(json['branch']),
        jobTitle: asNullableString(json['jobTitle']),
        statusToday: asString(json['statusToday'], 'not_recorded'),
        statusTodayLabel: asNullableString(json['statusTodayLabel']),
        activityTitle: asNullableString(json['activityTitle']),
      );

  final String id;
  final String? employeeCode;
  final String fullNameAr;
  final String? fullNameEn;
  final String status;
  final bool isActive;
  final String? photoUrl;
  final String? department;
  final String? team;
  final String? branch;
  final String? jobTitle;
  final String statusToday;
  final String? statusTodayLabel;
  final String? activityTitle;
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
        id: asString(json['id']),
        name: asString(json['name'], 'موظف'),
        employeeCode: asNullableString(json['employeeCode']),
        department: asNullableString(json['department']),
      );
  final String id;
  final String name;
  final String? employeeCode;
  final String? department;
}

class DirectoryEmployee {
  const DirectoryEmployee({
    required this.id,
    required this.name,
    this.employeeCode,
    this.photoUrl,
    this.jobTitle,
    this.department,
    this.statusToday = 'not_recorded',
    this.statusTodayLabel,
    this.activityTitle,
  });

  factory DirectoryEmployee.fromJson(Map<String, dynamic> j) =>
      DirectoryEmployee(
        id: asString(j['id']),
        name: asString(j['name'], ''),
        employeeCode: asNullableString(j['employeeCode']),
        photoUrl: asNullableString(j['photoUrl']),
        jobTitle: asNullableString(j['jobTitle']),
        department: asNullableString(j['department']),
        statusToday: asString(j['statusToday'], 'not_recorded'),
        statusTodayLabel: asNullableString(j['statusTodayLabel']),
        activityTitle: asNullableString(j['activityTitle']),
      );

  final String id;
  final String name;
  final String? employeeCode;
  final String? photoUrl;
  final String? jobTitle;
  final String? department;

  /// الحالة العامة اليومية: present | late | absent | mission | convoy | fundraising | on_leave
  final String statusToday;
  final String? statusTodayLabel;
  final String? activityTitle;
}

/// الملف الشامل للموظف (V22 — get_employee_360) — مطابق لـ employee360Schema
/// في shared-contracts. يُستخدم لملفات أعضاء الفريق من جهة المدير.
class Employee360 {
  const Employee360({
    required this.id,
    required this.employeeCode,
    required this.fullNameAr,
    required this.fullNameEn,
    required this.phoneE164,
    required this.photoUrl,
    required this.status,
    required this.isActive,
    required this.hireDate,
    required this.contractEnd,
    required this.probationEnd,
    required this.jobTitle,
    required this.position,
    required this.grade,
    required this.department,
    required this.team,
    required this.branch,
    required this.workSite,
    required this.managerName,
    required this.accountStatus,
    required this.email,
    required this.departments,
    required this.roles,
    required this.directReports,
    this.managerId,
    this.manager,
    this.teamMembers = const [],
    this.viewerScope,
    this.todayStatus,
    required this.attendance30,
    required this.requestCounts,
    required this.latestKpi,
    required this.documents,
    required this.assets,
    required this.recentRequests,
    required this.recentTasks,
    required this.lastUpdatedAt,
  });

  factory Employee360.fromJson(Map<String, dynamic> json) => Employee360(
    id: asString(json['id']),
    employeeCode: asString(json['employeeCode'], ''),
    fullNameAr: asString(json['fullNameAr'], 'موظف'),
    fullNameEn: asNullableString(json['fullNameEn']),
    phoneE164: asNullableString(json['phoneE164']),
    photoUrl: asNullableString(json['photoUrl']),
    status: asString(json['status'], 'active'),
    isActive: (asNullableBool(json['isActive'])) ?? true,
    hireDate: optDate(json['hireDate']),
    contractEnd: optDate(json['contractEnd']),
    probationEnd: optDate(json['probationEnd']),
    jobTitle: asNullableString(json['jobTitle']),
    position: asNullableString(json['position']),
    grade: asNullableString(json['grade']),
    department: asNullableString(json['department']),
    team: asNullableString(json['team']),
    branch: asNullableString(json['branch']),
    workSite: asNullableString(json['workSite']),
    managerName: asNullableString(json['managerName']),
    accountStatus: asNullableString(json['accountStatus']),
    email: asNullableString(json['email']),
    departments: asList(json['departments'])
        .map(
          (e) => EmployeeDepartmentLink.fromJson(
            asMap(e),
          ),
        )
        .toList(growable: false),
    roles: asList(json['roles'])
        .map(
          (e) => EmployeeRoleLink.fromJson(
            asMap(e),
          ),
        )
        .toList(growable: false),
    directReports: asInt(json['directReports'], 0),
    managerId: asNullableString(json['managerId']),
    manager: json['manager'] is Map
        ? Employee360Person.fromJson(
            asMap(json['manager']),
          )
        : null,
    teamMembers: asList(json['teamMembers'])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Employee360Person.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false),
    viewerScope: asNullableString(json['viewerScope']),
    todayStatus: asNullableMap(json['todayStatus']) == null
        ? null
        : Employee360TodayStatus.fromJson(asMap(json['todayStatus'])),
    attendance30: Attendance30Summary.fromJson(asMap(json['attendance30'])),
    requestCounts: RequestCounts.fromJson(asMap(json['requestCounts'])),
    latestKpi: asNullableMap(json['latestKpi']) == null
        ? null
        : KpiLatest.fromJson(asMap(json['latestKpi'])),
    documents: asList(json['documents'])
        .map(
          (e) => EmployeeDocumentBrief.fromJson(
            asMap(e),
          ),
        )
        .toList(growable: false),
    assets: asList(json['assets'])
        .map(
          (e) => EmployeeAssetBrief.fromJson(
            asMap(e),
          ),
        )
        .toList(growable: false),
    recentRequests: asList(json['recentRequests'])
        .map(
          (e) => EmployeeRequestBrief.fromJson(
            asMap(e),
          ),
        )
        .toList(growable: false),
    recentTasks: asList(json['recentTasks'])
        .map(
          (e) => EmployeeTaskBrief.fromJson(
            asMap(e),
          ),
        )
        .toList(growable: false),
    lastUpdatedAt: optDate(json['lastUpdatedAt']),
  );

  final String id;
  final String employeeCode;
  final String fullNameAr;
  final String? fullNameEn;
  final String? phoneE164;
  final String? photoUrl;
  final String status;
  final bool isActive;
  final DateTime? hireDate;
  final DateTime? contractEnd;
  final DateTime? probationEnd;
  final String? jobTitle;
  final String? position;
  final String? grade;
  final String? department;
  final String? team;
  final String? branch;
  final String? workSite;
  final String? managerName;
  final String? accountStatus;
  final String? email;
  final List<EmployeeDepartmentLink> departments;
  final List<EmployeeRoleLink> roles;
  final int directReports;
  final String? managerId;

  /// مديره المباشر (0631) — null لأعلى الهيكل أو مع خادم أقدم.
  final Employee360Person? manager;

  /// فريقه المباشر بأسمائهم وحالة كل منهم اليوم (0631).
  final List<Employee360Person> teamMembers;

  /// full = من يملك قراءة ملفه (هو/مديره/الإدارة/HR)؛ basic = بقية الزملاء.
  /// null = خادم أقدم من 0631.
  final String? viewerScope;
  final Employee360TodayStatus? todayStatus;
  final Attendance30Summary attendance30;
  final RequestCounts requestCounts;
  final KpiLatest? latestKpi;
  final List<EmployeeDocumentBrief> documents;
  final List<EmployeeAssetBrief> assets;
  final List<EmployeeRequestBrief> recentRequests;
  final List<EmployeeTaskBrief> recentTasks;
  final DateTime? lastUpdatedAt;
}

class EmployeeDepartmentLink {
  const EmployeeDepartmentLink({
    required this.id,
    required this.departmentId,
    required this.departmentName,
    required this.jobTitle,
    required this.isPrimary,
    required this.assignedAt,
  });
  factory EmployeeDepartmentLink.fromJson(Map<String, dynamic> j) =>
      EmployeeDepartmentLink(
        id: asString(j['id']),
        departmentId: asString(j['departmentId']),
        departmentName: asString(j['departmentName'], ''),
        jobTitle: asNullableString(j['jobTitle']),
        isPrimary: (asNullableBool(j['isPrimary'])) ?? false,
        assignedAt: reqDate(j['assignedAt']),
      );
  final String id;
  final String departmentId;
  final String departmentName;
  final String? jobTitle;
  final bool isPrimary;
  final DateTime assignedAt;
}

/// شخص في الهيكل الإداري لملف الموظف: مديره المباشر أو أحد أفراد فريقه.
class Employee360Person {
  const Employee360Person({
    required this.id,
    required this.fullNameAr,
    this.jobTitle,
    this.photoUrl,
    this.status,
    this.statusLabel,
    this.activityTitle,
  });

  factory Employee360Person.fromJson(Map<String, dynamic> j) =>
      Employee360Person(
        id: asString(j['id'], ''),
        fullNameAr: asString(j['fullNameAr'], 'موظف'),
        jobTitle: asNullableString(j['jobTitle']),
        photoUrl: asNullableString(j['photoUrl']),
        status: asNullableString(j['status']),
        statusLabel: asNullableString(j['statusLabel']),
        activityTitle: asNullableString(j['activityTitle']),
      );

  final String id;
  final String fullNameAr;
  final String? jobTitle;
  final String? photoUrl;

  /// حالة اليوم (لأفراد الفريق فقط).
  final String? status;
  final String? statusLabel;
  final String? activityTitle;
}

class EmployeeRoleLink {
  const EmployeeRoleLink({required this.slug, required this.name});
  factory EmployeeRoleLink.fromJson(Map<String, dynamic> j) => EmployeeRoleLink(
    slug: asString(j['slug'], ''),
    name: asString(j['name'], ''),
  );
  final String slug;
  final String name;
}

class Employee360TodayStatus {
  const Employee360TodayStatus({
    this.status,
    this.statusLabel,
    this.activityTitle,
    this.requestStatus,
    this.lateMinutes = 0,
    this.checkInAt,
    this.checkOutAt,
    this.workMinutes = 0,
    this.overtimeMinutes = 0,
    this.dueTime,
  });

  factory Employee360TodayStatus.fromJson(Map<String, dynamic> j) =>
      Employee360TodayStatus(
        status: asNullableString(j['status']),
        statusLabel: asNullableString(j['statusLabel']),
        activityTitle: asNullableString(j['activityTitle']),
        requestStatus: asNullableString(j['requestStatus']),
        lateMinutes: asInt(j['lateMinutes'], 0),
        checkInAt: optDate(j['checkInAt']),
        checkOutAt: optDate(j['checkOutAt']),
        workMinutes: asInt(j['workMinutes'], 0),
        overtimeMinutes: asInt(j['overtimeMinutes'], 0),
        dueTime: asNullableString(j['dueTime']),
      );

  /// موعد الحضور المعتمد اليوم (HH:mm) — لمن يملك تفاصيل الملف (0631).
  final String? dueTime;

  final String? status;
  final String? statusLabel;
  final String? activityTitle;

  /// حالة طلب نشاط/إجازة اليوم: approved | pending (null = مسجّل بالحضور).
  final String? requestStatus;
  final int lateMinutes;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final int workMinutes;
  final int overtimeMinutes;
}

class Attendance30Summary {
  const Attendance30Summary({
    required this.present,
    required this.lateDays,
    required this.absent,
    required this.workMinutes,
    this.offsiteDays,
    this.missingCheckout,
  });
  factory Attendance30Summary.fromJson(Map<String, dynamic> j) =>
      Attendance30Summary(
        present: asInt(j['present'], 0),
        lateDays: asInt(j['lateDays'], 0),
        absent: asInt(j['absent'], 0),
        workMinutes: asInt(j['workMinutes'], 0),
        offsiteDays: asNullableInt(j['offsiteDays']),
        missingCheckout: asNullableInt(j['missingCheckout']),
      );
  final int present;
  final int lateDays;
  final int absent;

  /// دقائق الأيام المكتملة فقط (حضور + انصراف).
  final int workMinutes;

  /// أيام مأمورية/قافلة/فاندي ضمن الحضور (null = الخادم لا يرسلها بعد).
  final int? offsiteDays;

  /// أيام سابقة بحضور دون انصراف (null = الخادم لا يرسلها بعد).
  final int? missingCheckout;
}

class RequestCounts {
  const RequestCounts({
    required this.pending,
    required this.approved,
    required this.rejected,
  });
  factory RequestCounts.fromJson(Map<String, dynamic> j) => RequestCounts(
    pending: asInt(j['pending'], 0),
    approved: asInt(j['approved'], 0),
    rejected: asInt(j['rejected'], 0),
  );
  final int pending;
  final int approved;
  final int rejected;
}

class KpiLatest {
  const KpiLatest({
    required this.id,
    required this.periodMonth,
    required this.currentStage,
    required this.finalScore,
    required this.finalRating,
  });
  factory KpiLatest.fromJson(Map<String, dynamic> j) => KpiLatest(
    id: asString(j['id'], ''),
    periodMonth: asString(j['periodMonth'], ''),
    currentStage: asString(j['currentStage'], ''),
    finalScore: asNullableDouble(j['finalScore']),
    finalRating: asNullableString(j['finalRating']),
  );
  final String id;
  final String periodMonth;
  final String currentStage;
  final double? finalScore;
  final String? finalRating;
}

class EmployeeDocumentBrief {
  const EmployeeDocumentBrief({
    required this.id,
    required this.type,
    required this.title,
    required this.expiryDate,
    required this.status,
  });
  factory EmployeeDocumentBrief.fromJson(Map<String, dynamic> j) =>
      EmployeeDocumentBrief(
        id: asString(j['id'], ''),
        type: asString(j['type'], ''),
        title: asString(j['title'], ''),
        expiryDate: optDate(j['expiryDate']),
        status: asString(j['status'], ''),
      );
  final String id;
  final String type;
  final String title;
  final DateTime? expiryDate;
  final String status;
}

class EmployeeAssetBrief {
  const EmployeeAssetBrief({
    required this.id,
    required this.assetName,
    required this.assetType,
    required this.serial,
    required this.handedOverAt,
    required this.returnedAt,
  });
  factory EmployeeAssetBrief.fromJson(Map<String, dynamic> j) =>
      EmployeeAssetBrief(
        id: asString(j['id'], ''),
        assetName: asString(j['assetName'], ''),
        assetType: asString(j['assetType'], ''),
        serial: asNullableString(j['serial']),
        handedOverAt: optDate(j['handedOverAt']),
        returnedAt: optDate(j['returnedAt']),
      );
  final String id;
  final String assetName;
  final String assetType;
  final String? serial;
  final DateTime? handedOverAt;
  final DateTime? returnedAt;
}

class EmployeeRequestBrief {
  const EmployeeRequestBrief({
    required this.id,
    required this.requestNumber,
    required this.requestType,
    required this.title,
    required this.status,
    required this.createdAt,
  });
  factory EmployeeRequestBrief.fromJson(Map<String, dynamic> j) =>
      EmployeeRequestBrief(
        id: asString(j['id'], ''),
        requestNumber: asInt(j['requestNumber'], 0),
        requestType: asString(j['requestType'], ''),
        title: asNullableString(j['title']),
        status: asString(j['status'], ''),
        createdAt: reqDate(j['createdAt']),
      );
  final String id;
  final int requestNumber;
  final String requestType;
  final String? title;
  final String status;
  final DateTime createdAt;
}

class EmployeeTaskBrief {
  const EmployeeTaskBrief({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.dueDate,
  });
  factory EmployeeTaskBrief.fromJson(Map<String, dynamic> j) =>
      EmployeeTaskBrief(
        id: asString(j['id'], ''),
        title: asString(j['title'], ''),
        status: asString(j['status'], ''),
        priority: asNullableString(j['priority']),
        dueDate: optDate(j['dueDate']),
      );
  final String id;
  final String title;
  final String status;
  final String? priority;
  final DateTime? dueDate;
}
