import 'package:ahla_shabab_management_os/features/mobile_data/models/json_parse.dart';

class LocationDirectoryEmployee {
  const LocationDirectoryEmployee({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.jobTitle,
    required this.department,
    this.photoUrl,
    required this.lastLatitude,
    required this.lastLongitude,
    required this.lastAccuracy,
    required this.lastRecordedAt,
    required this.activeRequestId,
    required this.activeRequestStatus,
  });
  factory LocationDirectoryEmployee.fromJson(Map<String, dynamic> json) =>
      LocationDirectoryEmployee(
        id: asString(json['id']),
        name: asString(json['name'], 'موظف'),
        employeeCode: asNullableString(json['employeeCode']),
        jobTitle: asNullableString(json['jobTitle']),
        department: asNullableString(json['department']),
        photoUrl: asNullableString(json['photoUrl']),
        lastLatitude: asNullableDouble(json['lastLatitude']),
        lastLongitude: asNullableDouble(json['lastLongitude']),
        lastAccuracy: asNullableDouble(json['lastAccuracy']),
        lastRecordedAt: optDate(json['lastRecordedAt']),
        activeRequestId: asNullableString(json['activeRequestId']),
        activeRequestStatus: asNullableString(json['activeRequestStatus']),
      );
  final String id;
  final String name;
  final String? employeeCode;
  final String? jobTitle;
  final String? department;
  final String? photoUrl;
  final double? lastLatitude;
  final double? lastLongitude;
  final double? lastAccuracy;
  final DateTime? lastRecordedAt;
  final String? activeRequestId;
  final String? activeRequestStatus;
}

/// ملف موقع موظف للمدير التنفيذي — get_employee_location_dossier (0491).
class ExecutiveEmployeeLocationDossier {
  const ExecutiveEmployeeLocationDossier({
    required this.employee,
    required this.lastPoint,
    required this.points,
    required this.requests,
  });
  factory ExecutiveEmployeeLocationDossier.fromJson(Map<String, dynamic> json) =>
      ExecutiveEmployeeLocationDossier(
        employee: EmployeeLocationProfile.fromJson(asMap(json['employee'])),
        lastPoint: json['lastPoint'] == null
            ? null
            : EmployeeLocationPoint.fromJson(
                asMap(json['lastPoint']),
              ),
        points: asList(json['points'])
            .map((e) => EmployeeLocationPoint.fromJson(
                  asMap(e),
                ))
            .toList(growable: false),
        requests: asList(json['requests'])
            .map((e) => EmployeeLocationRequestItem.fromJson(
                  asMap(e),
                ))
            .toList(growable: false),
      );
  final EmployeeLocationProfile employee;
  final EmployeeLocationPoint? lastPoint;
  final List<EmployeeLocationPoint> points;
  final List<EmployeeLocationRequestItem> requests;
}

class EmployeeLocationProfile {
  const EmployeeLocationProfile({
    required this.id,
    required this.name,
    this.employeeCode,
    this.photoUrl,
    this.jobTitle,
    this.department,
    this.status,
  });
  factory EmployeeLocationProfile.fromJson(Map<String, dynamic> json) =>
      EmployeeLocationProfile(
        id: asString(json['id']),
        name: asString(json['name'], 'موظف'),
        employeeCode: asNullableString(json['employeeCode']),
        photoUrl: asNullableString(json['photoUrl']),
        jobTitle: asNullableString(json['jobTitle']),
        department: asNullableString(json['department']),
        status: asNullableString(json['status']),
      );
  final String id;
  final String name;
  final String? employeeCode;
  final String? photoUrl;
  final String? jobTitle;
  final String? department;
  final String? status;
}

class EmployeeLocationPoint {
  const EmployeeLocationPoint({
    required this.id,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    this.isMock = false,
    this.source,
    this.batteryLevel,
    this.addressAr,
    this.recordedAt,
    this.createdAt,
    this.requestId,
    this.requestMode,
  });
  factory EmployeeLocationPoint.fromJson(Map<String, dynamic> json) =>
      EmployeeLocationPoint(
        id: asString(json['id']),
        latitude: asNullableDouble(json['latitude']),
        longitude: asNullableDouble(json['longitude']),
        accuracy: asNullableDouble(json['accuracy']),
        altitude: asNullableDouble(json['altitude']),
        speed: asNullableDouble(json['speed']),
        heading: asNullableDouble(json['heading']),
        isMock: asBool(json['isMock'], false),
        source: asNullableString(json['source']),
        batteryLevel: asNullableInt(json['batteryLevel']),
        addressAr: asNullableString(json['addressAr']),
        recordedAt: optDate(json['recordedAt']),
        createdAt: optDate(json['createdAt']),
        requestId: asNullableString(json['requestId']),
        requestMode: asNullableString(json['requestMode']),
      );
  final String id;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final bool isMock;
  final String? source;
  final int? batteryLevel;
  final String? addressAr;
  final DateTime? recordedAt;
  final DateTime? createdAt;
  final String? requestId;
  final String? requestMode;

  bool get hasCoordinates => latitude != null && longitude != null;
}

class EmployeeLocationRequestItem {
  const EmployeeLocationRequestItem({
    required this.id,
    required this.status,
    required this.mode,
    this.reason,
    this.requestedByName,
    this.requestedAt,
    this.respondedAt,
    this.startsAt,
    this.expiresAt,
    this.durationMinutes,
    this.pointCount = 0,
  });
  factory EmployeeLocationRequestItem.fromJson(Map<String, dynamic> json) =>
      EmployeeLocationRequestItem(
        id: asString(json['id']),
        status: asString(json['status'], 'pending'),
        mode: asString(json['mode'], 'snapshot'),
        reason: asNullableString(json['reason']),
        requestedByName: asNullableString(json['requestedByName']),
        requestedAt: optDate(json['requestedAt']),
        respondedAt: optDate(json['respondedAt']),
        startsAt: optDate(json['startsAt']),
        expiresAt: optDate(json['expiresAt']),
        durationMinutes: asNullableInt(json['durationMinutes']),
        pointCount: asInt(json['pointCount'], 0),
      );
  final String id;
  final String status;
  final String mode;
  final String? reason;
  final String? requestedByName;
  final DateTime? requestedAt;
  final DateTime? respondedAt;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? durationMinutes;
  final int pointCount;
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
        id: asString(json['id']),
        requesterName: asString(json['requesterName'], 'الإدارة'),
        reason: asString(json['reason'], ''),
        status: asString(json['status'], 'pending'),
        mode: asString(json['mode'], 'snapshot'),
        durationMinutes: asInt(json['durationMinutes'], 1),
        requestedAt: reqDate(json['requestedAt']),
        expiresAt: optDate(json['expiresAt']),
      );
  final String id;
  final String requesterName;
  final String reason;
  final String status;
  final String mode;
  final int durationMinutes;
  final DateTime requestedAt;
  final DateTime? expiresAt;
  // V12 §9 / 0269: تسجيل الفيديو ملغى نهائيًا — التطبيق لا يطلب فيديو التحقق أبدًا.
  bool get needsVideo => false;
  bool get needsPoint => mode == 'snapshot' || mode == 'location_video';
  bool get isTracking => mode.startsWith('track_');
}
