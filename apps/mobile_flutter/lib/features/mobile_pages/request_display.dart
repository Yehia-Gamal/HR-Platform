import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

/// عرض موحّد للطلبات في كل الشاشات (التفاصيل، طلباتي، اعتماد طلبات الفريق،
/// صندوق الإجراءات): أسماء الأنواع والحالات ومراحل الاعتماد والأزمنة بالعربية.

// ═══════════════════════════════════════════════════════════════════════════
// نوع الطلب
// ═══════════════════════════════════════════════════════════════════════════

String requestTypeLabel(String type) => switch (type) {
  'leave' => 'إجازة',
  'mission' => 'مأمورية',
  'convoy' => 'قافلة',
  'fundraising' => 'فاندي ترفيهي',
  'late_permit' => 'إذن حضور',
  'early_permit' => 'إذن انصراف',
  'attendance_correction' => 'تصحيح بصمة',
  'shift_change' => 'تغيير فترة العمل',
  'overtime' => 'عمل إضافي',
  'excuse' => 'إذن',
  _ => 'طلب',
};

IconData requestTypeIcon(String type) => switch (type) {
  'leave' => Icons.beach_access_rounded,
  'mission' => Icons.business_center_rounded,
  'convoy' => Icons.directions_bus_rounded,
  'fundraising' => Icons.festival_rounded,
  'late_permit' => Icons.login_rounded,
  'early_permit' => Icons.logout_rounded,
  'attendance_correction' => Icons.fingerprint_rounded,
  'shift_change' => Icons.more_time_rounded,
  _ => Icons.description_rounded,
};

/// ألوان الأنواع مطابقة لألوان حالة اليوم (مأمورية/قافلة/فاندي).
Color requestTypeColor(String type) => switch (type) {
  'leave' => const Color(0xFF0284C7),
  'mission' => const Color(0xFF2563EB),
  'convoy' => const Color(0xFF7C3AED),
  'fundraising' => const Color(0xFF0D9488),
  'late_permit' || 'early_permit' => const Color(0xFFD97706),
  'attendance_correction' => const Color(0xFF4F46E5),
  'shift_change' => const Color(0xFF0F766E),
  _ => const Color(0xFF475569),
};

bool isFieldAssignmentType(String type) =>
    type == 'mission' || type == 'convoy' || type == 'fundraising';

String leaveTypeLabel(String? value) => switch (value) {
  'annual' => 'إجازة اعتيادية',
  'sick' => 'إجازة مرضية',
  'casual' || 'emergency' => 'إجازة عارضة',
  'unpaid' => 'إجازة بدون راتب',
  'weekly_rest_comp' => 'بدل راحة أسبوعية',
  _ => 'إجازة',
};

String permitKindLabel(String? value, String type) => switch (value) {
  'late_arrival' => 'إذن حضور متأخر',
  'early_departure' => 'إذن انصراف مبكر',
  _ => type == 'early_permit' ? 'إذن انصراف مبكر' : 'إذن حضور متأخر',
};

// ═══════════════════════════════════════════════════════════════════════════
// حالة الطلب
// ═══════════════════════════════════════════════════════════════════════════

typedef RequestStatusStyle = ({String label, Color color, IconData icon});

RequestStatusStyle requestStatusStyle(String status) => switch (status) {
  'approved' => (
    label: 'معتمد',
    color: AppColors.statusSuccess,
    icon: Icons.verified_rounded,
  ),
  'rejected' => (
    label: 'مرفوض',
    color: AppColors.statusDanger,
    icon: Icons.cancel_rounded,
  ),
  'returned' => (
    label: 'أُعيد للتعديل',
    color: const Color(0xFFC2410C),
    icon: Icons.undo_rounded,
  ),
  'cancelled' || 'withdrawn' => (
    label: 'مسحوب',
    color: const Color(0xFF64748B),
    icon: Icons.remove_circle_outline_rounded,
  ),
  'expired' => (
    label: 'انتهت مهلته',
    color: const Color(0xFF64748B),
    icon: Icons.timer_off_outlined,
  ),
  _ => (
    label: 'قيد المراجعة',
    color: AppColors.statusWarning,
    icon: Icons.hourglass_top_rounded,
  ),
};

/// شارة حالة الطلب (أيقونة + نص) — بديل الشارة العامة في شاشات الطلبات.
class RequestStatusChip extends StatelessWidget {
  const RequestStatusChip(this.status, {super.key, this.dense = false});

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = requestStatusStyle(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: dense ? 13 : 15, color: style.color),
          const SizedBox(width: 4),
          Text(
            style.label,
            style: TextStyle(
              color: style.color,
              fontWeight: FontWeight.w800,
              fontSize: dense ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// رقاقة صغيرة (عمر الطلب، المهلة، المرحلة…) بلون اختياري.
class RequestMetaChip extends StatelessWidget {
  const RequestMetaChip({
    required this.icon,
    required this.text,
    this.color,
    this.strong = false,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color == null
            ? scheme.surfaceContainerHighest.withValues(alpha: .6)
            : fg.withValues(alpha: strong ? .16 : .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// مراحل الاعتماد
// ═══════════════════════════════════════════════════════════════════════════

/// اسم المرحلة الموحّد: تعريفات المسار القديمة تسمّي المرحلة نفسها
/// «موافقة مشرف العمليات 1» و«مدير التشغيل 1» و«الأوبريشن».
String requestStageName(String? name, {String? roleSlug, int? order}) {
  var n = (name ?? '').trim();
  if (roleSlug == 'operations-manager-1' ||
      n.contains('مشرف العمليات') ||
      n.contains('مدير التشغيل') ||
      n.contains('الأوبريشن')) {
    return 'مدير التشغيل 1';
  }
  if (n.contains('المدير المباشر')) return 'المدير المباشر';
  for (final prefix in const ['موافقة ', 'اعتماد ', 'مراجعة ']) {
    if (n.startsWith(prefix)) n = n.substring(prefix.length).trim();
  }
  if (roleSlug == 'hr-manager' ||
      n == 'الموارد البشرية' ||
      n == 'إدارة الموارد البشرية') {
    return 'الموارد البشرية';
  }
  if (n.isEmpty) return order == 1 ? 'المدير المباشر' : 'مرحلة الاعتماد';
  return n;
}

/// الجهة التي صُعِّد إليها الطلب آليًا.
String escalationTargetLabel(String? roleSlug) => switch (roleSlug) {
  'operations-manager-1' => 'مدير التشغيل 1',
  'operations-manager-2' => 'مدير التشغيل 2',
  'operations-officer' => 'ضابط العمليات',
  'hr-manager' || 'hr-specialist' || 'hr-officer' => 'الموارد البشرية',
  'executive' || 'executive-director' => 'المدير التنفيذي',
  _ => 'المستوى التالي',
};

enum RequestStageState {
  approved('اعتُمد', AppColors.statusSuccess, Icons.check_rounded),
  rejected('رُفض', AppColors.statusDanger, Icons.close_rounded),
  returned('أُعيد للتعديل', Color(0xFFC2410C), Icons.undo_rounded),
  current('بانتظار القرار', AppColors.statusInfo, Icons.hourglass_top_rounded),
  escalated('صُعِّد لتأخر الرد', AppColors.statusWarning, Icons.trending_up_rounded),
  waiting('لم يحن دوره', Color(0xFF94A3B8), Icons.more_horiz_rounded),
  skipped('لم يلزم', Color(0xFF94A3B8), Icons.remove_rounded),
  stopped('توقف بسحب الطلب', Color(0xFF94A3B8), Icons.block_rounded);

  const RequestStageState(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;

  bool get isDecision =>
      this == approved || this == rejected || this == returned;
}

/// موضع المرحلة الحالية بنفس اختيار الخادم: النشطة أولًا ثم أول مصعَّدة/منتظرة.
int currentStepIndex(List<MobileRequestStep> steps, String requestStatus) {
  if (requestStatus != 'pending') return -1;
  final flagged = steps.indexWhere((s) => s.isCurrent == true);
  if (flagged >= 0) return flagged;
  final active = steps.indexWhere((s) => s.status == 'active');
  if (active >= 0) return active;
  return steps.indexWhere(
    (s) => s.status == 'escalated' || s.status == 'pending',
  );
}

RequestStageState requestStageState(
  MobileRequestStep step,
  String requestStatus, {
  required bool isCurrent,
}) {
  if (isCurrent) return RequestStageState.current;
  return switch (step.status) {
    'approved' || 'completed' => RequestStageState.approved,
    'rejected' =>
      step.decision == 'returned' || requestStatus == 'returned'
          ? RequestStageState.returned
          : RequestStageState.rejected,
    'escalated' => RequestStageState.escalated,
    'skipped' =>
      requestStatus == 'cancelled'
          ? RequestStageState.stopped
          : step.escalatedAt != null
          ? RequestStageState.escalated
          : RequestStageState.skipped,
    'active' => RequestStageState.current,
    _ => RequestStageState.waiting,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// الأزمنة بالعربية
// ═══════════════════════════════════════════════════════════════════════════

String _minutesG(int n) => arCount(
  n,
  one: 'دقيقة',
  two: 'دقيقتين',
  few: 'دقائق',
  many: 'دقيقة',
  base: 'دقيقة',
);

String _hoursG(int n) => arCount(
  n,
  one: 'ساعة',
  two: 'ساعتين',
  few: 'ساعات',
  many: 'ساعة',
  base: 'ساعة',
);

String _daysG(int n) => arCount(
  n,
  one: 'يوم',
  two: 'يومين',
  few: 'أيام',
  many: 'يومًا',
  base: 'يوم',
);

/// مدة بصيغة المجرور بعد «منذ / خلال»: «ساعتين»، «3 أيام»، «11 يومًا».
String arSpan(Duration d) {
  final m = d.inMinutes.abs();
  if (m < 60) return _minutesG(m < 1 ? 1 : m);
  final h = d.inHours.abs();
  if (h < 24) return _hoursG(h);
  return _daysG(d.inDays.abs());
}

/// «الآن» / «منذ ساعتين» / «منذ 57 يومًا».
String arAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'الآن';
  return 'منذ ${arSpan(d)}';
}

/// مدة منجزة بصيغة المرفوع: «ساعتان و20 دقيقة».
String arDurationMinutes(int minutes) {
  if (minutes < 60) {
    return arCount(
      minutes,
      one: 'دقيقة واحدة',
      two: 'دقيقتان',
      few: 'دقائق',
      many: 'دقيقة',
      base: 'دقيقة',
    );
  }
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hours = arCount(
    h,
    one: 'ساعة',
    two: 'ساعتان',
    few: 'ساعات',
    many: 'ساعة',
    base: 'ساعة',
  );
  if (m == 0) return hours;
  return '$hours و${arCount(m, one: 'دقيقة', two: 'دقيقتان', few: 'دقائق', many: 'دقيقة', base: 'دقيقة')}';
}

/// حالة المهلة: «متأخر منذ يومين» (حمراء) أو «خلال 3 ساعات».
({String label, bool overdue})? requestDueStatus(
  DateTime? due, {
  DateTime? now,
}) {
  if (due == null) return null;
  final d = due.difference(now ?? DateTime.now());
  if (d.isNegative) return (label: 'متأخر منذ ${arSpan(d)}', overdue: true);
  return (label: 'المهلة خلال ${arSpan(d)}', overdue: false);
}

String _timeOf(DateTime local) => DateFormat('h:mm a', 'ar').format(local);

/// «الأحد 5 أكتوبر» (مع السنة إن لم تكن الحالية).
String arDay(DateTime date) {
  final now = DateTime.now();
  final pattern = date.year == now.year ? 'EEEE d MMMM' : 'EEEE d MMMM y';
  return DateFormat(pattern, 'ar').format(date);
}

/// «اليوم · 10:20 ص» / «أمس · 4:15 م» / «الأحد 5 أكتوبر · 10:20 ص».
String arDateTime(DateTime t) {
  final local = t.toLocal();
  final now = DateTime.now();
  final day = DateTime(local.year, local.month, local.day);
  if (day == DateTime(now.year, now.month, now.day)) {
    return 'اليوم · ${_timeOf(local)}';
  }
  if (day == DateTime(now.year, now.month, now.day - 1)) {
    return 'أمس · ${_timeOf(local)}';
  }
  return '${arDay(local)} · ${_timeOf(local)}';
}

/// عنوان مجموعة زمنية للقوائم: «اليوم»، «أمس»، «الأحد 4 أكتوبر»، «سبتمبر».
String requestGroupLabel(DateTime t) {
  final local = t.toLocal();
  final now = DateTime.now();
  final day = DateTime(local.year, local.month, local.day);
  final diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
  if (diff <= 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  if (diff < 7) return DateFormat('EEEE d MMMM', 'ar').format(local);
  if (local.year == now.year) return DateFormat('MMMM', 'ar').format(local);
  return DateFormat('MMMM y', 'ar').format(local);
}

/// فاصل مجموعة زمنية داخل القوائم.
class RequestGroupHeader extends StatelessWidget {
  const RequestGroupHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: scheme.outlineVariant, height: 1)),
        ],
      ),
    );
  }
}

/// يُدرج فواصل المجموعات الزمنية بين عناصر قائمة مرتبة زمنيًا.
List<Widget> withRequestGroupHeaders<T>(
  List<T> items,
  DateTime Function(T) dateOf,
  Widget Function(T) build,
) {
  final out = <Widget>[];
  String? last;
  for (final item in items) {
    final label = requestGroupLabel(dateOf(item));
    if (label != last) {
      out.add(RequestGroupHeader(label));
      last = label;
    }
    out.add(build(item));
  }
  return out;
}

/// 'HH:mm' → '2:19 م'.
String? time12(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  final parts = raw.trim().split(':');
  final h = int.tryParse(parts.first);
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  if (h == null) return raw;
  final period = h < 12 ? 'ص' : 'م';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $period';
}

DateTime? _payloadDate(Map<String, dynamic> payload, String key) {
  final raw = payload[key]?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

/// فترة الطلب: «الأحد 5 أكتوبر» أو «من الأحد 5 أكتوبر إلى الثلاثاء 7 أكتوبر».
String? requestPeriodLabel(Map<String, dynamic> payload) {
  final start =
      _payloadDate(payload, 'startDate') ?? _payloadDate(payload, 'permitDate');
  final end = _payloadDate(payload, 'endDate');
  if (start == null) return end == null ? null : arDay(end);
  if (end == null || DateUtils.isSameDay(start, end)) return arDay(start);
  return 'من ${arDay(start)} إلى ${arDay(end)}';
}

/// عدد أيام الطلب (من الحمولة أو من الفترة).
int? requestDays(Map<String, dynamic> payload) {
  final raw = payload['days'];
  if (raw is num && raw > 0) return raw.round();
  final start = _payloadDate(payload, 'startDate');
  final end = _payloadDate(payload, 'endDate');
  if (start == null || end == null || end.isBefore(start)) return null;
  return end.difference(start).inDays + 1;
}

/// آخر يوم في الطلب — لمعرفة أن مأمورية «قيد التنفيذ» انقضى يومها.
DateTime? requestLastDay(Map<String, dynamic> payload) =>
    _payloadDate(payload, 'endDate') ??
    _payloadDate(payload, 'startDate') ??
    _payloadDate(payload, 'permitDate');

String _permitMinutes(Object? raw) {
  final minutes = raw is num ? raw.round() : int.tryParse('$raw') ?? 120;
  if (minutes % 60 == 0) {
    return arCount(
      minutes ~/ 60,
      one: 'ساعة واحدة',
      two: 'ساعتان',
      few: 'ساعات',
      many: 'ساعة',
      base: 'ساعة',
    );
  }
  return '$minutes دقيقة';
}

/// سطر موجز يلخّص الطلب في البطاقات: الوجهة/النوع · الفترة · المدة.
String requestBriefLine(String type, Map<String, dynamic> payload) {
  final parts = <String>[];
  final location = payload['location']?.toString().trim();
  switch (type) {
    case 'leave':
      parts.add(leaveTypeLabel(payload['leaveType']?.toString()));
      final period = requestPeriodLabel(payload);
      if (period != null) parts.add(period);
      final days = requestDays(payload);
      if (days != null && days > 1) parts.add(arDays(days));
    case 'late_permit' || 'early_permit':
      final period = requestPeriodLabel(payload);
      if (period != null) parts.add(period);
      parts.add(_permitMinutes(payload['minutes']));
    case 'shift_change':
      final shift = payload['shiftName']?.toString().trim();
      if (shift != null && shift.isNotEmpty) parts.add(shift);
      final from = _payloadDate(payload, 'effectiveFrom');
      if (from != null) parts.add('من ${arDay(from)}');
    default:
      if (location != null && location.isNotEmpty) parts.add(location);
      final period = requestPeriodLabel(payload);
      if (period != null) parts.add(period);
      final start = time12(payload['startTime']);
      if (start != null) parts.add(start);
  }
  return parts.join(' · ');
}

/// مدة الإذن للعرض في التفاصيل.
String permitDurationLabel(Object? minutes) => _permitMinutes(minutes);

/// رسالة عربية لأخطاء مسار الطلبات المعروفة من الخادم.
String? requestErrorMessage(Object error) {
  final m = error.toString();
  if (m.contains('is not pending') || m.contains('only pending requests')) {
    return 'تم البت في هذا الطلب بالفعل — حدّث الصفحة لرؤية القرار.';
  }
  if (m.contains('not authorized for the active workflow step')) {
    return 'ليس لك صلاحية القرار في هذه المرحلة من مسار الطلب.';
  }
  if (m.contains('return_requires_comment')) return 'اكتب سبب الإرجاع للموظف.';
  if (m.contains('ONLY_REQUEST_OWNER_CAN_RESUBMIT')) {
    return 'إعادة الرفع متاحة لصاحب الطلب فقط.';
  }
  if (m.contains('ONLY_REJECTED_OR_RETURNED_CAN_RESUBMIT')) {
    return 'لا يُعاد رفع إلا الطلب المرفوض أو المُعاد للتعديل.';
  }
  if (m.contains('TYPE_NOT_RESUBMITTABLE')) {
    return 'هذا النوع من الطلبات لا يُعاد رفعه — قدّم طلبًا جديدًا.';
  }
  if (m.contains('INVALID_TITLE_LENGTH')) {
    return 'عنوان الطلب يجب أن يكون بين 3 و300 حرف.';
  }
  if (m.contains('INVALID_REASON_LENGTH')) {
    return 'السبب يجب أن يكون بين 3 و300 حرف.';
  }
  if (m.contains('request not found') || m.contains('REQUEST_NOT_FOUND')) {
    return 'الطلب غير موجود أو حُذف.';
  }
  if (m.contains('request access denied')) {
    return 'لا تملك صلاحية عرض هذا الطلب.';
  }
  return null;
}
