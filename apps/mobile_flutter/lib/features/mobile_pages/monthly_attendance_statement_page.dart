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

// رؤوس أيام الأسبوع (يبدأ بالسبت — معيار المؤسسة)
const _weekDayHeaders = ['سبت', 'أحد', 'إثن', 'ثلا', 'أرب', 'خمي', 'جمع'];

/// كشف الحضور والانصراف الشهري — للموظف عن نفسه (V12 §18)،
/// وعند تمرير [employeeId] يُعرض كشف موظف محدد (مدير مباشر/HR) (V22).
class MonthlyAttendanceStatementPage extends ConsumerStatefulWidget {
  const MonthlyAttendanceStatementPage({
    this.employeeId,
    this.employeeName,
    super.key,
  });

  /// عند تمريره يُحمل كشف هذا الموظف بدلًا من كشف المستخدم الحالي.
  final String? employeeId;
  final String? employeeName;

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

  AsyncValue<MonthlyAttendanceStatement> _statement(WidgetRef ref) =>
      widget.employeeId == null
          ? ref.watch(myMonthlyStatementProvider((_year, _month)))
          : ref.watch(
              employeeMonthlyStatementProvider(
                (widget.employeeId!, _year, _month),
              ),
            );

  void _reload(WidgetRef ref) => widget.employeeId == null
      ? ref.invalidate(myMonthlyStatementProvider((_year, _month)))
      : ref.invalidate(
          employeeMonthlyStatementProvider((widget.employeeId!, _year, _month)),
        );

  @override
  Widget build(BuildContext context) {
    final statement = _statement(ref);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employeeName ?? 'كشف الحضور والانصراف'),
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
          onRefresh: () async => _reload(ref),
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
                    onPressed: () => _reload(ref),
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

        // ───── التقويم الشهري ─────
        Text('التقويم الشهري',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('اضغط على أي يوم لعرض التفاصيل والإجراءات المتاحة.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        _MonthlyCalendarGrid(
          statement: statement,
          days: statement.days,
          year: statement.year,
          month: statement.month,
        ),

        // ───── دليل الألوان ─────
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _LegendDot(color: const Color(0xFF0F9F6E), label: 'حضور'),
            _LegendDot(color: const Color(0xFFDC3D4B), label: 'غياب'),
            _LegendDot(color: const Color(0xFF6366F1), label: 'إجازة'),
            _LegendDot(color: const Color(0xFFF59E0B), label: 'مراجعة'),
            _LegendDot(color: const Color(0xFF90A4AE), label: 'راحة/عطلة'),
            _LegendDot(color: const Color(0xFF0EA5E9), label: 'مأمورية'),
            _LegendDot(color: const Color(0xFF8B5CF6), label: 'قافلة/فاندي'),
            _LegendDot(color: const Color(0xFFBDBDBD), label: 'قادم'),
          ],
        ),
        const SizedBox(height: 24),
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

// ─── التقويم الشهري (شبكة 7 أعمدة) ────────────────────────────────

class _MonthlyCalendarGrid extends StatelessWidget {
  const _MonthlyCalendarGrid({
    required this.statement,
    required this.days,
    required this.year,
    required this.month,
  });
  final MonthlyAttendanceStatement statement;
  final List<AttendanceStatementDay> days;
  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final isCurrentMonth = today.year == year && today.month == month;

    // بناء خريطة الأيام (رقم اليوم → بيانات اليوم)
    final dayMap = <int, AttendanceStatementDay>{};
    for (final d in days) {
      final parsed = DateTime.tryParse(d.date);
      if (parsed != null) dayMap[parsed.day] = d;
    }

    // حساب أول يوم في الشهر وعدد الأيام
    final firstOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;

    // عمود اليوم الأول (السبت = 0, الأحد = 1, ... الجمعة = 6)
    final firstWeekdayCol = (firstOfMonth.weekday + 1) % 7;

    // عدد الصفوف المطلوبة
    final totalCells = firstWeekdayCol + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // ─ رأس الأسبوع ─
            Row(
              children: _weekDayHeaders.map((h) => Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(h, style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    )),
                  ),
                ),
              )).toList(),
            ),
            // ─ صفوف الأيام ─
            ...List.generate(rows, (row) {
              return Row(
                children: List.generate(7, (col) {
                  final cellIndex = row * 7 + col;
                  final dayNum = cellIndex - firstWeekdayCol + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 48));
                  }
                  final dayData = dayMap[dayNum];
                  final isToday = isCurrentMonth && today.day == dayNum;
                  final dayDate = DateTime(year, month, dayNum);
                  final isFuture = dayDate.isAfter(
                    DateTime(today.year, today.month, today.day),
                  );
                  return Expanded(
                    child: _CalendarDayCell(
                      statement: statement,
                      dayNum: dayNum,
                      dayData: dayData,
                      isToday: isToday,
                      isFuture: isFuture,
                      year: year,
                      month: month,
                    ),
                  );
                }),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─── خلية يوم في التقويم ────────────────────────────────────────────

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.statement,
    required this.dayNum,
    required this.dayData,
    required this.isToday,
    required this.isFuture,
    required this.year,
    required this.month,
  });
  final MonthlyAttendanceStatement statement;
  final int dayNum;
  final AttendanceStatementDay? dayData;
  final bool isToday;
  final bool isFuture;
  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _resolveStyle(scheme);

    return Semantics(
      button: true,
      label: 'يوم $dayNum${dayData?.status != null ? " - ${dayData!.status}" : ""}',
      child: GestureDetector(
        onTap: () => _showDayDetail(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: style.bg,
            borderRadius: BorderRadius.circular(12),
            border: isToday
                ? Border.all(color: style.accent, width: 2.5)
                : Border.all(color: style.accent.withValues(alpha: .25)),
            boxShadow: isToday
                ? [
                    BoxShadow(
                      color: style.accent.withValues(alpha: .3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // رقم اليوم — داخل دائرة ممتلئة لليوم الحالي
              if (isToday)
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.accent,
                  ),
                  child: Text(
                    '$dayNum',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                )
              else
                Text(
                  '$dayNum',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: style.fg,
                    height: 1.1,
                  ),
                ),
              const SizedBox(height: 4),
              // نقطة الحالة الملوّنة (بدل الأيقونة الصغيرة)
              if (style.dot != null)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.dot,
                  ),
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  /// هوية لونية موحّدة لكل حالة: خلفية فاتحة + نص داكن + لون مميّز (حدود/دائرة اليوم) + نقطة صغيرة
  ({Color bg, Color fg, Color accent, Color? dot}) _resolveStyle(
      ColorScheme scheme) {
    // أيام مستقبلية — مظلّلة بهدوء بدون أي حالة
    if (isFuture) {
      return (
        bg: scheme.surfaceContainerLow,
        fg: scheme.onSurface.withValues(alpha: .25),
        accent: scheme.surfaceContainerLow,
        dot: null,
      );
    }
    if (dayData == null) {
      return (
        bg: scheme.surfaceContainerLow,
        fg: scheme.onSurfaceVariant.withValues(alpha: .5),
        accent: scheme.surfaceContainerLow,
        dot: null,
      );
    }
    final d = dayData!;
    final status = d.status;
    // غائب دون إذن — أحمر
    if (status == 'غائب دون إذن') {
      return (
        bg: const Color(0xFFFDECEA),
        fg: const Color(0xFFBA1A1A),
        accent: const Color(0xFFDC3D4B),
        dot: const Color(0xFFDC3D4B),
      );
    }
    // يحتاج مراجعة — كهرمان
    if (status == 'يحتاج مراجعة') {
      return (
        bg: const Color(0xFFFFF4E5),
        fg: const Color(0xFF9A5B00),
        accent: const Color(0xFFF59E0B),
        dot: const Color(0xFFF59E0B),
      );
    }
    // إجازة — نيلي
    if (d.hasLeave) {
      return (
        bg: const Color(0xFFEEF0FB),
        fg: const Color(0xFF3D4FA8),
        accent: const Color(0xFF6366F1),
        dot: const Color(0xFF6366F1),
      );
    }
    // مأمورية — سماوي
    if (d.hasMission) {
      return (
        bg: const Color(0xFFE5F6FB),
        fg: const Color(0xFF0B6B80),
        accent: const Color(0xFF0EA5E9),
        dot: const Color(0xFF0EA5E9),
      );
    }
    // قافلة/فاندي — بنفسجي
    if (d.hasConvoyFundi) {
      return (
        bg: const Color(0xFFF4ECF8),
        fg: const Color(0xFF6D3FA0),
        accent: const Color(0xFF8B5CF6),
        dot: const Color(0xFF8B5CF6),
      );
    }
    // عطلة رسمية — بنفسجي باهت بدون نقطة
    if (status == 'عطلة رسمية') {
      return (
        bg: const Color(0xFFF4ECF8),
        fg: const Color(0xFF8A6BB5),
        accent: const Color(0xFFDCCBEE),
        dot: null,
      );
    }
    // راحة أسبوعية — رمادي مزرقّ بدون نقطة
    if (status == 'راحة' || status == 'راحة أسبوعية') {
      return (
        bg: const Color(0xFFF4F6F7),
        fg: const Color(0xFF90A0A8),
        accent: const Color(0xFFE1E7EA),
        dot: null,
      );
    }
    // حاضر — أخضر (ومؤشر تأخير كهرماني إن وُجد)
    if (status == 'حاضر') {
      final late = d.lateMinutes > 0;
      return (
        bg: late ? const Color(0xFFFFF9E9) : const Color(0xFFE9F7F0),
        fg: late ? const Color(0xFF9A5B00) : const Color(0xFF15734F),
        accent: late ? const Color(0xFFF59E0B) : const Color(0xFF0F9F6E),
        dot: late ? const Color(0xFFF59E0B) : const Color(0xFF0F9F6E),
      );
    }
    return (
      bg: scheme.surfaceContainerHighest,
      fg: scheme.onSurfaceVariant,
      accent: scheme.outlineVariant.withValues(alpha: .4),
      dot: null,
    );
  }

  void _showDayDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DayDetailSheet(
        statement: statement,
        day: dayData,
        dayNum: dayNum,
        isFuture: isFuture,
        isToday: isToday,
        year: year,
        month: month,
      ),
    );
  }
}

// ─── ورقة تفاصيل اليوم + الإجراءات ─────────────────────────────────

class _DayDetailSheet extends ConsumerWidget {
  const _DayDetailSheet({
    required this.statement,
    required this.day,
    required this.dayNum,
    required this.isFuture,
    required this.isToday,
    required this.year,
    required this.month,
  });
  final MonthlyAttendanceStatement statement;
  final AttendanceStatementDay? day;
  final int dayNum;
  final bool isFuture;
  final bool isToday;
  final int year;
  final int month;

  static const _warn = {'غائب دون إذن', 'يحتاج مراجعة'};

  String get _dateStr =>
      '$year-${month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // 0449: عرض الوقت بنظام 12 ساعة مع ص/م بدل اقتطاع HH24 الخام
    String fmt(String? t) {
      if (t == null || t.length < 5) return '—';
      final h = int.tryParse(t.substring(0, 2));
      final m = int.tryParse(t.substring(3, 5));
      if (h == null || m == null) return '—';
      final period = h < 12 ? 'ص' : 'م';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:${m.toString().padLeft(2, '0')} $period';
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // ─ المقبض ─
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ─ رأس: التاريخ + الحالة ─
            Row(
              children: [
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('اليوم', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: scheme.onPrimary,
                    )),
                  ),
                Expanded(
                  child: Text(
                    '${day?.dayNameAr ?? _dayNameFull} $_dateStr',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                MobileStatusPill(isFuture ? 'scheduled' : _statusPillKey),
              ],
            ),

            const SizedBox(height: 16),

            if (day?.hasAdminOverride == true) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF0FB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF6366F1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تعديل إداري مسجل: ${day?.adminOverride?['dayType'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF3D4FA8)),
                          ),
                          if (day?.adminOverride?['reason'] != null)
                            Text(
                              'السبب: ${day!.adminOverride!['reason']}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ─ بطاقة الحضور/الانصراف (أيام فائتة فقط) ─
            if (!isFuture && day != null) ...[
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        // حضور
                        Expanded(
                          child: Column(
                            children: [
                              const Icon(Icons.login, size: 20, color: Color(0xFF0F9F6E)),
                              const SizedBox(height: 4),
                              Text('حضور', style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant),
                                textDirection: TextDirection.rtl),
                              Text(fmt(day!.checkIn), style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward, size: 16, color: scheme.onSurfaceVariant),
                        // انصراف
                        Expanded(
                          child: Column(
                            children: [
                              Icon(Icons.logout, size: 20, color: scheme.onSurfaceVariant),
                              const SizedBox(height: 4),
                              Text('انصراف', style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant),
                                textDirection: TextDirection.rtl),
                              Text(fmt(day!.checkOut), style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                            ],
                          ),
                        ),
                        // ساعات العمل
                        if (day!.workHours > 0) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text(day!.workHours.toStringAsFixed(1),
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16,
                                        color: scheme.onPrimaryContainer)),
                                Text('ساعة', style: TextStyle(fontSize: 10,
                                    color: scheme.onPrimaryContainer),
                                    textDirection: TextDirection.rtl),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ─ تفاصيل المخالفات والعلامات ─
            if (day != null && _hasDetails) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (day!.lateMinutes > 0)
                    _DetailChip(icon: Icons.schedule, label: 'تأخير ${day!.lateMinutes} د',
                        color: _warn.contains(day!.status) ? scheme.error : const Color(0xFFF59E0B)),
                  if (day!.earlyLeaveMinutes > 0)
                    _DetailChip(icon: Icons.exit_to_app, label: 'خروج مبكر ${day!.earlyLeaveMinutes} د',
                        color: const Color(0xFFF59E0B)),
                  if (day!.overtimeMinutes > 0)
                    _DetailChip(icon: Icons.more_time, label: 'إضافي ${day!.overtimeMinutes} د',
                        color: const Color(0xFF0F9F6E)),
                  if (day!.hasLeave)
                    _DetailChip(icon: Icons.beach_access, label: 'إجازة', color: const Color(0xFF6366F1)),
                  if (day!.hasPermit)
                    _DetailChip(icon: Icons.assignment_turned_in, label: 'إذن', color: const Color(0xFFF59E0B)),
                  if (day!.hasMission)
                    _DetailChip(icon: Icons.directions_car, label: 'مأمورية', color: const Color(0xFF0EA5E9)),
                  if (day!.hasConvoyFundi)
                    _DetailChip(icon: Icons.groups, label: 'قافلة/فاندي', color: const Color(0xFF8B5CF6)),
                  if (day!.missingCheckIn)
                    _DetailChip(icon: Icons.warning_amber, label: 'لم يسجل حضور', color: scheme.error),
                  if (day!.missingCheckOut)
                    _DetailChip(icon: Icons.warning_amber, label: 'لم يسجل انصراف', color: scheme.error),
                  if (day!.hasCorrection)
                    _DetailChip(icon: Icons.edit_note, label: 'تصحيح', color: const Color(0xFF64748B)),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // ─ ملاحظة التصحيح ─
            if (day?.correctionNote != null && day!.correctionNote!.isNotEmpty) ...[
              Text('📝 ${day!.correctionNote}',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
            ],

            // ─ الإجراءات المتاحة ─
            const Divider(height: 24),
            Text('الإجراءات المتاحة',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: scheme.primary)),
            const SizedBox(height: 10),
            ..._buildActions(context, ref, scheme),
          ],
        );
      },
    );
  }

  String get _statusPillKey {
    if (day == null) return 'absent';
    final s = day!.status;
    if (s == 'حاضر') return 'present';
    if (s == 'غائب دون إذن') return 'absent';
    if (s == 'عطلة رسمية') return 'holiday';
    if (s == 'راحة' || s == 'راحة أسبوعية') return 'rest';
    if (s == 'يحتاج مراجعة') return 'flagged';
    if (day!.hasLeave) return 'on_leave';
    if (day!.hasMission) return 'mission';
    if (day!.hasConvoyFundi) return 'convoy_fundi';
    return 'unregistered';
  }

  /// اسم اليوم كاملاً — من الـ backend، أو احتياطي محلي مضبوط على weekday الصحيح
  String get _dayNameFull {
    final fromServer = day?.dayNameAr.trim() ?? '';
    if (fromServer.isNotEmpty) return fromServer;
    const names = {
      1: 'الاثنين', 2: 'الثلاثاء', 3: 'الأربعاء', 4: 'الخميس',
      5: 'الجمعة', 6: 'السبت', 7: 'الأحد',
    };
    return names[DateTime(year, month, dayNum).weekday] ?? '';
  }

  bool get _hasDetails => day != null && (
      day!.lateMinutes > 0 || day!.earlyLeaveMinutes > 0 || day!.overtimeMinutes > 0 ||
      day!.hasLeave || day!.hasPermit || day!.hasMission || day!.hasConvoyFundi ||
      day!.missingCheckIn || day!.missingCheckOut || day!.hasCorrection);

  List<Widget> _buildActions(BuildContext context, WidgetRef ref, ColorScheme scheme) {
    final actions = <Widget>[];

    // ── يوم ماضٍ غائب → طلب إجازة أو نسيان بصمة ──
    if (!isFuture && day != null && day!.status == 'غائب دون إذن') {
      actions.add(_ActionTile(
        icon: Icons.beach_access_outlined,
        label: 'طلب إجازة لتغطية هذا اليوم',
        subtitle: 'تقديم طلب إجازة بأثر رجعي يعتمده المدير المباشر.',
        color: const Color(0xFF6366F1),
        onTap: () => _openLeaveRequest(context, ref),
      ));
      actions.add(_ActionTile(
        icon: Icons.fingerprint,
        label: 'نسيان بصمة',
        subtitle: 'طلب تصحيح حضور — يُراجَع ويُعتمَد من المدير.',
        color: const Color(0xFFDC3D4B),
        onTap: () => _openCorrectionRequest(context, ref),
      ));
    }

    // ── نسيان بصمة (حضور أو انصراف) وليس غائباً بالكامل ──
    if (!isFuture && day != null && day!.status != 'غائب دون إذن' &&
        (day!.missingCheckIn || day!.missingCheckOut)) {
      actions.add(_ActionTile(
        icon: Icons.fingerprint,
        label: 'تسجيل بصمة منسية',
        subtitle: day!.missingCheckIn ? 'نسيان بصمة الحضور.' : 'نسيان بصمة الانصراف.',
        color: const Color(0xFFDC3D4B),
        onTap: () => _openCorrectionRequest(context, ref),
      ));
    }

    // ── تأخير → إذن حضور ──
    if (!isFuture && day != null && day!.lateMinutes > 0 && !day!.hasPermit) {
      actions.add(_ActionTile(
        icon: Icons.schedule,
        label: 'طلب إذن حضور',
        subtitle: 'تغطية ${day!.lateMinutes} دقيقة تأخير بإذن مُعتمَد.',
        color: const Color(0xFFF59E0B),
        onTap: () => _openPermitRequest(context, ref, 'late_arrival'),
      ));
    }

    // ── خروج مبكر → إذن انصراف ──
    if (!isFuture && day != null && day!.earlyLeaveMinutes > 0 && !day!.hasPermit) {
      actions.add(_ActionTile(
        icon: Icons.exit_to_app,
        label: 'طلب إذن انصراف',
        subtitle: 'تغطية ${day!.earlyLeaveMinutes} دقيقة خروج مبكر.',
        color: const Color(0xFFF59E0B),
        onTap: () => _openPermitRequest(context, ref, 'early_departure'),
      ));
    }

    // ── يوم قادم → طلب إجازة مسبقة ──
    if (isFuture) {
      actions.add(_ActionTile(
        icon: Icons.beach_access_outlined,
        label: 'طلب إجازة مسبقة',
        subtitle: 'تقديم طلب إجازة لهذا اليوم — يعتمده المدير المباشر.',
        color: const Color(0xFF6366F1),
        onTap: () => _openLeaveRequest(context, ref),
      ));
    }

    // ── إجراءات المدير / المشرف المعتمد (تعديل اليوم إدارياً أو إلغاؤه) ──
    if (statement.canEditDays) {
      actions.add(_ActionTile(
        icon: Icons.edit_calendar_rounded,
        label: 'تعديل اليوم إدارياً (حالة اليوم وساعات العمل)',
        subtitle: 'تعديل نوع اليوم إلى عمل أو إجازة أو مأمورية أو ضبط الساعات.',
        color: scheme.primary,
        onTap: () => _openAdminEditDaySheet(context, ref),
      ));
    }

    if (day?.hasAdminOverride == true && statement.canEditDays) {
      actions.add(_ActionTile(
        icon: Icons.restart_alt_rounded,
        label: 'إلغاء التعديل الإداري والعودة لاحتساب النظام',
        subtitle: 'حذف الاستثناء الإداري واستعادة الاحتساب التلقائي للبصمات.',
        color: scheme.error,
        onTap: () => _revertAdminOverride(context, ref),
      ));
    }

    if (actions.isEmpty) {
      actions.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text('لا توجد إجراءات متاحة لهذا اليوم.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ));
    }

    return actions;
  }

  // ── إلغاء التعديل الإداري والعودة لاحتساب النظام ──
  Future<void> _revertAdminOverride(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء التعديل الإداري'),
        content: const Text(
          'هل أنت متأكد من رغبتك في إلغاء التعديل الإداري والعودة لاحتساب النظام الأصلي للبصمات؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.pop(context);
    try {
      final empId = statement.employeeId;
      await ref.read(mobileCommandsProvider).clearAttendanceDayAdmin(
            employeeId: empId,
            date: _dateStr,
          );
      _invalidateProviders(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء التعديل الإداري واستعادة احتساب النظام.')),
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

  // ── فتح ورقة التعديل الإداري ──
  Future<void> _openAdminEditDaySheet(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AdminEditDaySheet(
        statement: statement,
        day: day,
        dateStr: _dateStr,
        dayNum: dayNum,
        year: year,
        month: month,
      ),
    );
    if (result == true) {
      _invalidateProviders(ref);
    }
  }

  // ── فتح نموذج طلب إجازة سريع ──
  Future<void> _openLeaveRequest(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context); // إغلاق ورقة التفاصيل
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuickLeaveSheet(dateStr: _dateStr),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(mobileCommandsProvider).submitRequest(
            'leave',
            result['title'] as String,
            result['reason'] as String,
            result['payload'] as Map<String, dynamic>,
          );
      _invalidateProviders(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب الإجازة بنجاح.')),
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

  // ── فتح نموذج تصحيح حضور سريع ──
  Future<void> _openCorrectionRequest(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    final preselect = (day?.missingCheckOut == true && day?.missingCheckIn != true)
        ? 'missing_check_out'
        : 'missing_check_in';
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuickCorrectionSheet(
        dateStr: _dateStr,
        preselectType: preselect,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(mobileCommandsProvider).requestAttendanceCorrection(
            workDate: DateTime.parse(_dateStr),
            type: result['type'] as String,
            reason: result['reason'] as String,
          );
      _invalidateProviders(ref);
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

  // ── فتح نموذج إذن سريع ──
  Future<void> _openPermitRequest(
      BuildContext context, WidgetRef ref, String permitKind) async {
    Navigator.pop(context);
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuickPermitSheet(
        dateStr: _dateStr,
        permitKind: permitKind,
      ),
    );
    if (result == null || !context.mounted) return;
    final resolvedType = permitKind == 'early_departure' ? 'early_permit' : 'late_permit';
    try {
      await ref.read(mobileCommandsProvider).submitRequest(
            resolvedType,
            result['title'] as String,
            result['reason'] as String,
            result['payload'] as Map<String, dynamic>,
          );
      _invalidateProviders(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب الإذن بنجاح.')),
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

  void _invalidateProviders(WidgetRef ref) {
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(myMonthlyStatementProvider((year, month)));
    if (statement.employeeId.isNotEmpty) {
      ref.invalidate(
        employeeMonthlyStatementProvider(
          (statement.employeeId, year, month),
        ),
      );
    }
  }
}

// ─── بطاقة إجراء ────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14, color: color)),
                      Text(subtitle, style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── نموذج طلب إجازة سريع ───────────────────────────────────────────

class _QuickLeaveSheet extends StatefulWidget {
  const _QuickLeaveSheet({required this.dateStr});
  final String dateStr;
  @override
  State<_QuickLeaveSheet> createState() => _QuickLeaveSheetState();
}

class _QuickLeaveSheetState extends State<_QuickLeaveSheet> {
  final _reasonCtrl = TextEditingController();
  String _leaveType = 'annual';

  static const _leaveTypes = {
    'annual': 'سنوية',
    'casual': 'عارضة',
    'sick': 'مرضية',
    'unpaid': 'بدون راتب',
  };

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),
          Text('طلب إجازة', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900, color: scheme.primary)),
          const SizedBox(height: 4),
          Text('اليوم: ${widget.dateStr}', style: TextStyle(
            fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _leaveType,
            decoration: const InputDecoration(
              labelText: 'نوع الإجازة',
              isDense: true,
            ),
            items: _leaveTypes.entries.map((e) =>
              DropdownMenuItem(value: e.key, child: Text(e.value)),
            ).toList(),
            onChanged: (v) => setState(() => _leaveType = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'السبب',
              hintText: 'اكتب سبب طلب الإجازة...',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send),
            label: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال سبب الطلب (3 أحرف على الأقل)')),
      );
      return;
    }
    Navigator.pop(context, {
      'title': 'طلب إجازة ${_leaveTypes[_leaveType]} — ${widget.dateStr}',
      'reason': reason,
      'payload': {
        'leaveType': _leaveType,
        'startDate': widget.dateStr,
        'endDate': widget.dateStr,
      },
    });
  }
}

// ─── نموذج تصحيح حضور سريع ──────────────────────────────────────────

class _QuickCorrectionSheet extends StatefulWidget {
  const _QuickCorrectionSheet({
    required this.dateStr,
    required this.preselectType,
  });
  final String dateStr;
  final String preselectType;
  @override
  State<_QuickCorrectionSheet> createState() => _QuickCorrectionSheetState();
}

class _QuickCorrectionSheetState extends State<_QuickCorrectionSheet> {
  final _reasonCtrl = TextEditingController();
  late String _type;

  @override
  void initState() {
    super.initState();
    _type = widget.preselectType;
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),
          Text('نسيان بصمة', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900, color: scheme.error)),
          const SizedBox(height: 4),
          Text('اليوم: ${widget.dateStr}', style: TextStyle(
            fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'missing_check_in', label: Text('نسيان حضور')),
              ButtonSegment(value: 'missing_check_out', label: Text('نسيان انصراف')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'السبب',
              hintText: 'اكتب سبب نسيان البصمة...',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send),
            label: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال سبب التصحيح (3 أحرف على الأقل)')),
      );
      return;
    }
    Navigator.pop(context, {
      'type': _type,
      'reason': reason,
    });
  }
}

// ─── نموذج إذن سريع ─────────────────────────────────────────────────

class _QuickPermitSheet extends StatefulWidget {
  const _QuickPermitSheet({
    required this.dateStr,
    required this.permitKind,
  });
  final String dateStr;
  final String permitKind;
  @override
  State<_QuickPermitSheet> createState() => _QuickPermitSheetState();
}

class _QuickPermitSheetState extends State<_QuickPermitSheet> {
  final _reasonCtrl = TextEditingController();

  String get _kindLabel =>
      widget.permitKind == 'early_departure' ? 'إذن انصراف' : 'إذن حضور';

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: .3),
              borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),
          Text(_kindLabel, style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B))),
          const SizedBox(height: 4),
          Text('اليوم: ${widget.dateStr}', style: TextStyle(
            fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'السبب',
              hintText: 'اكتب سبب طلب $_kindLabel...',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send),
            label: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال سبب الطلب (3 أحرف على الأقل)')),
      );
      return;
    }
    Navigator.pop(context, {
      'title': '$_kindLabel — ${widget.dateStr}',
      'reason': reason,
      'payload': {
        'permitDate': widget.dateStr,
        'minutes': 120,
        'permitKind': widget.permitKind,
      },
    });
  }
}

// ─── نقطة دليل الألوان ──────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
          fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
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

// ─── ورقة تعديل اليوم إدارياً ─────────────────────────────────────

class _AdminEditDaySheet extends ConsumerStatefulWidget {
  const _AdminEditDaySheet({
    required this.statement,
    required this.day,
    required this.dateStr,
    required this.dayNum,
    required this.year,
    required this.month,
  });

  final MonthlyAttendanceStatement statement;
  final AttendanceStatementDay? day;
  final String dateStr;
  final int dayNum;
  final int year;
  final int month;

  @override
  ConsumerState<_AdminEditDaySheet> createState() => _AdminEditDaySheetState();
}

class _AdminEditDaySheetState extends ConsumerState<_AdminEditDaySheet> {
  late String _dayType;
  late String _leaveType;
  late TextEditingController _checkInController;
  late TextEditingController _checkOutController;
  late TextEditingController _reasonController;
  late TextEditingController _notesController;
  bool _clearCheckIn = false;
  bool _clearCheckOut = false;
  bool _isSubmitting = false;

  static const _dayTypes = [
    ('work', 'يوم عمل (حاضر)', Icons.work_outline),
    ('leave', 'إجازة معتمدة', Icons.beach_access_outlined),
    ('mission', 'مأمورية عمل', Icons.directions_car_outlined),
    ('convoy', 'قافلة خيرية', Icons.volunteer_activism_outlined),
    ('fundraising', 'فاندي تبرعات', Icons.stars_outlined),
    ('rest', 'راحة أسبوعية', Icons.wb_sunny_outlined),
    ('holiday', 'عطلة رسمية', Icons.calendar_today_outlined),
    ('absent', 'تأكيد غياب', Icons.cancel_outlined),
  ];

  static const _leaveTypes = [
    ('annual', 'إجازة سنوية (اعتيادية)'),
    ('casual', 'إجازة عارضة'),
    ('sick', 'إجازة مرضية'),
    ('unpaid', 'إجازة بدون راتب'),
    ('weekly_rest_comp', 'بدل راحة أسبوعية'),
  ];

  static const _quickHours = [
    ('8 ساعات (09:00 - 17:00)', '09:00', '17:00'),
    ('8 ساعات (08:00 - 16:00)', '08:00', '16:00'),
    ('4 ساعات (09:00 - 13:00)', '09:00', '13:00'),
    ('10 ساعات (08:00 - 18:00)', '08:00', '18:00'),
  ];

  static const _presetReasons = [
    'تعديل ساعات العمل المعتمدة',
    'تصحيح وقت الحضور والانصراف',
    'إجازة معتمدة من الإدارة',
    'مأمورية عمل رسمية',
    'عطلة رسمية معتمدة',
    'دوام كامل معتمد',
  ];

  @override
  void initState() {
    super.initState();
    final existingType = widget.day?.adminOverride?['dayType'] as String? ?? 'work';
    _dayType = existingType;
    _leaveType = widget.day?.adminOverride?['leaveType'] as String? ?? 'annual';
    _checkInController = TextEditingController(
      text: widget.day?.checkIn != null && widget.day!.checkIn!.length >= 5
          ? widget.day!.checkIn!.substring(0, 5)
          : '09:00',
    );
    _checkOutController = TextEditingController(
      text: widget.day?.checkOut != null && widget.day!.checkOut!.length >= 5
          ? widget.day!.checkOut!.substring(0, 5)
          : '17:00',
    );
    _reasonController = TextEditingController(
      text: widget.day?.adminOverride?['reason'] as String? ?? 'تعديل ساعات وحضور معتمد',
    );
    _notesController = TextEditingController(
      text: widget.day?.adminOverride?['notes'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _checkInController.dispose();
    _checkOutController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final empId = widget.statement.employeeId;
      await ref.read(mobileCommandsProvider).setAttendanceDayAdmin(
            employeeId: empId,
            date: widget.dateStr,
            dayType: _dayType,
            checkIn: _dayType == 'work' && !_clearCheckIn ? _checkInController.text.trim() : null,
            checkOut: _dayType == 'work' && !_clearCheckOut ? _checkOutController.text.trim() : null,
            clearCheckIn: _dayType != 'work' || _clearCheckIn,
            clearCheckOut: _dayType != 'work' || _clearCheckOut,
            reason: _reasonController.text.trim().isNotEmpty
                ? _reasonController.text.trim()
                : 'تعديل إداري معتمد',
            notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
            leaveType: _dayType == 'leave' || _dayType == 'absent' ? _leaveType : null,
          );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التعديل الإداري بنجاح.')),
        );
      }
    } catch (error) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'تعديل إداري ليوم ${widget.dateStr}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'تعديل حالة اليوم أو ساعات العمل وتوثيقه في سجل التدقيق.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // 1. اختيار حالة اليوم
            Text(
              'حالة اليوم',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: scheme.primary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dayTypes.map((t) {
                final isSelected = _dayType == t.$1;
                return ChoiceChip(
                  avatar: Icon(t.$3, size: 16, color: isSelected ? scheme.onPrimary : scheme.primary),
                  label: Text(t.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  selected: isSelected,
                  selectedColor: scheme.primary,
                  labelStyle: TextStyle(color: isSelected ? scheme.onPrimary : scheme.onSurface),
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _dayType = t.$1;
                        if (_dayType == 'leave' || _dayType == 'absent') {
                          _leaveType = _dayType == 'absent' ? 'unpaid' : 'annual';
                        }
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 2. تفاصيل الإجازة إن اختيرت
            if (_dayType == 'leave' || _dayType == 'absent') ...[
              Text(
                'نوع الإجازة',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: scheme.primary),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _leaveType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _leaveTypes.map((lt) => DropdownMenuItem(value: lt.$1, child: Text(lt.$2))).toList(),
                onChanged: (val) => setState(() => _leaveType = val ?? 'annual'),
              ),
              const SizedBox(height: 16),
            ],

            // 3. ساعات وأوقات العمل عند اختيار يوم عمل
            if (_dayType == 'work') ...[
              Text(
                'ساعات وأوقات العمل',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: scheme.primary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _quickHours.map((qh) {
                  final isActive = _checkInController.text == qh.$2 &&
                      _checkOutController.text == qh.$3 &&
                      !_clearCheckIn &&
                      !_clearCheckOut;
                  return ActionChip(
                    label: Text(qh.$1, style: const TextStyle(fontSize: 11)),
                    backgroundColor: isActive ? scheme.primaryContainer : null,
                    side: BorderSide(color: isActive ? scheme.primary : scheme.outlineVariant),
                    onPressed: () {
                      setState(() {
                        _checkInController.text = qh.$2;
                        _checkOutController.text = qh.$3;
                        _clearCheckIn = false;
                        _clearCheckOut = false;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _checkInController,
                      enabled: !_clearCheckIn,
                      decoration: const InputDecoration(
                        labelText: 'وقت الحضور (HH:MM)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _checkOutController,
                      enabled: !_clearCheckOut,
                      decoration: const InputDecoration(
                        labelText: 'وقت الانصراف (HH:MM)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('بدون حضور', style: TextStyle(fontSize: 11)),
                      value: _clearCheckIn,
                      onChanged: (v) => setState(() => _clearCheckIn = v ?? false),
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('بدون انصراف', style: TextStyle(fontSize: 11)),
                      value: _clearCheckOut,
                      onChanged: (v) => setState(() => _clearCheckOut = v ?? false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // 4. سبب التعديل
            Text(
              'سبب التعديل',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: scheme.primary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _presetReasons.map((pr) {
                return ActionChip(
                  label: Text(pr, style: const TextStyle(fontSize: 11)),
                  onPressed: () => setState(() => _reasonController.text = pr),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'اكتب سبب التعديل…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),

            // 5. ملاحظات
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'ملاحظات إضافية (اختيارية)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),

            // 6. زر الحفظ
            FilledButton.icon(
              icon: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(_isSubmitting ? 'جارٍ الحفظ…' : 'حفظ التعديل الإداري'),
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        );
      },
    );
  }
}

