import 'package:ahla_shabab_management_os/core/observability/crash_reporter.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/models/json_parse.dart';

/// 0450: حالة يوم المأمورية/التكليف — تقود تحول زر البصمة في صفحة الحضور.
class MissionToday {
  const MissionToday({
    required this.requestId,
    required this.type,
    required this.execStatus,
    this.startTime,
    this.startedAt,
    this.endedAt,
    required this.autoCheckout,
  });

  factory MissionToday.fromJson(Map<String, dynamic> json) => MissionToday(
    requestId: asString(json['requestId']),
    type: asString(json['type'], 'mission'),
    execStatus: asString(json['execStatus'], 'approved'),
    startTime: asNullableString(json['startTime']),
    startedAt: optDate(json['startedAt']),
    endedAt: optDate(json['endedAt']),
    autoCheckout: asBool(json['autoCheckout'], false),
  );

  final String requestId;

  /// mission | convoy | fundraising
  final String type;

  /// approved (لم تبدأ) | in_progress | completed
  final String execStatus;

  /// الوقت المتوقع للبداية من الطلب (HH:mm) إن وُجد.
  final String? startTime;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// انتهت بعد نهاية الدوام ⇒ انصراف تلقائي بلا بصمة إضافية.
  final bool autoCheckout;
}

class AttendanceState {
  const AttendanceState({
    required this.attendanceRequired,
    required this.selfPunchEnabled,
    required this.activeLocalDevices,
    required this.hasActiveLocalDevice,
    required this.canPunch,
    required this.suggestedAction,
    required this.lastEventType,
    required this.lastEventAt,
    required this.lastEventStatus,
    required this.todayStatus,
    required this.localDeviceStatus,
    required this.todayCheckInAt,
    required this.todayCheckOutAt,
    this.workMinutes = 0,
    this.overtimeMinutes = 0,
    this.missionToday,
    this.isSplitShift = false,
    this.checkInCount = 0,
    this.lateMinutes = 0,
    this.estimatedLatePenaltyAmount = 0.0,
    this.todayCheckInTime,
    this.targetCheckoutAt,
    this.targetCheckoutTime,
    this.compensationRemainingMinutes = 0,
    this.isCompensationEligible = false,
    this.isCompensationCompleted = false,
  });
  factory AttendanceState.fromJson(Map<String, dynamic> json) =>
      AttendanceState(
        attendanceRequired: asBool(json['attendanceRequired'], false),
        selfPunchEnabled: asBool(json['selfPunchEnabled'], false),
        activeLocalDevices: asInt(
          json['activeLocalDevices'],
          asInt(json['activePasskeys'], 0),
        ),
        hasActiveLocalDevice:
            asNullableBool(json['hasActiveLocalDevice']) ??
            asBool(json['hasActivePasskey'], false),
        canPunch: asBool(json['canPunch'], false),
        suggestedAction: asString(json['suggestedAction'], 'CHECK_IN'),
        lastEventType: asNullableString(json['lastEventType']),
        lastEventAt: optDate(json['lastEventAt']),
        lastEventStatus: asNullableString(json['lastEventStatus']),
        todayStatus: asNullableString(json['todayStatus']),
        localDeviceStatus: asNullableString(json['localDeviceStatus']),
        todayCheckInAt: optDate(json['todayCheckInAt']),
        todayCheckOutAt: optDate(json['todayCheckOutAt']),
        workMinutes: asInt(json['workMinutes'], 0),
        overtimeMinutes: asInt(json['overtimeMinutes'], 0),
        missionToday: json['missionToday'] == null
            ? null
            : MissionToday.fromJson(
                asMap(json['missionToday']),
              ),
        isSplitShift: asBool(json['isSplitShift'], false),
        checkInCount: asInt(json['checkInCount'], 0),
        lateMinutes: asInt(json['lateMinutes'], 0),
        estimatedLatePenaltyAmount:
            asDouble(json['estimatedLatePenaltyAmount'], 0.0),
        todayCheckInTime: asNullableString(json['todayCheckInTime']),
        targetCheckoutAt: optDate(json['targetCheckoutAt']),
        targetCheckoutTime: asNullableString(json['targetCheckoutTime']),
        compensationRemainingMinutes:
            asInt(json['compensationRemainingMinutes'], 0),
        isCompensationEligible:
            asBool(json['isCompensationEligible'], false),
        isCompensationCompleted:
            asBool(json['isCompensationCompleted'], false),
      );
  final bool attendanceRequired;
  final bool selfPunchEnabled;
  final int activeLocalDevices;
  final bool hasActiveLocalDevice;
  final bool canPunch;
  final String suggestedAction;
  final String? lastEventType;
  final DateTime? lastEventAt;
  final String? lastEventStatus;
  final String? todayStatus;
  final int workMinutes;
  final int overtimeMinutes;

  /// حالة الجهاز المحلي: null (لا يوجد)، 'pending'، 'active'، 'blocked'، إلخ.
  final String? localDeviceStatus;

  /// 0439: أول توقيت حضور اليوم (بتوقيت UTC) — null قبل البصمة الأولى.
  final DateTime? todayCheckInAt;

  /// 0439: آخر توقيت انصراف اليوم (بتوقيت UTC) — null قبل اكتمال اليوم.
  final DateTime? todayCheckOutAt;

  /// 0450: يوم مأمورية/تكليف معتمد لليوم — يقود تحول زر البصمة.
  final MissionToday? missionToday;

  /// 0588: الموظف لديه وردية مجزأة (فترتان عمل في اليوم مع استراحة).
  final bool isSplitShift;

  /// 0588: عدد بصمات الحضور المسجلة اليوم.
  final int checkInCount;

  /// 0675: دقائق التأخير المسجلة لليوم.
  final int lateMinutes;

  /// 0675: مبلغ الغرامة التقديرية للتأخير (ج.م).
  final double estimatedLatePenaltyAmount;

  /// 0675: وقت الحضور الفعلي بنظام 12 ساعة (مثال: "10:23 ص").
  final String? todayCheckInTime;

  /// 0675: موعد الانصراف المستهدف لإكمال 8 ساعات عمل.
  final DateTime? targetCheckoutAt;

  /// 0675: نص موعد الانصراف المستهدف (مثال: "06:23 م").
  final String? targetCheckoutTime;

  /// 0675: دقائق العمل المتبقية لإتمام 8 ساعات عمل.
  final int compensationRemainingMinutes;

  /// 0675: هل الموظف متأخر ولديه فرصة تعويض بإتمام 8 ساعات عمل؟
  final bool isCompensationEligible;

  /// 0675: هل أتم الموظف 8 ساعات عمل وبانتظار بصمة الانصراف التأكيدية؟
  final bool isCompensationCompleted;
}

class PasskeyDevice {
  const PasskeyDevice({
    required this.id,
    required this.credentialId,
    required this.deviceLabel,
    required this.status,
    required this.trusted,
    required this.deviceType,
    required this.backedUp,
    required this.lastUsedAt,
    required this.createdAt,
    required this.approvedAt,
    required this.rejectionReason,
    required this.revocationSource,
    required this.canResubmit,
  });
  factory PasskeyDevice.fromJson(Map<String, dynamic> json) => PasskeyDevice(
    id: asString(json['id']),
    credentialId: asString(json['credentialId'], ''),
    deviceLabel: asString(json['deviceLabel'], 'جهاز موثوق'),
    status: asString(json['status'], 'active'),
    trusted: asBool(json['trusted'], false),
    deviceType: asNullableString(json['deviceType']),
    backedUp: asBool(json['backedUp'], false),
    lastUsedAt: optDate(json['lastUsedAt']),
    createdAt: reqDate(json['createdAt']),
    approvedAt: optDate(json['approvedAt']),
    rejectionReason: asNullableString(json['rejectionReason']),
    revocationSource: asNullableString(json['revocationSource']),
    canResubmit: asBool(json['canResubmit'], false),
  );
  final String id;
  final String credentialId;
  final String deviceLabel;
  final String status;
  final bool trusted;
  final String? deviceType;
  final bool backedUp;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final String? revocationSource;
  final bool canResubmit;
}

class AttendanceHistoryItem {
  const AttendanceHistoryItem({
    required this.id,
    required this.eventType,
    required this.eventAt,
    required this.status,
    required this.verificationStatus,
    required this.lateMinutes,
    required this.requiresReview,
    required this.accuracyMeters,
    required this.distanceMeters,
    required this.source,
    required this.notes,
  });

  factory AttendanceHistoryItem.fromJson(Map<String, dynamic> json) =>
      AttendanceHistoryItem(
        id: asString(json['id']),
        eventType: asString(json['eventType'], 'CHECK_IN'),
        eventAt: reqDate(json['eventAt']),
        status: asString(json['status'], 'pending'),
        verificationStatus:
            asString(json['verificationStatus'], 'unverified'),
        lateMinutes: asInt(json['lateMinutes'], 0),
        requiresReview: asBool(json['requiresReview'], false),
        accuracyMeters: asNullableDouble(json['accuracyMeters']),
        distanceMeters: asNullableDouble(json['distanceMeters']),
        source: asString(json['source'], 'mobile'),
        notes: asNullableString(json['notes']),
      );

  final String id;
  final String eventType;
  final DateTime eventAt;
  final String status;
  final String verificationStatus;
  final int lateMinutes;
  final bool requiresReview;
  final double? accuracyMeters;
  final double? distanceMeters;
  final String source;
  final String? notes;
}

/// تكليف عمل (مأمورية/قافلة/فاندي) — وحدة work_assignments.
/// لا يخصم من رصيد الإجازات ولا يُحتسب غيابًا.
class MobileWorkAssignment {
  const MobileWorkAssignment({
    required this.id,
    required this.assignmentNumber,
    required this.assignmentType,
    required this.title,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.isFullDay,
    required this.location,
    required this.needsReport,
    required this.targetAmount,
  });

  factory MobileWorkAssignment.fromJson(Map<String, dynamic> json) =>
      MobileWorkAssignment(
        id: asString(json['id']),
        assignmentNumber: asInt(json['assignment_number'], 0),
        assignmentType: asString(json['assignment_type'], 'MISSION'),
        title: asString(json['title'], ''),
        status: asString(json['status'], 'DRAFT'),
        startAt: reqDate(json['start_at']),
        endAt: reqDate(json['end_at']),
        isFullDay: asBool(json['is_full_day'], true),
        location: asNullableString(json['location']),
        needsReport: asBool(json['needs_report'], false),
        targetAmount: asNullableDouble(json['target_amount']),
      );

  final String id;
  final int assignmentNumber;
  final String assignmentType; // MISSION | CONVOY | FUNDRAISING
  final String title;
  final String status;
  final DateTime startAt;
  final DateTime endAt;
  final bool isFullDay;
  final String? location;
  final bool needsReport;
  final double? targetAmount;

  String get typeLabel => switch (assignmentType) {
    'CONVOY' => 'قافلة',
    'FUNDRAISING' => 'فاندي ترفيهي',
    _ => 'مأمورية',
  };
}

/// صف واحد في كشف الحضور اليومي (V12 §18).
class AttendanceStatementDay {
  const AttendanceStatementDay({
    required this.date,
    required this.dayNameAr,
    required this.checkIn,
    required this.checkOut,
    required this.shiftName,
    required this.workHours,
    required this.requiredHours,
    required this.lateMinutes,
    required this.earlyLeaveMinutes,
    required this.overtimeMinutes,
    required this.status,
    required this.isAbsent,
    required this.isOfficialHoliday,
    required this.hasLeave,
    required this.hasPermit,
    required this.hasMission,
    required this.hasConvoyFundi,
    required this.missingCheckIn,
    required this.missingCheckOut,
    required this.hasCorrection,
    required this.correctionNote,
    required this.isFuture,
    required this.isDue,
    required this.isOpenShift,
    required this.isCompleted,
    this.hasAdminOverride = false,
    this.adminOverride,
    this.leaveDetail,
    this.assignmentDetail,
    this.permitDetail,
    this.correctionDetail,
  });

  factory AttendanceStatementDay.fromJson(Map<String, dynamic> json) =>
      AttendanceStatementDay(
        date: asString(json['date'], ''),
        dayNameAr: asString(json['dayNameAr'], ''),
        checkIn: asNullableString(json['checkIn']),
        checkOut: asNullableString(json['checkOut']),
        shiftName: asString(json['shiftName'], ''),
        workHours: asDouble(json['workHours'], 0),
        requiredHours: asDouble(json['requiredHours'], 0),
        lateMinutes: asInt(json['lateMinutes'], 0),
        earlyLeaveMinutes: asInt(json['earlyLeaveMinutes'], 0),
        overtimeMinutes: asInt(json['overtimeMinutes'], 0),
        status: asString(json['status'], ''),
        isAbsent: asBool(json['isAbsent'], false),
        isOfficialHoliday: asBool(json['isOfficialHoliday'], false),
        hasLeave: asBool(json['hasLeave'], false),
        hasPermit: asBool(json['hasPermit'], false),
        hasMission: asBool(json['hasMission'], false),
        hasConvoyFundi: asBool(json['hasConvoyFundi'], false),
        missingCheckIn: asBool(json['missingCheckIn'], false),
        missingCheckOut: asBool(json['missingCheckOut'], false),
        hasCorrection: asBool(json['hasCorrection'], false),
        correctionNote: asNullableString(json['correctionNote']),
        isFuture: asBool(json['isFuture'], false),
        isDue: asBool(json['isDue'], false),
        isOpenShift: asBool(json['isOpenShift'], false),
        isCompleted: asBool(json['isCompleted'], false),
        hasAdminOverride: (json['adminOverride'] != null && json['adminOverride'] is Map) ||
            (asBool(json['hasAdminOverride'], false)),
        adminOverride: json['adminOverride'] is Map
            ? asMap(json['adminOverride'])
            : null,
        leaveDetail: _mapDayDetail(json['details'], 'leave'),
        assignmentDetail: _mapDayDetail(json['details'], 'assignment'),
        permitDetail: _mapDayDetail(json['details'], 'permit'),
        correctionDetail: _mapDayDetail(json['details'], 'correction'),
      );

  /// قراءة آمنة لكائن فرعي داخل details (يرجع null إن غاب)
  static Map<String, dynamic>? _mapDayDetail(dynamic details, String key) {
    if (details is! Map) return null;
    final v = details[key];
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  final String date;
  final String dayNameAr;
  final String? checkIn;
  final String? checkOut;
  final String shiftName;
  final double workHours;
  final double requiredHours;
  final int lateMinutes;
  final int earlyLeaveMinutes;
  final int overtimeMinutes;
  final String status;
  final bool isAbsent;
  final bool isOfficialHoliday;
  final bool hasLeave;
  final bool hasPermit;
  final bool hasMission;
  final bool hasConvoyFundi;
  final bool missingCheckIn;
  final bool missingCheckOut;
  final bool hasCorrection;
  final String? correctionNote;
  final bool isFuture;
  final bool isDue;
  final bool isOpenShift;
  final bool isCompleted;
  final bool hasAdminOverride;
  final Map<String, dynamic>? adminOverride;

  /// تفاصيل إيضاحية تعبَّأ من backend (0252) — كلها اختيارية.
  final Map<String, dynamic>? leaveDetail;
  final Map<String, dynamic>? assignmentDetail;
  final Map<String, dynamic>? permitDetail;
  final Map<String, dynamic>? correctionDetail;
}

/// ملخص شهري للكشف.
class AttendanceStatementSummary {
  const AttendanceStatementSummary({
    required this.totalDays,
    required this.scheduledDays,
    required this.dueScheduledDays,
    required this.upcomingDays,
    required this.presentDays,
    required this.absentDays,
    required this.openShiftDays,
    required this.completedPresenceDays,
    required this.leaveDays,
    required this.missionDays,
    required this.permitCount,
    required this.convoyFundiDays,
    required this.holidayDays,
    required this.restDays,
    required this.totalWorkHours,
    required this.totalRequiredHours,
    required this.averageWorkHours,
    required this.totalLateMinutes,
    required this.totalEarlyLeaveMinutes,
    required this.totalOvertimeMinutes,
    required this.missingCheckInCount,
    required this.missingCheckOutCount,
    required this.correctionCount,
    required this.attendanceRate,
    required this.attendanceRatePresentDays,
    required this.attendanceRateDueDays,
    required this.hoursComplianceRate,
    required this.hoursComplianceAvailable,
    required this.coverageRate,
    required this.coverageDays,
    required this.totalDeficitMinutes,
    required this.hoursRateWorkedMinutes,
    required this.hoursRateRequiredMinutes,
    this.isAttendanceExempt = false,
    this.attendanceRateExcludedLeaveDays = 0,
  });

  factory AttendanceStatementSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    final rateBasis = json['attendanceRateBasis'] is Map
        ? asMap(json['attendanceRateBasis'])
        : null;
    final hoursBasis = json['hoursRateBasis'] is Map
        ? asMap(json['hoursRateBasis'])
        : null;

    return AttendanceStatementSummary(
      totalDays: asInt(json['totalDays'], 0),
      scheduledDays: asInt(json['scheduledDays'], 0),
      dueScheduledDays: asInt(
        json['dueScheduledDays'],
        asInt(json['scheduledDays'], 0),
      ),
      upcomingDays: asInt(json['upcomingDays'], 0),
      presentDays: asInt(json['presentDays'], 0),
      absentDays: asInt(json['absentDays'], 0),
      openShiftDays: asInt(json['openShiftDays'], 0),
      completedPresenceDays:
          asInt(json['completedPresenceDays'], 0),
      leaveDays: asInt(json['leaveDays'], 0),
      missionDays: asInt(json['missionDays'], 0),
      permitCount: asInt(json['permitCount'], 0),
      convoyFundiDays: asInt(json['convoyFundiDays'], 0),
      holidayDays: asInt(json['holidayDays'], 0),
      restDays: asInt(json['restDays'], 0),
      totalWorkHours: asDouble(json['totalWorkHours'], 0),
      totalRequiredHours: asDouble(json['totalRequiredHours'], 0),
      averageWorkHours: asDouble(json['averageWorkHours'], 0),
      totalLateMinutes: asInt(json['totalLateMinutes'], 0),
      totalEarlyLeaveMinutes:
          asInt(json['totalEarlyLeaveMinutes'], 0),
      totalOvertimeMinutes: asInt(json['totalOvertimeMinutes'], 0),
      missingCheckInCount: asInt(json['missingCheckInCount'], 0),
      missingCheckOutCount: asInt(json['missingCheckOutCount'], 0),
      correctionCount: asInt(json['correctionCount'], 0),
      attendanceRate: asNullableDouble(json['attendanceRate']),
      attendanceRatePresentDays: asInt(
        rateBasis?['presentInDue'],
        asInt(json['presentDays'], 0),
      ),
      attendanceRateDueDays: asInt(
        rateBasis?['dueDays'],
        asInt(json['scheduledDays'], asInt(json['dueScheduledDays'], 0)),
      ),
      hoursComplianceRate: asDouble(json['hoursComplianceRate'], 0),
      hoursComplianceAvailable:
          asNullableBool(json['hoursComplianceAvailable']) ??
          asDouble(json['totalRequiredHours'], 0) > 0,
      coverageRate: asDouble(json['coverageRate'], 0),
      coverageDays: asInt(json['coverageDays'], 0),
      totalDeficitMinutes: asInt(json['totalDeficitMinutes'], 0),
      hoursRateWorkedMinutes: asInt(
        hoursBasis?['workedMinutes'],
        (asDouble(json['totalWorkHours'], 0) * 60).round(),
      ),
      hoursRateRequiredMinutes: asInt(
        hoursBasis?['requiredMinutes'],
        (asDouble(json['totalRequiredHours'], 0) * 60).round(),
      ),
      isAttendanceExempt: asBool(json['isAttendanceExempt'], false),
      attendanceRateExcludedLeaveDays:
          asInt(rateBasis?['excludedLeaveDays'], 0),
    );
  }

  final int totalDays;
  final int scheduledDays;
  final int dueScheduledDays;
  final int upcomingDays;
  final int presentDays;
  final int absentDays;
  final int openShiftDays;
  final int completedPresenceDays;
  final int leaveDays;
  final int missionDays;
  final int permitCount;
  final int convoyFundiDays;
  final int holidayDays;
  final int restDays;
  final double totalWorkHours;
  final double totalRequiredHours;
  final double averageWorkHours;
  final int totalLateMinutes;
  final int totalEarlyLeaveMinutes;
  final int totalOvertimeMinutes;
  final int missingCheckInCount;
  final int missingCheckOutCount;
  final int correctionCount;
  final double? attendanceRate;
  final int attendanceRatePresentDays;
  final int attendanceRateDueDays;
  final double hoursComplianceRate;
  final bool hoursComplianceAvailable;
  final double coverageRate;
  final int coverageDays;
  final int totalDeficitMinutes;
  final int hoursRateWorkedMinutes;
  final int hoursRateRequiredMinutes;

  /// معفى من البصمة بقرار الإدارة — لا تُحسب له نسبة («معفى» لا 0%).
  final bool isAttendanceExempt;

  /// أيام إجازة استُبعدت من مقام نسبة الحضور (معتمدة أو قيد الاعتماد).
  final int attendanceRateExcludedLeaveDays;
}

/// كشف الحضور والانصراف الشهري الكامل (V12 §18).
class MonthlyAttendanceStatement {
  const MonthlyAttendanceStatement({
    this.employeeId = '',
    this.canEditDays = false,
    this.photoUrl,
    required this.employeeNameAr,
    required this.employeeCode,
    required this.jobTitle,
    required this.department,
    required this.branch,
    required this.manager,
    required this.hireDate,
    required this.year,
    required this.month,
    required this.startDate,
    required this.endDate,
    required this.generatedAt,
    required this.days,
    required this.summary,
  });

  factory MonthlyAttendanceStatement.fromJson(Map<String, dynamic> json) {
    final emp = json['employee'] is Map
        ? asMap(json['employee'])
        : <String, dynamic>{};
    final period = json['period'] is Map
        ? asMap(json['period'])
        : <String, dynamic>{};
    final sumJson = json['summary'] is Map
        ? asMap(json['summary'])
        : <String, dynamic>{};
    final cap = json['capabilities'] is Map
        ? asMap(json['capabilities'])
        : <String, dynamic>{};
    final daysJson = asList(json['days']);
    return MonthlyAttendanceStatement(
      employeeId: asString(emp['id'], asNullableString(json['employeeId']) ?? ''),
      canEditDays: asBool(cap['canEditDays'], false),
      photoUrl: asNullableString(emp['photoUrl']),
      employeeNameAr: (asNullableString(emp['fullNameAr']))?.isNotEmpty == true
          ? asString(emp['fullNameAr'])
          : (asString(emp['name'], asNullableString(json['employeeNameAr']) ?? '')),
      employeeCode: asString(emp['employeeCode'], asString(emp['code'], '')),
      jobTitle: asString(emp['jobTitle'], ''),
      department: asString(emp['department'], ''),
      branch: asString(emp['branch'], ''),
      manager: asString(emp['manager'], ''),
      hireDate: asNullableString(emp['hireDate']),
      year: asInt(period['year'], 0),
      month: asInt(period['month'], 0),
      startDate: asString(period['startDate'], ''),
      endDate: asString(period['endDate'], ''),
      generatedAt: asString(period['generatedAt'], ''),
      days: daysJson
          .where((e) => e != null && e is Map)
          .map(
            (e) => AttendanceStatementDay.fromJson(
              asMap(e),
            ),
          )
          .toList(growable: false),
      summary: AttendanceStatementSummary.fromJson(sumJson),
    );
  }

  final String employeeId;
  final bool canEditDays;
  final String? photoUrl;
  final String employeeNameAr;
  final String? employeeCode;
  final String jobTitle;
  final String department;
  final String branch;
  final String manager;
  final String? hireDate;
  final int year;
  final int month;
  final String startDate;
  final String endDate;
  final String generatedAt;
  final List<AttendanceStatementDay> days;
  final AttendanceStatementSummary summary;

  /// نسبة الحضور الشهرية (كل يوم به بصمة دخول ÷ كل أيام عمل الشهر).
  double get attendancePercentage =>
      summary.attendanceRate ??
      (summary.attendanceRateDueDays > 0
          ? (summary.attendanceRatePresentDays /
                summary.attendanceRateDueDays *
                100)
          : 0);

  double get hoursPercentage => summary.hoursComplianceRate;
}

class MobileScheduleDay {
  const MobileScheduleDay({
    required this.id,
    required this.workDate,
    required this.dayStatus,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.notes,
  });
  factory MobileScheduleDay.fromJson(Map<String, dynamic> json) =>
      MobileScheduleDay(
        id: asString(json['id']),
        workDate: reqDate(json['workDate']),
        dayStatus: asString(json['dayStatus'], 'scheduled'),
        shiftName: asNullableString(json['shiftName']),
        startTime: asNullableString(json['startTime']),
        endTime: asNullableString(json['endTime']),
        notes: asNullableString(json['notes']),
      );
  final String id;
  final DateTime workDate;
  final String dayStatus;
  final String? shiftName;
  final String? startTime;
  final String? endTime;
  final String? notes;
}

class MobileAttendanceCorrection {
  const MobileAttendanceCorrection({
    required this.id,
    required this.workDate,
    required this.type,
    required this.reason,
    required this.status,
    required this.requestedCheckIn,
    required this.requestedCheckOut,
    required this.requestedStatus,
    required this.reviewNote,
    required this.createdAt,
  });
  factory MobileAttendanceCorrection.fromJson(Map<String, dynamic> json) =>
      MobileAttendanceCorrection(
        id: asString(json['id']),
        workDate: reqDate(json['workDate']),
        type: asString(json['type'], 'other'),
        reason: asString(json['reason'], ''),
        status: asString(json['status'], 'pending'),
        requestedCheckIn: optDate(json['requestedCheckIn']),
        requestedCheckOut: optDate(json['requestedCheckOut']),
        requestedStatus: asNullableString(json['requestedStatus']),
        reviewNote: asNullableString(json['reviewNote']),
        createdAt: reqDate(json['createdAt']),
      );
  final String id;
  final DateTime workDate;
  final String type;
  final String reason;
  final String status;
  final DateTime? requestedCheckIn;
  final DateTime? requestedCheckOut;
  final String? requestedStatus;
  final String? reviewNote;
  final DateTime createdAt;
}

class MobileAttendanceServices {
  const MobileAttendanceServices({
    required this.schedule,
    required this.corrections,
    required this.lastUpdatedAt,
  });
  factory MobileAttendanceServices.fromJson(Map<String, dynamic> json) =>
      MobileAttendanceServices(
        schedule: asList(json['schedule'])
            .map(
              (e) => MobileScheduleDay.fromJson(
                asMap(e),
              ),
            )
            .toList(growable: false),
        corrections: asList(json['corrections'])
            .map(
              (e) => MobileAttendanceCorrection.fromJson(
                asMap(e),
              ),
            )
            .toList(growable: false),
        lastUpdatedAt: optDate(json['lastUpdatedAt']),
      );
  final List<MobileScheduleDay> schedule;
  final List<MobileAttendanceCorrection> corrections;
  final DateTime? lastUpdatedAt;
}

class MobileWorkShift {
  const MobileWorkShift({
    required this.id,
    required this.code,
    required this.name,
    this.nameEn,
    required this.startTime,
    required this.endTime,
    this.graceInMinutes = 15,
    this.isDefault = false,
    this.description,
  });

  factory MobileWorkShift.fromJson(Map<String, dynamic> json) => MobileWorkShift(
        id: asString(json['id']),
        code: asString(json['code'], ''),
        name: asString(json['name'], 'وردية عمل'),
        nameEn: asNullableString(json['nameEn']),
        startTime: asString(json['startTime'], '10:00:00'),
        endTime: asString(json['endTime'], '18:00:00'),
        graceInMinutes: asInt(json['graceInMinutes'], 15),
        isDefault: asBool(json['isDefault'], false),
        description: asNullableString(json['description']),
      );

  final String id;
  final String code;
  final String name;
  final String? nameEn;
  final String startTime;
  final String endTime;
  final int graceInMinutes;
  final bool isDefault;
  final String? description;

  String get formattedRange {
    String formatTime(String t) {
      final parts = t.split(':');
      if (parts.length < 2) return t;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final period = h < 12 ? 'ص' : 'م';
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final mStr = m > 0 ? ':${m.toString().padLeft(2, '0')}' : '';
      return '$h12$mStr $period';
    }
    return '${formatTime(startTime)} – ${formatTime(endTime)}';
  }

  String get formattedStartTime {
    final parts = startTime.split(':');
    if (parts.length < 2) return startTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final period = h < 12 ? 'ص' : 'م';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mStr = m > 0 ? ':${m.toString().padLeft(2, '0')}' : ':00';
    return '$h12$mStr $period';
  }

  String get formattedEndTime {
    final parts = endTime.split(':');
    if (parts.length < 2) return endTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final period = h < 12 ? 'ص' : 'م';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mStr = m > 0 ? ':${m.toString().padLeft(2, '0')}' : ':00';
    return '$h12$mStr $period';
  }

  String get formattedGraceEndTime {
    final parts = startTime.split(':');
    if (parts.length < 2) return startTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final totalM = h * 60 + m + graceInMinutes;
    final graceH = (totalM ~/ 60) % 24;
    final graceM = totalM % 60;
    final period = graceH < 12 ? 'ص' : 'م';
    final h12 = graceH == 0 ? 12 : (graceH > 12 ? graceH - 12 : graceH);
    final mStr = ':${graceM.toString().padLeft(2, '0')}';
    return '$h12$mStr $period';
  }
}

class ShiftTodayPermit {
  const ShiftTodayPermit({
    required this.id,
    required this.requestType,
    required this.title,
    required this.permitMinutes,
    this.permitKind = 'late_arrival',
    this.status = 'approved',
    required this.effectiveStartTime,
    required this.effectiveGraceEndTime,
    required this.effectiveEndTime,
  });

  factory ShiftTodayPermit.fromJson(Map<String, dynamic> json) => ShiftTodayPermit(
        id: asString(json['id'], ''),
        requestType: asString(json['requestType'], 'late_permit'),
        title: asString(json['title'], 'إذن معتمد'),
        permitMinutes: asInt(json['permitMinutes'], 120),
        permitKind: asString(json['permitKind'], 'late_arrival'),
        status: asString(json['status'], 'approved'),
        effectiveStartTime: asString(json['effectiveStartTime'], '10:00:00'),
        effectiveGraceEndTime: asString(json['effectiveGraceEndTime'], '10:15:00'),
        effectiveEndTime: asString(json['effectiveEndTime'], '18:00:00'),
      );

  final String id;
  final String requestType;
  final String title;
  final int permitMinutes;
  final String permitKind;
  final String status;
  final String effectiveStartTime;
  final String effectiveGraceEndTime;
  final String effectiveEndTime;

  bool get isLateArrival => permitKind != 'early_departure';
  bool get isEarlyDeparture => permitKind == 'early_departure';

  String get durationLabel {
    final h = permitMinutes ~/ 60;
    final m = permitMinutes % 60;
    if (h > 0 && m > 0) return '$h ساعة و$m دقيقة';
    if (h == 1) return 'ساعة واحدة';
    if (h == 2) return 'ساعتان';
    if (h > 2) return '$h ساعات';
    return '$m دقيقة';
  }
}

class CurrentWorkShift {
  const CurrentWorkShift({
    required this.id,
    required this.code,
    required this.name,
    this.nameEn,
    required this.startTime,
    required this.endTime,
    this.graceInMinutes = 15,
    this.isAssigned = false,
    this.assignmentId,
    this.effectiveFrom,
    this.status = 'default',
    this.effectiveStartTime,
    this.effectiveGraceEndTime,
    this.effectiveEndTime,
    this.hasPermitToday = false,
    this.todayPermit,
  });

  factory CurrentWorkShift.fromJson(Map<String, dynamic> json) => CurrentWorkShift(
        id: asString(json['id']),
        code: asString(json['code'], 'OFFICIAL'),
        name: asString(json['name'], 'الدوام الأساسي (10 ص – 6 م)'),
        nameEn: asNullableString(json['nameEn']),
        startTime: asString(json['startTime'], '10:00:00'),
        endTime: asString(json['endTime'], '18:00:00'),
        graceInMinutes: asInt(json['graceInMinutes'], 15),
        isAssigned: asBool(json['isAssigned'], false),
        assignmentId: asNullableString(json['assignmentId']),
        effectiveFrom: optDate(json['effectiveFrom']),
        status: asString(json['status'], 'default'),
        effectiveStartTime: asNullableString(json['effectiveStartTime']),
        effectiveGraceEndTime: asNullableString(json['effectiveGraceEndTime']),
        effectiveEndTime: asNullableString(json['effectiveEndTime']),
        hasPermitToday:
            asNullableBool(json['hasPermitToday']) ??
            (json['todayPermit'] != null || json['permitToday'] != null),
        todayPermit: (json['todayPermit'] ?? json['permitToday']) != null
            ? ShiftTodayPermit.fromJson(
                asMap(json['todayPermit'] ?? json['permitToday']),
              )
            : null,
      );

  final String id;
  final String code;
  final String name;
  final String? nameEn;
  final String startTime;
  final String endTime;
  final int graceInMinutes;
  final bool isAssigned;
  final String? assignmentId;
  final DateTime? effectiveFrom;
  final String status;
  final String? effectiveStartTime;
  final String? effectiveGraceEndTime;
  final String? effectiveEndTime;
  final bool hasPermitToday;
  final ShiftTodayPermit? todayPermit;

  bool get hasActivePermit => todayPermit != null || hasPermitToday;
  bool get hasTodayPermit => hasActivePermit;
  String get activeStartTime => effectiveStartTime ?? startTime;
  String get activeEndTime => effectiveEndTime ?? endTime;

  CurrentWorkShift copyWith({
    String? id,
    String? code,
    String? name,
    String? nameEn,
    String? startTime,
    String? endTime,
    int? graceInMinutes,
    bool? isAssigned,
    String? assignmentId,
    DateTime? effectiveFrom,
    String? status,
    String? effectiveStartTime,
    String? effectiveGraceEndTime,
    String? effectiveEndTime,
    bool? hasPermitToday,
    ShiftTodayPermit? todayPermit,
  }) {
    return CurrentWorkShift(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      graceInMinutes: graceInMinutes ?? this.graceInMinutes,
      isAssigned: isAssigned ?? this.isAssigned,
      assignmentId: assignmentId ?? this.assignmentId,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      status: status ?? this.status,
      effectiveStartTime: effectiveStartTime ?? this.effectiveStartTime,
      effectiveGraceEndTime: effectiveGraceEndTime ?? this.effectiveGraceEndTime,
      effectiveEndTime: effectiveEndTime ?? this.effectiveEndTime,
      hasPermitToday: hasPermitToday ?? this.hasPermitToday,
      todayPermit: todayPermit ?? this.todayPermit,
    );
  }

  static String _formatClock(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return t;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final period = h < 12 ? 'ص' : 'م';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mStr = m > 0 ? ':${m.toString().padLeft(2, '0')}' : ':00';
    return '$h12$mStr $period';
  }

  String get formattedRange {
    return '${_formatClock(startTime)} – ${_formatClock(endTime)}';
  }

  String get formattedStartTime => _formatClock(startTime);
  String get formattedEndTime => _formatClock(endTime);

  String get formattedActiveStartTime => _formatClock(activeStartTime);
  String get formattedActiveEndTime => _formatClock(activeEndTime);

  String get formattedActiveGraceEndTime {
    if (effectiveGraceEndTime != null) {
      return _formatClock(effectiveGraceEndTime!);
    }
    final parts = activeStartTime.split(':');
    if (parts.length < 2) return formattedGraceEndTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final totalM = h * 60 + m + graceInMinutes;
    final graceH = (totalM ~/ 60) % 24;
    final graceM = totalM % 60;
    final period = graceH < 12 ? 'ص' : 'م';
    final h12 = graceH == 0 ? 12 : (graceH > 12 ? graceH - 12 : graceH);
    final mStr = ':${graceM.toString().padLeft(2, '0')}';
    return '$h12$mStr $period';
  }

  String get formattedGraceEndTime {
    final parts = startTime.split(':');
    if (parts.length < 2) return startTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final totalM = h * 60 + m + graceInMinutes;
    final graceH = (totalM ~/ 60) % 24;
    final graceM = totalM % 60;
    final period = graceH < 12 ? 'ص' : 'م';
    final h12 = graceH == 0 ? 12 : (graceH > 12 ? graceH - 12 : graceH);
    final mStr = ':${graceM.toString().padLeft(2, '0')}';
    return '$h12$mStr $period';
  }

  String get badgeLabel => isAssigned ? 'معتمدة من الإدارة' : 'الدوام الافتراضي العام';
}

class PendingShiftChange {
  const PendingShiftChange({
    required this.requestId,
    this.title,
    this.reason,
    this.requestedShiftId,
    this.requestedShiftName,
    this.createdAt,
    this.status = 'pending',
  });

  factory PendingShiftChange.fromJson(Map<String, dynamic> json) => PendingShiftChange(
        requestId: asString(json['requestId']),
        title: asNullableString(json['title']),
        reason: asNullableString(json['reason']),
        requestedShiftId: asNullableString(json['requestedShiftId']),
        requestedShiftName: asNullableString(json['requestedShiftName']),
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'].toString()),
        status: asString(json['status'], 'pending'),
      );

  final String requestId;
  final String? title;
  final String? reason;
  final String? requestedShiftId;
  final String? requestedShiftName;
  final DateTime? createdAt;
  final String status;
}

class MobileWorkShiftInfo {
  const MobileWorkShiftInfo({
    required this.currentShift,
    required this.availableShifts,
    this.pendingRequest,
    this.todayPermit,
  });

  factory MobileWorkShiftInfo.fromJson(Map<String, dynamic> json) {
    final currentShiftMap = asNullableMap(json['currentShift']);
    final rawPermit = json['todayPermit'] ??
        json['permitToday'] ??
        currentShiftMap?['todayPermit'] ??
        currentShiftMap?['permitToday'];
    final permitJson = rawPermit != null
        ? ShiftTodayPermit.fromJson(asMap(rawPermit))
        : null;
    var current = CurrentWorkShift.fromJson(asMap(json['currentShift']));
    if (permitJson != null) {
      current = current.copyWith(
        todayPermit: permitJson,
        hasPermitToday: true,
        effectiveStartTime: current.effectiveStartTime ?? permitJson.effectiveStartTime,
        effectiveGraceEndTime: current.effectiveGraceEndTime ?? permitJson.effectiveGraceEndTime,
        effectiveEndTime: current.effectiveEndTime ?? permitJson.effectiveEndTime,
      );
    }
    return MobileWorkShiftInfo(
      currentShift: current,
      availableShifts: asList(json['availableShifts'])
          .map((e) => MobileWorkShift.fromJson(asMap(e)))
          .toList(growable: false),
      pendingRequest: json['pendingRequest'] == null
          ? null
          : PendingShiftChange.fromJson(
              asMap(json['pendingRequest']),
            ),
      todayPermit: permitJson,
    );
  }

  final CurrentWorkShift currentShift;
  final List<MobileWorkShift> availableShifts;
  final PendingShiftChange? pendingRequest;
  final ShiftTodayPermit? todayPermit;
}

// ── AttendanceTodayEmployee ───────────────────────────────────────────────
// موظف مع حالة حضوره اليوم — يُستخدم في لوحة الحضور التنفيذية.
class AttendanceTodayEmployee {
  const AttendanceTodayEmployee({
    required this.id,
    required this.name,
    required this.employeeCode,
    required this.photoUrl,
    required this.jobTitle,
    required this.department,
    required this.attendanceStatus,
    required this.firstCheckIn,
    required this.lastCheckOut,
    required this.lateMinutes,
    required this.isOnMission,
    required this.lastLatitude,
    required this.lastLongitude,
    required this.lastRecordedAt,
  });
  factory AttendanceTodayEmployee.fromJson(Map<String, dynamic> json) =>
      AttendanceTodayEmployee(
        id: asString(json['id']),
        name: asString(json['name'], 'موظف'),
        employeeCode: asNullableString(json['employeeCode']),
        photoUrl: asNullableString(json['photoUrl']),
        jobTitle: asNullableString(json['jobTitle']),
        department: asNullableString(json['department']),
        attendanceStatus: asString(json['attendanceStatus'], 'absent'),
        firstCheckIn: optDate(json['firstCheckIn']),
        lastCheckOut: optDate(json['lastCheckOut']),
        lateMinutes: asInt(json['lateMinutes'], 0),
        isOnMission: asBool(json['isOnMission'], false),
        lastLatitude: asNullableDouble(json['lastLatitude']),
        lastLongitude: asNullableDouble(json['lastLongitude']),
        lastRecordedAt: optDate(json['lastRecordedAt']),
      );
  final String id;
  final String name;
  final String? employeeCode;
  final String? photoUrl;
  final String? jobTitle;
  final String? department;
  final String attendanceStatus;
  final DateTime? firstCheckIn;
  final DateTime? lastCheckOut;
  final int lateMinutes;
  final bool isOnMission;
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime? lastRecordedAt;

  String get statusAr {
    if (isOnMission) return 'مأمورية خارجية';
    return switch (attendanceStatus) {
      'present' => 'حضر',
      'late' => 'متأخر',
      'absent' => 'غائب',
      'on_leave' => 'إجازة',
      'on_permit' || 'permit' || 'late_permit' => 'في إذن',
      'holiday' => 'عطلة',
      'weekend' => 'إجازة أسبوعية',
      'partial' => 'حضور جزئي',
      'pending' => 'في انتظار التحقق',
      _ => attendanceStatus,
    };
  }
}

// ── MobileInstantPenalty ─────────────────────────────────────────────────
// غرامة حضور فورية — تُعرض للموظف في صفحة غراماتي.
class MobileInstantPenalty {
  const MobileInstantPenalty({
    required this.id,
    required this.workDate,
    required this.lateMinutes,
    required this.originalAmount,
    required this.currentAmount,
    required this.currency,
    required this.status,
    this.escalationLevel = 'initial',
    this.paidAt,
    this.suspendedAt,
    this.suspensionLiftedAt,
    this.notes,
    required this.createdAt,
    this.excuseStatus = 'none',
    this.excuseText,
    this.excuseAttachmentUrl,
    this.excuseNotes,
    this.paymentMethod,
    this.receiptAttachmentUrl,
    this.receiptReferenceNumber,
    this.employeeId,
    this.employeeName,
    this.departmentName,
    this.cancelledReason,
    this.photoUrl,
  });

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static String? _toStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }

  factory MobileInstantPenalty.fromJson(Map<String, dynamic> j) {
    try {
      return MobileInstantPenalty(
        id: _toStr(j['id']) ?? '',
        workDate: _toStr(j['work_date'] ?? j['workDate']) ?? '',
        lateMinutes: _toInt(j['late_minutes'] ?? j['lateMinutes']),
        originalAmount: _toDouble(j['original_amount'] ?? j['originalAmount']),
        currentAmount: _toDouble(j['current_amount'] ?? j['currentAmount']),
        currency: _toStr(j['currency']) ?? 'EGP',
        status: _toStr(j['status']) ?? 'pending_payment',
        escalationLevel:
            _toStr(j['escalation_level'] ?? j['escalationLevel']) ?? 'initial',
        paidAt: optDate(j['paid_at'] ?? j['paidAt']),
        suspendedAt: optDate(j['suspended_at'] ?? j['suspendedAt']),
        suspensionLiftedAt:
            optDate(j['suspension_lifted_at'] ?? j['suspensionLiftedAt']),
        notes: _toStr(j['notes']),
        createdAt: reqDate(j['created_at'] ?? j['createdAt']),
        excuseStatus:
            _toStr(j['excuse_status'] ?? j['excuseStatus']) ?? 'none',
        excuseText: _toStr(j['excuse_text'] ?? j['excuseText']),
        excuseAttachmentUrl:
            _toStr(j['excuse_attachment_url'] ?? j['excuseAttachmentUrl']),
        excuseNotes: _toStr(j['excuse_notes'] ?? j['excuseNotes']),
        paymentMethod: _toStr(j['payment_method'] ?? j['paymentMethod']),
        receiptAttachmentUrl:
            _toStr(j['receipt_attachment_url'] ?? j['receiptAttachmentUrl']),
        receiptReferenceNumber:
            _toStr(j['receipt_reference_number'] ?? j['receiptReferenceNumber']),
        employeeId: _toStr(j['employee_id'] ?? j['employeeId']),
        employeeName: _toStr(j['employee_name'] ?? j['employeeName']),
        departmentName: _toStr(j['department_name'] ?? j['departmentName']),
        cancelledReason: _toStr(j['cancelled_reason'] ?? j['cancelledReason']),
        photoUrl: _toStr(j['photo_url'] ?? j['photoUrl']),
      );
    } catch (error, stackTrace) {
      CrashReporter.instance.captureError(
        error,
        stackTrace,
        context: 'mobile_instant_penalty_from_json',
      );
      return MobileInstantPenalty(
        id: _toStr(j['id']) ?? '',
        workDate: _toStr(j['work_date'] ?? j['workDate']) ?? '',
        lateMinutes: _toInt(j['late_minutes'] ?? j['lateMinutes']),
        originalAmount: _toDouble(j['original_amount'] ?? j['originalAmount']),
        currentAmount: _toDouble(j['current_amount'] ?? j['currentAmount']),
        currency: 'EGP',
        status: 'pending_payment',
        createdAt: DateTime.now(),
      );
    }
  }

  final String id;
  final String workDate;
  final int lateMinutes;
  final double originalAmount;
  final double currentAmount;
  final String currency;
  final String status;

  /// مرحلة التصعيد: initial / doubled / suspended.
  final String escalationLevel;
  final DateTime? paidAt;
  final DateTime? suspendedAt;
  final DateTime? suspensionLiftedAt;
  final String? notes;
  final DateTime createdAt;
  final String excuseStatus;
  final String? excuseText;
  final String? excuseAttachmentUrl;
  final String? excuseNotes;
  final String? paymentMethod;
  final String? receiptAttachmentUrl;
  final String? receiptReferenceNumber;

  /// للعرض الإداري (get_instant_penalties): صاحب الغرامة وإدارته.
  final String? employeeId;
  final String? employeeName;
  final String? departmentName;
  final String? photoUrl;

  /// سبب الإلغاء/الإعفاء — منفصل عن الملاحظات (0642).
  final String? cancelledReason;
}

class MobileAttendanceCorrectionDetail {
  const MobileAttendanceCorrectionDetail({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.employeePhotoUrl,
    this.jobTitle,
    this.branchId,
    required this.workDate,
    required this.type,
    this.requestedCheckIn,
    this.requestedCheckOut,
    this.requestedStatus,
    required this.reason,
    this.attachmentPath,
    required this.status,
    this.reviewedBy,
    this.reviewerName,
    this.reviewedAt,
    this.reviewNote,
    required this.createdAt,
    this.canDecide = false,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? employeePhotoUrl;
  final String? jobTitle;
  final String? branchId;
  final DateTime workDate;
  final String type;
  final DateTime? requestedCheckIn;
  final DateTime? requestedCheckOut;
  final String? requestedStatus;
  final String reason;
  final String? attachmentPath;
  final String status;
  final String? reviewedBy;
  final String? reviewerName;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final DateTime createdAt;
  final bool canDecide;

  factory MobileAttendanceCorrectionDetail.fromJson(Map<String, dynamic> json) {
    return MobileAttendanceCorrectionDetail(
      id: asString(json['id'], ''),
      employeeId: asString(json['employeeId'], ''),
      employeeName: asString(json['employeeName'], 'موظف'),
      employeeCode: asString(json['employeeCode'], ''),
      employeePhotoUrl: asNullableString(json['employeePhotoUrl']),
      jobTitle: asNullableString(json['jobTitle']),
      branchId: asNullableString(json['branchId']),
      workDate: DateTime.tryParse(asString(json['workDate'], '')) ?? DateTime.now(),
      type: asString(json['type'], 'missing_check_in'),
      requestedCheckIn: json['requestedCheckIn'] != null ? DateTime.tryParse(asString(json['requestedCheckIn'])) : null,
      requestedCheckOut: json['requestedCheckOut'] != null ? DateTime.tryParse(asString(json['requestedCheckOut'])) : null,
      requestedStatus: asNullableString(json['requestedStatus']),
      reason: asString(json['reason'], ''),
      attachmentPath: asNullableString(json['attachmentPath']),
      status: asString(json['status'], 'pending'),
      reviewedBy: asNullableString(json['reviewedBy']),
      reviewerName: asNullableString(json['reviewerName']),
      reviewedAt: json['reviewedAt'] != null ? DateTime.tryParse(asString(json['reviewedAt'])) : null,
      reviewNote: asNullableString(json['reviewNote']),
      createdAt: DateTime.tryParse(asString(json['createdAt'], '')) ?? DateTime.now(),
      canDecide: asBool(json['canDecide'], false),
    );
  }
}

class MobileTeamAttendanceCorrection {
  const MobileTeamAttendanceCorrection({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.employeePhotoUrl,
    this.jobTitle,
    required this.workDate,
    required this.type,
    this.requestedCheckIn,
    this.requestedCheckOut,
    this.requestedStatus,
    required this.reason,
    this.attachmentPath,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    required this.createdAt,
    this.canDecide = false,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? employeePhotoUrl;
  final String? jobTitle;
  final DateTime workDate;
  final String type;
  final DateTime? requestedCheckIn;
  final DateTime? requestedCheckOut;
  final String? requestedStatus;
  final String reason;
  final String? attachmentPath;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final DateTime createdAt;
  final bool canDecide;

  factory MobileTeamAttendanceCorrection.fromJson(Map<String, dynamic> json) {
    return MobileTeamAttendanceCorrection(
      id: asString(json['id'], ''),
      employeeId: asString(json['employeeId'], ''),
      employeeName: asString(json['employeeName'], 'موظف'),
      employeeCode: asString(json['employeeCode'], ''),
      employeePhotoUrl: asNullableString(json['employeePhotoUrl']),
      jobTitle: asNullableString(json['jobTitle']),
      workDate: DateTime.tryParse(asString(json['workDate'], '')) ?? DateTime.now(),
      type: asString(json['type'], 'missing_check_in'),
      requestedCheckIn: json['requestedCheckIn'] != null ? DateTime.tryParse(asString(json['requestedCheckIn'])) : null,
      requestedCheckOut: json['requestedCheckOut'] != null ? DateTime.tryParse(asString(json['requestedCheckOut'])) : null,
      requestedStatus: asNullableString(json['requestedStatus']),
      reason: asString(json['reason'], ''),
      attachmentPath: asNullableString(json['attachmentPath']),
      status: asString(json['status'], 'pending'),
      reviewedBy: asNullableString(json['reviewedBy']),
      reviewedAt: json['reviewedAt'] != null ? DateTime.tryParse(asString(json['reviewedAt'])) : null,
      reviewNote: asNullableString(json['reviewNote']),
      createdAt: DateTime.tryParse(asString(json['createdAt'], '')) ?? DateTime.now(),
      canDecide: asBool(json['canDecide'], false),
    );
  }
}
