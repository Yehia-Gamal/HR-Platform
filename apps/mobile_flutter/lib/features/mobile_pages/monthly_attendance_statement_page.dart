import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/attendance_pdf_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// الشهور بالعربية
const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

// ألوان الحالات الثابتة
const _kPresent = Color(0xFF0F9F6E);
const _kAbsent = Color(0xFFEF4444);
const _kLeave = Color(0xFF6366F1);
const _kMission = Color(0xFF0EA5E9);
const _kConvoy = Color(0xFF8B5CF6);
const _kPermit = Color(0xFFF59E0B);
const _kHoliday = Color(0xFF94A3B8);
const _kPartial = Color(0xFFF97316);

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
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                          value: i + 1, child: Text(_months[i])),
                    ),
                    onChanged: (v) => setState(() => _month = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _year,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [_now.year, _now.year - 1, _now.year - 2]
                        .map((y) =>
                            DropdownMenuItem(value: y, child: Text('$y')))
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
                  Icon(Icons.error_outline,
                      size: 40,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 8),
                  Text(humanizeError(error), textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => ref.invalidate(
                        myMonthlyStatementProvider((_year, _month))),
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

// ═══════════════════════════════════════════════════════════════════
//  الجسم الرئيسي
// ═══════════════════════════════════════════════════════════════════

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

        // ───── بطاقات الملخص ─────
        Text('ملخص الشهر',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _MetricTile(
                icon: Icons.check_circle_outline,
                label: 'حضور',
                value: '${s.presentDays}',
                color: _kPresent),
            _MetricTile(
                icon: Icons.cancel_outlined,
                label: 'غياب',
                value: '${s.absentDays}',
                color: scheme.error),
            _MetricTile(
                icon: Icons.beach_access_outlined,
                label: 'إجازات',
                value: '${s.leaveDays}',
                color: _kLeave),
            _MetricTile(
                icon: Icons.directions_car_outlined,
                label: 'مأموريات',
                value: '${s.missionDays}',
                color: _kMission),
            _MetricTile(
                icon: Icons.assignment_outlined,
                label: 'إذنات',
                value: '${s.permitCount}',
                color: _kPermit),
            _MetricTile(
                icon: Icons.groups_outlined,
                label: 'قوافل/فاندي',
                value: '${s.convoyFundiDays}',
                color: _kConvoy),
          ],
        ),
        const SizedBox(height: 16),

        // ───── الساعات والمخالفات ─────
        Text('الساعات والمخالفات',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _SummaryTile(
                label: 'إجمالي الساعات',
                value: s.totalWorkHours.toStringAsFixed(1),
                unit: 'ساعة'),
            _SummaryTile(
                label: 'متوسط يومي',
                value: s.averageWorkHours.toStringAsFixed(1),
                unit: 'ساعة/يوم'),
            _SummaryTile(
                label: 'إجمالي التأخير',
                value: '${s.totalLateMinutes}',
                unit: 'دقيقة'),
            _SummaryTile(
                label: 'خروج مبكر',
                value: '${s.totalEarlyLeaveMinutes}',
                unit: 'دقيقة'),
            _SummaryTile(
                label: 'ساعات إضافية',
                value: '${s.totalOvertimeMinutes}',
                unit: 'دقيقة'),
            _SummaryTile(
                label: 'تصحيحات', value: '${s.correctionCount}', unit: ''),
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
                  Icon(Icons.warning_amber_rounded,
                      size: 20, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'نسيان بصمة حضور: ${s.missingCheckInCount} · نسيان بصمة انصراف: ${s.missingCheckOutCount}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ═════ التقويم الشهري (بديل الجدول اليومي) ═════
        Row(
          children: [
            Expanded(
              child: Text('التقويم الشهري',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
            ),
            Icon(Icons.touch_app_outlined,
                size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('اضغط على اليوم',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 10),
        _MonthCalendarGrid(statement: statement),
        const SizedBox(height: 10),
        const _CalendarLegend(),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  شبكة التقويم (7 أعمدة — سبت → جمعة)
// ═══════════════════════════════════════════════════════════════════

class _MonthCalendarGrid extends StatelessWidget {
  const _MonthCalendarGrid({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final year = statement.year;
    final month = statement.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstDay = DateTime(year, month, 1);

    // ربط بيانات كل يوم برقمه
    final dayMap = <int, AttendanceStatementDay>{};
    for (final d in statement.days) {
      final n = _parseDayNum(d.date);
      if (n != null && n >= 1 && n <= daysInMonth) dayMap[n] = d;
    }

    // عمود البداية: السبت = 0
    // DateTime.weekday: 1=Mon … 6=Sat, 7=Sun
    final startCol = (firstDay.weekday + 1) % 7;

    const headers = ['سبت', 'أحد', 'اثن', 'ثلا', 'أرب', 'خمس', 'جمع'];
    final totalSlots = startCol + daysInMonth;
    final rows = (totalSlots / 7).ceil();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // ── رأس الأيام ──
            Row(
              children: headers
                  .map((h) => Expanded(
                        child: Center(
                          child: Text(h,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              )),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 6),
            // ── صفوف التقويم ──
            ...List.generate(rows, (row) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: List.generate(7, (col) {
                    final idx = row * 7 + col;
                    final dayNum = idx - startCol + 1;
                    if (dayNum < 1 || dayNum > daysInMonth) {
                      return const Expanded(child: SizedBox(height: 46));
                    }
                    final date = DateTime(year, month, dayNum);
                    final isToday = date.year == today.year &&
                        date.month == today.month &&
                        date.day == today.day;
                    final isFuture = date.isAfter(today);
                    return Expanded(
                      child: _CalendarCell(
                        dayNum: dayNum,
                        dayData: dayMap[dayNum],
                        isToday: isToday,
                        isFuture: isFuture,
                        date: date,
                      ),
                    );
                  }),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  static int? _parseDayNum(String date) {
    if (date.contains('-')) {
      final parts = date.split('-');
      if (parts.length >= 3) return int.tryParse(parts.last);
    }
    if (date.contains('/')) return int.tryParse(date.split('/').first);
    return int.tryParse(date);
  }
}

// ═══════════════════════════════════════════════════════════════════
//  خلية يوم واحد
// ═══════════════════════════════════════════════════════════════════

class _CalendarCell extends ConsumerWidget {
  const _CalendarCell({
    required this.dayNum,
    required this.dayData,
    required this.isToday,
    required this.isFuture,
    required this.date,
  });

  final int dayNum;
  final AttendanceStatementDay? dayData;
  final bool isToday;
  final bool isFuture;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, dot) = _colors(scheme);

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _DayActionSheet(
          dayNum: dayNum,
          dayData: dayData,
          date: date,
          isFuture: isFuture,
        ),
      ),
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: scheme.primary, width: 2.5)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayNum',
              style: TextStyle(
                fontWeight: isToday ? FontWeight.w900 : FontWeight.w700,
                fontSize: 14,
                color: fg,
              ),
            ),
            if (dot != null) ...[
              const SizedBox(height: 2),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (Color bg, Color fg, Color? dot) _colors(ColorScheme scheme) {
    // أيام مستقبلية — مظللة بدون حالة
    if (isFuture) {
      return (
        scheme.surfaceContainerHighest.withValues(alpha: .35),
        scheme.onSurfaceVariant.withValues(alpha: .45),
        null,
      );
    }

    final d = dayData;
    if (d == null) {
      return (
        scheme.surfaceContainerHighest.withValues(alpha: .15),
        scheme.onSurfaceVariant,
        null,
      );
    }

    final st = d.status;

    // حاضر
    if (st == 'حاضر' || st == 'present') {
      return (_kPresent.withValues(alpha: .14), _kPresent, _kPresent);
    }
    // غائب
    if (st == 'غائب' ||
        st == 'غائب دون إذن' ||
        st == 'absent') {
      return (_kAbsent.withValues(alpha: .14), _kAbsent, _kAbsent);
    }
    // إجازة
    if (d.hasLeave || st == 'إجازة' || st == 'on_leave') {
      return (_kLeave.withValues(alpha: .14), _kLeave, _kLeave);
    }
    // عطلة رسمية
    if (st == 'عطلة رسمية' || st == 'holiday') {
      return (_kHoliday.withValues(alpha: .1), _kHoliday, null);
    }
    // راحة / عطلة أسبوعية
    if (st == 'راحة' || st == 'weekend' || st == 'rest') {
      return (_kHoliday.withValues(alpha: .08), _kHoliday, null);
    }
    // مأمورية
    if (d.hasMission || st == 'مأمورية') {
      return (_kMission.withValues(alpha: .14), _kMission, _kMission);
    }
    // قافلة/فاندي
    if (d.hasConvoyFundi) {
      return (_kConvoy.withValues(alpha: .14), _kConvoy, _kConvoy);
    }
    // جزئي
    if (st == 'جزئي' || st == 'partial') {
      return (_kPartial.withValues(alpha: .14), _kPartial, _kPartial);
    }
    // يحتاج مراجعة / معلّق
    if (st == 'يحتاج مراجعة' || st == 'pending') {
      return (_kPermit.withValues(alpha: .14), _kPermit, _kPermit);
    }
    return (
      scheme.surfaceContainerHighest.withValues(alpha: .15),
      scheme.onSurfaceVariant,
      null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  مفتاح ألوان التقويم
// ═══════════════════════════════════════════════════════════════════

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _LegendDot(color: _kPresent, label: 'حاضر'),
        _LegendDot(color: _kAbsent, label: 'غائب'),
        _LegendDot(color: _kLeave, label: 'إجازة'),
        _LegendDot(color: _kMission, label: 'مأمورية'),
        _LegendDot(color: _kConvoy, label: 'قافلة'),
        _LegendDot(color: _kPermit, label: 'معلّق'),
        _LegendDot(color: _kHoliday, label: 'عطلة/راحة'),
        _LegendDot(
          color: scheme.surfaceContainerHighest,
          label: 'يوم قادم',
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
        ],
      );
}

// ═══════════════════════════════════════════════════════════════════
//  ورقة تفاصيل + إجراءات اليوم
// ═══════════════════════════════════════════════════════════════════

class _DayActionSheet extends ConsumerWidget {
  const _DayActionSheet({
    required this.dayNum,
    required this.dayData,
    required this.date,
    required this.isFuture,
  });

  final int dayNum;
  final AttendanceStatementDay? dayData;
  final DateTime date;
  final bool isFuture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final d = dayData;
    final dateLabel = DateFormat('EEEE d MMMM y', 'ar').format(date);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── مؤشر السحب ──
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: .25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── عنوان اليوم ──
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text('$dayNum',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: scheme.onPrimaryContainer,
                        )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(height: 2),
                      if (d != null)
                        Row(children: [
                          MobileStatusPill(d.status),
                          if (d.shiftName.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(d.shiftName,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: scheme.onSurfaceVariant)),
                          ],
                        ])
                      else
                        Text(
                          isFuture ? 'يوم قادم' : 'لا توجد بيانات',
                          style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // ── تفاصيل اليوم (الماضي فقط) ──
            if (d != null && !isFuture) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              // حضور ← انصراف
              Row(
                children: [
                  Expanded(
                    child: _DetailItem(
                      icon: Icons.login,
                      label: 'الحضور',
                      value: _fmt(d.checkIn),
                      color: _kPresent,
                    ),
                  ),
                  Expanded(
                    child: _DetailItem(
                      icon: Icons.logout,
                      label: 'الانصراف',
                      value: _fmt(d.checkOut),
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (d.workHours > 0)
                    Expanded(
                      child: _DetailItem(
                        icon: Icons.timer_outlined,
                        label: 'ساعات',
                        value: d.workHours.toStringAsFixed(1),
                        color: scheme.primary,
                      ),
                    ),
                ],
              ),
              // تأخير / خروج مبكر / إضافي
              if (d.lateMinutes > 0 ||
                  d.earlyLeaveMinutes > 0 ||
                  d.overtimeMinutes > 0) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (d.lateMinutes > 0)
                      _SmallChip(
                          icon: Icons.schedule,
                          label: 'تأخير ${d.lateMinutes} د',
                          color: _kPermit),
                    if (d.earlyLeaveMinutes > 0)
                      _SmallChip(
                          icon: Icons.exit_to_app,
                          label: 'خروج مبكر ${d.earlyLeaveMinutes} د',
                          color: _kPermit),
                    if (d.overtimeMinutes > 0)
                      _SmallChip(
                          icon: Icons.more_time,
                          label: 'إضافي ${d.overtimeMinutes} د',
                          color: _kPresent),
                  ],
                ),
              ],
              // علامات
              if (d.hasLeave ||
                  d.hasPermit ||
                  d.hasMission ||
                  d.hasConvoyFundi ||
                  d.hasCorrection ||
                  d.missingCheckIn ||
                  d.missingCheckOut) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (d.hasLeave)
                      _SmallChip(
                          icon: Icons.beach_access,
                          label: 'إجازة',
                          color: _kLeave),
                    if (d.hasPermit)
                      _SmallChip(
                          icon: Icons.assignment_turned_in,
                          label: 'إذن',
                          color: _kPermit),
                    if (d.hasMission)
                      _SmallChip(
                          icon: Icons.directions_car,
                          label: 'مأمورية',
                          color: _kMission),
                    if (d.hasConvoyFundi)
                      _SmallChip(
                          icon: Icons.groups,
                          label: 'قافلة/فاندي',
                          color: _kConvoy),
                    if (d.hasCorrection)
                      _SmallChip(
                          icon: Icons.edit_note,
                          label: 'تصحيح',
                          color: _kHoliday),
                    if (d.missingCheckIn)
                      _SmallChip(
                          icon: Icons.warning_amber,
                          label: 'لم يسجل حضور',
                          color: _kAbsent),
                    if (d.missingCheckOut)
                      _SmallChip(
                          icon: Icons.warning_amber,
                          label: 'لم يسجل انصراف',
                          color: _kAbsent),
                  ],
                ),
              ],
              if (d.correctionNote != null &&
                  d.correctionNote!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('📝 ${d.correctionNote}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ],

            // ── إجراءات ──
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text('إجراءات متاحة',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ..._actions(context, ref),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final list = <Widget>[];
    final d = dayData;
    final isAbsent = d != null &&
        (d.status == 'غائب' ||
            d.status == 'غائب دون إذن' ||
            d.status == 'absent');
    final hasMissing =
        d != null && (d.missingCheckIn || d.missingCheckOut);

    // 1. نسيان بصمة (يوم ماضي غائب أو ناقص بصمة)
    if (!isFuture && (isAbsent || hasMissing)) {
      list.add(_ActionRow(
        icon: Icons.fingerprint_rounded,
        label: 'تصحيح حضور (نسيان بصمة)',
        color: _kAbsent,
        onTap: () {
          Navigator.pop(context);
          _submitCorrection(context, ref);
        },
      ));
    }

    // 2. طلب إجازة — أي يوم
    list.add(_ActionRow(
      icon: Icons.beach_access_rounded,
      label: isFuture
          ? 'طلب إجازة لهذا اليوم'
          : 'طلب إجازة لتغطية هذا اليوم',
      color: _kLeave,
      onTap: () {
        Navigator.pop(context);
        _submitRequest(context, ref, 'leave');
      },
    ));

    // 3. إذن حضور (تأخير)
    if (isFuture || (d != null && d.lateMinutes > 0)) {
      list.add(_ActionRow(
        icon: Icons.access_time_rounded,
        label: 'طلب إذن حضور (تأخير)',
        color: _kPermit,
        onTap: () {
          Navigator.pop(context);
          _submitRequest(context, ref, 'permit',
              permitKind: 'late_arrival');
        },
      ));
    }

    // 4. إذن انصراف (خروج مبكر)
    if (isFuture || (d != null && d.earlyLeaveMinutes > 0)) {
      list.add(_ActionRow(
        icon: Icons.exit_to_app_rounded,
        label: 'طلب إذن انصراف (خروج مبكر)',
        color: _kPartial,
        onTap: () {
          Navigator.pop(context);
          _submitRequest(context, ref, 'permit',
              permitKind: 'early_departure');
        },
      ));
    }

    return list;
  }

  String _fmt(String? t) =>
      (t == null || t.length < 5) ? '—' : t.substring(0, 5);

  // ── تصحيح حضور ──
  void _submitCorrection(BuildContext context, WidgetRef ref) async {
    final d = dayData;
    final corrType = d != null && d.missingCheckOut
        ? 'missing_check_out'
        : 'missing_check_in';

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuickCorrectionSheet(
        workDate: date,
        correctionType: corrType,
      ),
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(mobileCommandsProvider).requestAttendanceCorrection(
            workDate: result['workDate'] as DateTime,
            type: result['type'] as String,
            reason: result['reason'] as String,
            checkIn: result['checkIn'] as DateTime?,
            checkOut: result['checkOut'] as DateTime?,
          );
      ref.invalidate(mobileRequestsProvider);
      ref.invalidate(myMonthlyStatementProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب التصحيح بنجاح.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    }
  }

  // ── طلب إجازة أو إذن ──
  void _submitRequest(
    BuildContext context,
    WidgetRef ref,
    String type, {
    String? permitKind,
  }) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuickRequestSheet(
        type: type,
        prefilledDate: date,
        permitKind: permitKind,
      ),
    );
    if (result == null || !context.mounted) return;

    var resolvedType = type;
    if (type == 'permit') {
      final kind = (result['payload'] as Map<String, dynamic>)['permitKind']
          as String?;
      resolvedType =
          kind == 'early_departure' ? 'early_permit' : 'late_permit';
    }

    try {
      await ref.read(mobileCommandsProvider).submitRequest(
            resolvedType,
            result['title'] as String,
            result['reason'] as String,
            result['payload'] as Map<String, dynamic>,
          );
      ref.invalidate(mobileRequestsProvider);
      ref.invalidate(employeeHomeProvider);
      ref.invalidate(myMonthlyStatementProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الطلب بنجاح.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  نموذج طلب سريع (إجازة / إذن) — تاريخ مملوء مسبقًا
// ═══════════════════════════════════════════════════════════════════

class _QuickRequestSheet extends StatefulWidget {
  const _QuickRequestSheet({
    required this.type,
    required this.prefilledDate,
    this.permitKind,
  });
  final String type;
  final DateTime prefilledDate;
  final String? permitKind;

  @override
  State<_QuickRequestSheet> createState() => _QuickRequestSheetState();
}

class _QuickRequestSheetState extends State<_QuickRequestSheet> {
  final _titleCtl = TextEditingController();
  final _reasonCtl = TextEditingController();
  late DateTime _startDate;
  late DateTime _endDate;
  String _leaveType = 'annual';
  late String _permitKind;

  @override
  void initState() {
    super.initState();
    _startDate = widget.prefilledDate;
    _endDate = widget.prefilledDate;
    _permitKind = widget.permitKind ?? 'late_arrival';

    // عنوان تلقائي حسب النوع
    final dateFmt = DateFormat('d/M', 'ar').format(widget.prefilledDate);
    if (widget.type == 'leave') {
      _titleCtl.text = 'طلب إجازة — $dateFmt';
    } else if (widget.type == 'permit') {
      _titleCtl.text = _permitKind == 'early_departure'
          ? 'إذن انصراف — $dateFmt'
          : 'إذن حضور — $dateFmt';
    }
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _reasonCtl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtl.text.trim();
    final reason = _reasonCtl.text.trim();
    if (title.length < 3 || reason.length < 3 || reason.length > 300) return;

    final Map<String, dynamic> payload;
    if (widget.type == 'leave') {
      payload = {
        'leaveType': _leaveType,
        'startDate': _startDate.toIso8601String().substring(0, 10),
        'endDate': _endDate.toIso8601String().substring(0, 10),
      };
    } else {
      // permit
      payload = {
        'permitDate':
            widget.prefilledDate.toIso8601String().substring(0, 10),
        'minutes': 120,
        'permitKind': _permitKind,
      };
    }
    Navigator.pop(context, {
      'title': title,
      'reason': reason,
      'payload': payload,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isLeave = widget.type == 'leave';
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: bottomInset > 0 ? bottomInset + 16 : 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isLeave ? 'طلب إجازة' : 'طلب إذن',
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _titleCtl,
            decoration: const InputDecoration(
              labelText: 'عنوان الطلب',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          if (isLeave) ...[
            DropdownButtonFormField<String>(
              value: _leaveType,
              decoration: const InputDecoration(
                labelText: 'نوع الإجازة',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'annual', child: Text('سنوية')),
                DropdownMenuItem(value: 'casual', child: Text('طارئة')),
                DropdownMenuItem(value: 'sick', child: Text('مرضية')),
                DropdownMenuItem(
                    value: 'unpaid', child: Text('بدون راتب')),
              ],
              onChanged: (v) => setState(() => _leaveType = v!),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 30)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('ar'),
                      );
                      if (picked != null) {
                        setState(() {
                          _startDate = picked;
                          if (_endDate.isBefore(picked)) _endDate = picked;
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('d/M/y').format(_startDate)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: _startDate,
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('ar'),
                      );
                      if (picked != null) setState(() => _endDate = picked);
                    },
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('d/M/y').format(_endDate)),
                  ),
                ),
              ],
            ),
          ] else ...[
            // permit
            DropdownButtonFormField<String>(
              value: _permitKind,
              decoration: const InputDecoration(
                labelText: 'نوع الإذن',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'late_arrival', child: Text('إذن حضور')),
                DropdownMenuItem(
                    value: 'early_departure',
                    child: Text('إذن انصراف')),
              ],
              onChanged: (v) => setState(() => _permitKind = v!),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: .25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'التاريخ: ${DateFormat('d/M/y').format(widget.prefilledDate)} · كل إذن ساعتين كاملة · 4 أذونات شهريًا',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonCtl,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'السبب',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  نموذج تصحيح حضور سريع — تاريخ مملوء مسبقًا
// ═══════════════════════════════════════════════════════════════════

class _QuickCorrectionSheet extends StatefulWidget {
  const _QuickCorrectionSheet({
    required this.workDate,
    required this.correctionType,
  });
  final DateTime workDate;
  final String correctionType;

  @override
  State<_QuickCorrectionSheet> createState() => _QuickCorrectionSheetState();
}

class _QuickCorrectionSheetState extends State<_QuickCorrectionSheet> {
  final _reasonCtl = TextEditingController();
  TimeOfDay? _time;
  late String _type;

  @override
  void initState() {
    super.initState();
    _type = widget.correctionType;
  }

  @override
  void dispose() {
    _reasonCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: bottomInset > 0 ? bottomInset + 16 : 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'تصحيح حضور',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'التاريخ: ${DateFormat('EEEE d MMMM', 'ar').format(widget.workDate)}',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(
              labelText: 'نوع التصحيح',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: 'missing_check_in',
                  child: Text('نسيان بصمة حضور')),
              DropdownMenuItem(
                  value: 'missing_check_out',
                  child: Text('نسيان بصمة انصراف')),
            ],
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime:
                    _time ?? const TimeOfDay(hour: 8, minute: 0),
              );
              if (picked != null) setState(() => _time = picked);
            },
            icon: const Icon(Icons.access_time, size: 18),
            label: Text(
              _time == null
                  ? 'الوقت التقريبي'
                  : 'الوقت: ${_time!.format(context)}',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonCtl,
            maxLines: 2,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'السبب',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (_reasonCtl.text.trim().length < 3) return;
              DateTime? checkIn;
              DateTime? checkOut;
              if (_time != null) {
                final dt = DateTime(
                  widget.workDate.year,
                  widget.workDate.month,
                  widget.workDate.day,
                  _time!.hour,
                  _time!.minute,
                );
                if (_type == 'missing_check_in') {
                  checkIn = dt;
                } else {
                  checkOut = dt;
                }
              }
              Navigator.pop(context, {
                'workDate': widget.workDate,
                'type': _type,
                'reason': _reasonCtl.text.trim(),
                'checkIn': checkIn,
                'checkOut': checkOut,
              });
            },
            child: const Text('إرسال طلب التصحيح'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ويدجتات مساعدة صغيرة
// ═══════════════════════════════════════════════════════════════════

/// عنصر تفصيلي (أيقونة + تسمية + قيمة) — داخل ورقة اليوم
class _DetailItem extends StatelessWidget {
  const _DetailItem({
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
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 2),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}

/// صف إجراء (أيقونة + نص + سهم)
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: color,
                      )),
                ),
                Icon(Icons.chevron_left,
                    size: 20, color: color.withValues(alpha: .6)),
              ],
            ),
          ),
        ),
      );
}

/// شريحة صغيرة (chip) — أيقونة + نص
class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
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
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════
//  ويدجتات البطاقات (لم تتغير)
// ═══════════════════════════════════════════════════════════════════

class _EmployeeHeader extends StatelessWidget {
  const _EmployeeHeader({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.person_outline,
                      color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(statement.employeeNameAr,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      if (statement.employeeCode != null)
                        Text('كود: ${statement.employeeCode}',
                            style: muted),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _InfoRow(
                icon: Icons.work_outline,
                label: 'المسمى الوظيفي',
                value: statement.jobTitle),
            _InfoRow(
                icon: Icons.business_outlined,
                label: 'القسم',
                value: statement.department),
            _InfoRow(
                icon: Icons.location_city_outlined,
                label: 'الفرع',
                value: statement.branch),
            _InfoRow(
                icon: Icons.supervisor_account_outlined,
                label: 'المدير المباشر',
                value: statement.manager),
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
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$label: ', style: muted),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}

class _AttendancePercentageCard extends StatelessWidget {
  const _AttendancePercentageCard({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final pct = statement.attendancePercentage;
    final s = statement.summary;
    final scheme = Theme.of(context).colorScheme;
    final pctColor = pct >= 90
        ? _kPresent
        : pct >= 75
            ? _kPermit
            : scheme.error;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          children: [
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
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              color: pctColor)),
                      Text('حضور',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('نسبة الحضور الشهرية',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  _PctRow(label: 'أيام مجدولة', value: '${s.scheduledDays}'),
                  _PctRow(label: 'أيام حضور', value: '${s.presentDays}'),
                  _PctRow(
                      label: 'أيام عطل رسمية',
                      value: '${s.holidayDays}'),
                  _PctRow(label: 'أيام راحة', value: '${s.restDays}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PctRow extends StatelessWidget {
  const _PctRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );
}

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
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile(
      {required this.label, required this.value, required this.unit});
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
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 18)),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(unit,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
