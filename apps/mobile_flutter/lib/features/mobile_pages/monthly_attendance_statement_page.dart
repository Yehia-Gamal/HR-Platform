import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/attendance_pdf_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// الشهور بالعربية
const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// كشف الحضور والانصراف الشهري — للموظف عن نفسه (V12 §18).
class MonthlyAttendanceStatementPage extends ConsumerStatefulWidget {
  const MonthlyAttendanceStatementPage({super.key});

  @override
  ConsumerState<MonthlyAttendanceStatementPage> createState() =>
      _MonthlyAttendanceStatementPageState();
}

class _MonthlyAttendanceStatementPageState
    extends ConsumerState<MonthlyAttendanceStatementPage> {
  final _now = DateTime.now();
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = _now.year;
    _month = _now.month;
  }

  @override
  Widget build(BuildContext context) {
    final statement = ref.watch(myMonthlyStatementProvider((_year, _month)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('كشف الحضور والانصراف'),
        actions: [
          if (statement.hasValue)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded),
              tooltip: 'تصدير PDF',
              onPressed: () async {
                try {
                  await exportAttendancePdf(statement.value!);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(humanizeError(error))),
                    );
                  }
                }
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _month,
                    decoration:
                        const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(_months[i]))),
                    onChanged: (v) => setState(() => _month = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _year,
                    decoration:
                        const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: [_now.year, _now.year - 1, _now.year - 2]
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (v) => setState(() => _year = v!),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(myMonthlyStatementProvider((_year, _month))),
          child: statement.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 8),
                  Text(humanizeError(error), textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => ref.invalidate(myMonthlyStatementProvider((_year, _month))),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            data: (stmt) => _StatementBody(statement: stmt),
          ),
        ),
      ),
    );
  }
}

// ─── الجسم الرئيسي ───────────────────────────────────────────────

class _StatementBody extends StatelessWidget {
  const _StatementBody({required this.statement});

  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final s = statement.summary;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ───── بطاقة بيانات الموظف ─────
        _EmployeeHeader(statement: statement),
        const SizedBox(height: 16),

        // ───── دائرة نسبة الحضور ─────
        _AttendancePercentageCard(statement: statement),
        const SizedBox(height: 16),

        // ───── بطاقات الملخص الرئيسية ─────
        Text('ملخص الشهر',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _MetricTile(icon: Icons.check_circle_outline, label: 'حضور', value: '${s.presentDays}', color: const Color(0xFF0F9F6E)),
            _MetricTile(icon: Icons.cancel_outlined, label: 'غياب', value: '${s.absentDays}', color: scheme.error),
            _MetricTile(icon: Icons.beach_access_outlined, label: 'إجازات', value: '${s.leaveDays}', color: const Color(0xFF6366F1)),
            _MetricTile(icon: Icons.directions_car_outlined, label: 'مأموريات', value: '${s.missionDays}', color: const Color(0xFF0EA5E9)),
            _MetricTile(icon: Icons.assignment_outlined, label: 'إذنات', value: '${s.permitCount}', color: const Color(0xFFF59E0B)),
            _MetricTile(icon: Icons.groups_outlined, label: 'قوافل/فاندي', value: '${s.convoyFundiDays}', color: const Color(0xFF8B5CF6)),
          ],
        ),
        const SizedBox(height: 16),

        // ───── بطاقات الساعات والتأخيرات ─────
        Text('الساعات والمخالفات',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _SummaryTile(label: 'إجمالي الساعات', value: s.totalWorkHours.toStringAsFixed(1), unit: 'ساعة'),
            _SummaryTile(label: 'متوسط يومي', value: s.averageWorkHours.toStringAsFixed(1), unit: 'ساعة/يوم'),
            _SummaryTile(label: 'إجمالي التأخير', value: '${s.totalLateMinutes}', unit: 'دقيقة'),
            _SummaryTile(label: 'خروج مبكر', value: '${s.totalEarlyLeaveMinutes}', unit: 'دقيقة'),
            _SummaryTile(label: 'ساعات إضافية', value: '${s.totalOvertimeMinutes}', unit: 'دقيقة'),
            _SummaryTile(label: 'تصحيحات', value: '${s.correctionCount}', unit: ''),
          ],
        ),

        // ───── ملاحظات نقص البصمة ─────
        if (s.missingCheckInCount > 0 || s.missingCheckOutCount > 0) ...[
          const SizedBox(height: 8),
          Card(
            color: scheme.errorContainer.withValues(alpha: .3),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'نسيان بصمة حضور: ${s.missingCheckInCount} · نسيان بصمة انصراف: ${s.missingCheckOutCount}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ───── الجدول اليومي ─────
        Text('الجدول اليومي',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        ...statement.days.map((d) => _DayCard(day: d)),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── بطاقة بيانات الموظف ──────────────────────────────────────────

class _EmployeeHeader extends StatelessWidget {
  const _EmployeeHeader({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // الاسم والكود
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.person_outline, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(statement.employeeNameAr,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      if (statement.employeeCode != null)
                        Text('كود: ${statement.employeeCode}', style: muted),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // تفاصيل وظيفية
            _InfoRow(icon: Icons.work_outline, label: 'المسمى الوظيفي', value: statement.jobTitle),
            _InfoRow(icon: Icons.business_outlined, label: 'القسم', value: statement.department),
            _InfoRow(icon: Icons.location_city_outlined, label: 'الفرع', value: statement.branch),
            _InfoRow(icon: Icons.supervisor_account_outlined, label: 'المدير المباشر', value: statement.manager),
            _InfoRow(
              icon: Icons.calendar_month_outlined,
              label: 'الفترة',
              value: '${_months[statement.month - 1]} ${statement.year}',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$label: ', style: muted),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}

// ─── دائرة نسبة الحضور ────────────────────────────────────────────

class _AttendancePercentageCard extends StatelessWidget {
  const _AttendancePercentageCard({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final pct = statement.attendancePercentage;
    final s = statement.summary;
    final scheme = Theme.of(context).colorScheme;
    final pctColor = pct >= 90
        ? const Color(0xFF0F9F6E)
        : pct >= 75
            ? const Color(0xFFF59E0B)
            : scheme.error;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          children: [
            // دائرة النسبة
            SizedBox(
              width: 90,
              height: 90,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: pct / 100,
                      strokeWidth: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(pctColor),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${pct.toStringAsFixed(0)}%',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: pctColor)),
                      Text('حضور', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // تفاصيل جانبية
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('نسبة الحضور الشهرية',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  _PctDetailRow(label: 'أيام مجدولة', value: '${s.scheduledDays}'),
                  _PctDetailRow(label: 'أيام حضور', value: '${s.presentDays}'),
                  _PctDetailRow(label: 'أيام عطل رسمية', value: '${s.holidayDays}'),
                  _PctDetailRow(label: 'أيام راحة', value: '${s.restDays}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PctDetailRow extends StatelessWidget {
  const _PctDetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── بطاقة مقياس (أيقونة + رقم + تسمية) ────────────────────────────

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: color)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─── بطاقة ملخص (قيمة + وحدة) ────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(unit, style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── بطاقة اليوم المفصّلة ─────────────────────────────────────────

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});
  final AttendanceStatementDay day;

  static const _warn = {'غائب دون إذن', 'يحتاج مراجعة'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final isWarn = _warn.contains(day.status);
    String fmt(String? t) => (t == null || t.length < 5) ? '—' : t.substring(0, 5);

    // تحديد الأيقونة واللون حسب الحالة
    final (Color cardAccent, IconData statusIcon) = _resolveStatusStyle(scheme);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─ السطر الأول: التاريخ + الحالة
            Row(
              children: [
                Icon(statusIcon, size: 18, color: cardAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${day.dayNameAr} ${day.date}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                ),
                MobileStatusPill(day.status),
              ],
            ),
            const SizedBox(height: 8),

            // ─ السطر الثاني: حضور ← انصراف + ساعات
            Row(
              children: [
                // حضور → انصراف
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        Icon(Icons.login, size: 14, color: const Color(0xFF0F9F6E)),
                        const SizedBox(width: 4),
                        Text(fmt(day.checkIn), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 12, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Icon(Icons.logout, size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(fmt(day.checkOut), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                // ساعات العمل
                if (day.workHours > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${day.workHours.toStringAsFixed(1)} س',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
              ],
            ),

            // ─ السطر الثالث: تفاصيل المخالفات والعلامات
            if (_hasDetails) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (day.lateMinutes > 0)
                    _DetailChip(
                      icon: Icons.schedule,
                      label: 'تأخير ${day.lateMinutes} د',
                      color: isWarn ? scheme.error : const Color(0xFFF59E0B),
                    ),
                  if (day.earlyLeaveMinutes > 0)
                    _DetailChip(
                      icon: Icons.exit_to_app,
                      label: 'خروج مبكر ${day.earlyLeaveMinutes} د',
                      color: const Color(0xFFF59E0B),
                    ),
                  if (day.overtimeMinutes > 0)
                    _DetailChip(
                      icon: Icons.more_time,
                      label: 'إضافي ${day.overtimeMinutes} د',
                      color: const Color(0xFF0F9F6E),
                    ),
                  if (day.hasLeave)
                    _DetailChip(icon: Icons.beach_access, label: 'إجازة', color: const Color(0xFF6366F1)),
                  if (day.hasPermit)
                    _DetailChip(icon: Icons.assignment_turned_in, label: 'إذن', color: const Color(0xFFF59E0B)),
                  if (day.hasMission)
                    _DetailChip(icon: Icons.directions_car, label: 'مأمورية', color: const Color(0xFF0EA5E9)),
                  if (day.hasConvoyFundi)
                    _DetailChip(icon: Icons.groups, label: 'قافلة/فاندي', color: const Color(0xFF8B5CF6)),
                  if (day.missingCheckIn)
                    _DetailChip(icon: Icons.warning_amber, label: 'لم يسجل حضور', color: scheme.error),
                  if (day.missingCheckOut)
                    _DetailChip(icon: Icons.warning_amber, label: 'لم يسجل انصراف', color: scheme.error),
                  if (day.hasCorrection)
                    _DetailChip(icon: Icons.edit_note, label: 'تصحيح', color: const Color(0xFF64748B)),
                ],
              ),
            ],

            // ─ ملاحظة التصحيح
            if (day.correctionNote != null && day.correctionNote!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('📝 ${day.correctionNote}', style: muted),
            ],
          ],
        ),
      ),
    );
  }

  bool get _hasDetails =>
      day.lateMinutes > 0 ||
      day.earlyLeaveMinutes > 0 ||
      day.overtimeMinutes > 0 ||
      day.hasLeave ||
      day.hasPermit ||
      day.hasMission ||
      day.hasConvoyFundi ||
      day.missingCheckIn ||
      day.missingCheckOut ||
      day.hasCorrection;

  (Color, IconData) _resolveStatusStyle(ColorScheme scheme) {
    if (_warn.contains(day.status)) return (scheme.error, Icons.cancel_outlined);
    if (day.hasLeave) return (const Color(0xFF6366F1), Icons.beach_access_outlined);
    if (day.hasMission) return (const Color(0xFF0EA5E9), Icons.directions_car_outlined);
    if (day.hasConvoyFundi) return (const Color(0xFF8B5CF6), Icons.groups_outlined);
    if (day.status == 'حاضر') return (const Color(0xFF0F9F6E), Icons.check_circle_outline);
    if (day.status == 'عطلة رسمية' || day.status == 'راحة') {
      return (scheme.onSurfaceVariant, Icons.event_outlined);
    }
    return (scheme.onSurfaceVariant, Icons.circle_outlined);
  }
}

// ─── شريحة تفاصيل صغيرة (chip) ────────────────────────────────────

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
