import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/attendance_pdf_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// الشهور بالعربية
const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// كشف المستخدم نفسه؟ الطلبات الذاتية (إجازة/إذن/تصحيح بصمة/تعديل حالة يوم)
/// تُقدَّم باسم من يستخدم التطبيق، فلا تُعرض على كشف موظف آخر.
bool _isOwnStatement(WidgetRef ref, MonthlyAttendanceStatement statement) {
  final me = ref.watch(accessContextProvider).value?.employeeId;
  return statement.employeeId.isEmpty || statement.employeeId == me;
}


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
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.check_circle_outline, color: Colors.white),
                            SizedBox(width: 8),
                            Expanded(child: Text('تم تصدير كشف الحضور PDF بنجاح')),
                          ],
                        ),
                        backgroundColor: Color(0xFF0F9F6E),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
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

  static String _formatOvertimeValue(int minutes) {
    if (minutes <= 0) return '0';
    if (minutes < 60) return '$minutes';
    final hours = minutes / 60.0;
    return hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1);
  }

  static String _formatOvertimeUnit(int minutes) {
    if (minutes <= 0) return 'ساعة';
    if (minutes < 60) return 'دقيقة';
    return 'ساعة ($minutes د)';
  }

  @override
  Widget build(BuildContext context) {
    final s = statement.summary;
    final scheme = Theme.of(context).colorScheme;
    final convoyDays = statement.days.where((d) => (d.status.contains('قافلة') || d.hasConvoyFundi) && !d.status.contains('فاندي')).length;
    final fundiDays = statement.days.where((d) => d.status.contains('فاندي')).length;
    final cDays = statement.days.isNotEmpty ? convoyDays : s.convoyFundiDays;
    final fDays = statement.days.isNotEmpty ? fundiDays : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ───── بطاقة بيانات الموظف ─────
        _EmployeeHeader(statement: statement),
        const SizedBox(height: 16),

        // ───── دائرة نسبة الحضور والالتزام ─────
        _AttendancePercentageCard(statement: statement),
        const SizedBox(height: 16),

        // ───── بطاقات الملخص الرئيسية ─────
        Text('ملخص الشهر',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.88,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          children: [
            _MetricTile(icon: Icons.check_circle_outline, label: 'حضور', value: '${s.presentDays}', color: const Color(0xFF0F9F6E)),
            _MetricTile(icon: Icons.cancel_outlined, label: 'غياب', value: '${s.absentDays}', color: scheme.error),
            _MetricTile(icon: Icons.beach_access_outlined, label: 'إجازات', value: '${s.leaveDays}', color: const Color(0xFF4F46E5)),
            _MetricTile(icon: Icons.directions_car_outlined, label: 'مأموريات', value: '${s.missionDays}', color: const Color(0xFF0284C7)),
            _MetricTile(icon: Icons.assignment_outlined, label: 'أذونات', value: '${s.permitCount}', color: const Color(0xFFD97706)),
            _MetricTile(icon: Icons.volunteer_activism_outlined, label: 'قوافل', value: '$cDays', color: const Color(0xFF7C3AED)),
            _MetricTile(icon: Icons.celebration_outlined, label: 'فاندي', value: '$fDays', color: const Color(0xFFDB2777)),
            _MetricTile(icon: Icons.bed_outlined, label: 'عطلات', value: '${s.restDays + s.holidayDays}', color: const Color(0xFF64748B)),
          ],
        ),
        const SizedBox(height: 16),

        // ───── مستهدف ساعات العمل الشهرية ─────
        _WorkingHoursGoalCard(statement: statement),
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
            _SummaryTile(
              label: 'ساعات إضافية',
              value: _formatOvertimeValue(s.totalOvertimeMinutes),
              unit: _formatOvertimeUnit(s.totalOvertimeMinutes),
            ),
            _SummaryTile(label: 'تصحيحات معتمدة', value: '${s.correctionCount}', unit: ''),
          ],
        ),
        const SizedBox(height: 16),

        // ───── الرؤى والإرشادات الذكية ─────
        _MonthlySmartInsights(statement: statement),

        // ───── تنبيه نقص البصمة التفاعلي ─────
        if (s.missingCheckInCount > 0 || s.missingCheckOutCount > 0) ...[
          const SizedBox(height: 12),
          _MissingPunchesBanner(statement: statement),
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
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _LegendChip(color: Color(0xFF0F9F6E), label: 'حضور'),
            _LegendChip(color: Color(0xFFDC2626), label: 'غياب'),
            _LegendChip(color: Color(0xFF4F46E5), label: 'إجازة'),
            _LegendChip(color: Color(0xFF0284C7), label: 'مأمورية'),
            _LegendChip(color: Color(0xFF7C3AED), label: 'قافلة'),
            _LegendChip(color: Color(0xFFDB2777), label: 'فاندي'),
            _LegendChip(color: Color(0xFFD97706), label: 'مراجعة / تأخير'),
            _LegendChip(color: Color(0xFF94A3B8), label: 'راحة / عطلة'),
            _LegendChip(color: Color(0xFF64748B), label: 'قادم'),
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

  static String _formatEmployeeCodeOrPhone(String? code) {
    if (code == null || code.trim().isEmpty) return '';
    final cleaned = code.trim();
    if (cleaned.startsWith('+') || (cleaned.startsWith('01') && cleaned.length >= 11)) {
      return 'الهاتف: $cleaned';
    }
    return 'كود: $cleaned';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final job = statement.jobTitle.trim();
    final dept = statement.department.trim();
    final isSameJobAndDept = job.isNotEmpty && (job == dept);
    final managerName = statement.manager.replaceAll('ألشيخ', 'الشيخ').trim();
    final codeOrPhone = _formatEmployeeCodeOrPhone(statement.employeeCode);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // الاسم والكود/الهاتف مع الصورة الرمزية الرسمية
            Row(
              children: [
                AppAvatar(name: statement.employeeNameAr, radius: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statement.employeeNameAr,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      if (codeOrPhone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(codeOrPhone, style: muted),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // تفاصيل وظيفية — إزالة التكرار
            if (isSameJobAndDept)
              _InfoRow(icon: Icons.work_outline, label: 'القسم والمسمى', value: job)
            else ...[
              _InfoRow(icon: Icons.work_outline, label: 'المسمى الوظيفي', value: job),
              _InfoRow(icon: Icons.business_outlined, label: 'القسم', value: dept),
            ],
            _InfoRow(icon: Icons.location_city_outlined, label: 'الفرع', value: statement.branch),
            _InfoRow(icon: Icons.supervisor_account_outlined, label: 'المدير المباشر', value: managerName),
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

// ─── دائرة ونسبة الحضور والالتزام ────────────────────────────────

class _AttendancePercentageCard extends StatelessWidget {
  const _AttendancePercentageCard({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final s = statement.summary;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isCurrentMonth = statement.year == now.year && statement.month == now.month;

    // تفصيل أيام الشهر للعرض فقط — النسبة نفسها من الخادم
    int presentInOffice = 0;
    int convoysCount = 0;
    int fundiCount = 0;
    int leavesCount = 0;
    int missionsCount = 0;
    int unexcusedAbsences = 0;
    int upcomingWorkDays = 0;
    final restDaysCount = s.restDays;
    final holidaysCount = s.holidayDays;

    if (statement.days.isNotEmpty) {
      for (final d in statement.days) {
        final date = DateTime.tryParse(d.date);
        final isFutureDay = isCurrentMonth && date != null && date.isAfter(DateTime(now.year, now.month, now.day));
        final isRest = d.status == 'راحة' || d.status == 'راحة أسبوعية' || d.status == 'عطلة رسمية';

        if (isRest) continue;

        if (isFutureDay) {
          upcomingWorkDays++;
        } else {
          if (d.status == 'حاضر') {
            presentInOffice++;
          } else if (d.status.contains('فاندي')) {
            fundiCount++;
          } else if (d.status.contains('قافلة') || d.hasConvoyFundi) {
            convoysCount++;
          } else if (d.hasLeave) {
            leavesCount++;
          } else if (d.hasMission) {
            missionsCount++;
          } else if (d.status == 'غائب دون إذن') {
            final isTodayDay = isCurrentMonth && date != null && date.year == now.year && date.month == now.month && date.day == now.day;
            if (!isTodayDay) {
              unexcusedAbsences++;
            }
          }
        }
      }
    } else {
      presentInOffice = s.presentDays;
      convoysCount = s.convoyFundiDays;
      fundiCount = 0;
      leavesCount = s.leaveDays;
      missionsCount = s.missionDays;
      unexcusedAbsences = s.absentDays;
      upcomingWorkDays = s.upcomingDays;
    }

    // النسبة من الخادم — نفس رقم الويب وملف PDF: الأيام المحتسبة حضورًا (بالمقر أو
    // مأمورية/قافلة/فاندي) ÷ أيام العمل المستحقة بعد استبعاد الإجازات والطلبات المعلّقة.
    // (كانت تُحسب هنا بصيغة مختلفة تعدّ الإجازة حضورًا فيختلف الرقم عن الكشف المطبوع.)
    final isExempt = s.isAttendanceExempt;
    final dueDays = s.attendanceRateDueDays;
    final rateAvailable = !isExempt && dueDays > 0;
    final double displayPct = rateAvailable ? statement.attendancePercentage.clamp(0.0, 100.0) : 0;
    final pctText = isExempt
        ? 'معفى'
        : rateAvailable
            ? '${(displayPct >= 99.5 && displayPct < 100 ? 99 : displayPct.round())}%'
            : '—';
    final excludedLeave = s.attendanceRateExcludedLeaveDays;

    final purePresenceRate = rateAvailable ? ((presentInOffice / dueDays) * 100).clamp(0.0, 100.0) : 0.0;

    final pctColor = !rateAvailable
        ? scheme.onSurfaceVariant
        : displayPct >= 85
            ? const Color(0xFF0F9F6E)
            : displayPct >= 70
                ? const Color(0xFFF59E0B)
                : scheme.error;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // دائرة النسبة المحدثة
                SizedBox(
                  width: 94,
                  height: 94,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: displayPct / 100,
                          strokeWidth: 8.5,
                          backgroundColor: pctColor.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation(pctColor),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            pctText,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: isExempt ? 18 : 22,
                              color: pctColor,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            'نسبة الحضور',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                // تفاصيل جانبية واضحة ومفصلة
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'نسبة الحضور الشهرية',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          if (isCurrentMonth) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'حتى اليوم',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      _PctDetailRow(
                        label: 'أيام محتسبة حضورًا',
                        value: isExempt
                            ? 'معفى من البصمة بقرار الإدارة'
                            : rateAvailable
                                ? '${s.attendanceRatePresentDays} من $dueDays يوم مستحق'
                                : 'لا توجد أيام عمل مستحقة بعد',
                        color: pctColor,
                      ),
                      if (excludedLeave > 0 && rateAvailable)
                        _PctDetailRow(
                          label: 'مستبعد من النسبة',
                          value: '$excludedLeave يوم إجازة',
                        ),
                      _PctDetailRow(label: 'حضور بالمقر', value: '$presentInOffice يوم'),
                      if (convoysCount > 0)
                        _PctDetailRow(
                          label: 'قوافل خارجية',
                          value: '$convoysCount يوم',
                        ),
                      if (fundiCount > 0)
                        _PctDetailRow(
                          label: 'فاندي (ترفيهي)',
                          value: '$fundiCount يوم',
                        ),
                      if (missionsCount > 0)
                        _PctDetailRow(
                          label: 'مأموريات خارجية',
                          value: '$missionsCount يوم',
                        ),
                      if (leavesCount > 0)
                        _PctDetailRow(label: 'إجازات', value: '$leavesCount يوم'),
                      if (unexcusedAbsences > 0)
                        _PctDetailRow(
                          label: 'غياب غير مبرر',
                          value: '$unexcusedAbsences يوم',
                          color: scheme.error,
                        ),
                      if (upcomingWorkDays > 0)
                        _PctDetailRow(label: 'أيام عمل قادمة', value: '$upcomingWorkDays يوم'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatBadge(
                  label: 'راحة أسبوعية',
                  value: '$restDaysCount',
                  icon: Icons.weekend_outlined,
                ),
                _StatBadge(
                  label: 'عطلات رسمية',
                  value: '$holidaysCount',
                  icon: Icons.event_available_outlined,
                ),
                _StatBadge(
                  label: 'حضور المقر فقط',
                  value: rateAvailable ? '${purePresenceRate.toStringAsFixed(0)}%' : '—',
                  icon: Icons.business_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ],
    );
  }
}

class _PctDetailRow extends StatelessWidget {
  const _PctDetailRow({
    required this.label,
    required this.value,
    this.color,
  });
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── بطاقة مؤشر إنجاز ساعات العمل المستهدفة ─────────────────────

class _WorkingHoursGoalCard extends StatelessWidget {
  const _WorkingHoursGoalCard({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final s = statement.summary;
    final scheme = Theme.of(context).colorScheme;
    final targetHours = s.totalRequiredHours > 0
        ? s.totalRequiredHours
        : (s.scheduledDays > 0 ? s.scheduledDays * 8.0 : 192.0);
    final workedHours = s.totalWorkHours;
    final pct = targetHours > 0 ? (workedHours / targetHours * 100).clamp(0.0, 150.0) : 0.0;
    final isGood = pct >= 80;
    final barColor = isGood ? const Color(0xFF0F9F6E) : const Color(0xFFF59E0B);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.speed_rounded, size: 20, color: scheme.primary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'مؤشر ساعات العمل المستهدفة',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: barColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${pct.toStringAsFixed(0)}% إنجاز',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: barColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${workedHours.toStringAsFixed(1)} ساعة منجزة',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                Text(
                  'مستهدف: ${targetHours.toStringAsFixed(0)} ساعة',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (pct / 100.0).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MiniMetric(
                    label: 'متوسط يومي',
                    value: '${s.averageWorkHours.toStringAsFixed(1)} س/يوم',
                    icon: Icons.timer_outlined,
                  ),
                ),
                Expanded(
                  child: _MiniMetric(
                    label: 'ساعات إضافية',
                    value: s.totalOvertimeMinutes > 0
                        ? '${(s.totalOvertimeMinutes / 60).toStringAsFixed(1)} س'
                        : '0',
                    icon: Icons.more_time_rounded,
                    valueColor: s.totalOvertimeMinutes > 0 ? const Color(0xFF0F9F6E) : null,
                  ),
                ),
                Expanded(
                  child: _MiniMetric(
                    label: 'إجمالي التأخير',
                    value: '${s.totalLateMinutes} د',
                    icon: Icons.history_toggle_off_rounded,
                    valueColor: s.totalLateMinutes > 0 ? const Color(0xFFD97706) : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── ملاحظات ورؤى الشهر الذكية ────────────────────────────────────

class _MonthlySmartInsights extends StatelessWidget {
  const _MonthlySmartInsights({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final s = statement.summary;
    final scheme = Theme.of(context).colorScheme;

    final insights = <_InsightItem>[];

    if (s.missingCheckInCount > 0 || s.missingCheckOutCount > 0) {
      insights.add(
        _InsightItem(
          icon: Icons.notification_important_rounded,
          color: const Color(0xFFD97706),
          title: 'تنبيه بصمات معلقة',
          desc: 'لديك ${s.missingCheckInCount + s.missingCheckOutCount} بصمات تحتاج لتصحيح لتفادي احتساب عجز بالساعات.',
        ),
      );
    }

    if (s.convoyFundiDays > 0) {
      insights.add(
        _InsightItem(
          icon: Icons.celebration_rounded,
          color: const Color(0xFF7C3AED),
          title: 'أنشطة خارجية وميدانية معتمدة',
          desc: 'سجلت ${s.convoyFundiDays} أيام في قوافل المساعدات الإنسانية والأنشطة الترفيهية (فاندي).',
        ),
      );
    }

    if (s.totalOvertimeMinutes >= 120) {
      final hours = (s.totalOvertimeMinutes / 60).toStringAsFixed(1);
      insights.add(
        _InsightItem(
          icon: Icons.trending_up_rounded,
          color: const Color(0xFF0F9F6E),
          title: 'ساعات عمل إضافية',
          desc: 'حققت $hours ساعة إضافية معتمدة تُضاف إلى رصيدك وسجل أدائك الشهري.',
        ),
      );
    }

    if (s.absentDays == 0 && s.presentDays > 0) {
      insights.add(
        _InsightItem(
          icon: Icons.verified_user_rounded,
          color: const Color(0xFF0F9F6E),
          title: 'سجل حضور منضبط',
          desc: 'لا توجد أي أيام غياب غير مبرر هذا الشهر، التزام وظيفي ممتاز!',
        ),
      );
    }

    if (insights.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              'رؤى وإشارات الأداء للشهر',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...insights.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: item.color.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.icon, size: 20, color: item.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: item.color)),
                      const SizedBox(height: 2),
                      Text(
                        item.desc,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _InsightItem {
  const _InsightItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String desc;
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: valueColor ?? scheme.onSurface),
        ),
      ],
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
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
                Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      unit,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── بطاقة تنبيه نقص البصمة التفاعلية ─────────────────────────────

class _MissingPunchesBanner extends ConsumerWidget {
  const _MissingPunchesBanner({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = statement.summary;
    // معالجة البصمات المنسية = طلب تصحيح باسم المستخدم — على كشفه هو فقط.
    final missingDays = _isOwnStatement(ref, statement)
        ? statement.days.where((d) => d.missingCheckIn || d.missingCheckOut).toList()
        : const <AttendanceStatementDay>[];

    final parts = <String>[];
    if (s.missingCheckInCount > 0) parts.add('نسيان حضور: ${s.missingCheckInCount}');
    if (s.missingCheckOutCount > 0) parts.add('نسيان انصراف: ${s.missingCheckOutCount}');
    final desc = parts.join(' · ');

    return Card(
      color: const Color(0xFFFEF2F2),
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFFCA5A5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 22, color: Color(0xFFDC2626)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تنبيه نقص تسجيل البصمة',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc.isNotEmpty ? desc : 'يوجد بصمات غير مكتملة تؤثر على احتساب ساعاتك الشهرية.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (missingDays.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE2E2),
                    foregroundColor: const Color(0xFF991B1B),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.fingerprint, size: 18),
                  label: const Text(
                    'معالجة البصمات المنسية',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  onPressed: () => _openMissingPunchesResolver(context, statement, missingDays),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openMissingPunchesResolver(
    BuildContext context,
    MonthlyAttendanceStatement statement,
    List<AttendanceStatementDay> missingDays,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MissingPunchesSheet(
        statement: statement,
        missingDays: missingDays,
      ),
    );
  }
}

// ─── ورقة حل البصمات غير المكتملة ─────────────────────────────────

class _MissingPunchesSheet extends ConsumerWidget {
  const _MissingPunchesSheet({
    required this.statement,
    required this.missingDays,
  });

  final MonthlyAttendanceStatement statement;
  final List<AttendanceStatementDay> missingDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.8,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.fingerprint, color: Color(0xFFDC2626), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الأيام ذات البصمات غير المكتملة',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'اختر اليوم لتقديم طلب تصحيح بصمة الحضور أو الانصراف',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...missingDays.map((day) {
              final isMissingIn = day.missingCheckIn;
              final typeText = isMissingIn && day.missingCheckOut
                  ? 'نسيان بصمة حضور وانصراف'
                  : isMissingIn
                      ? 'نسيان بصمة حضور'
                      : 'نسيان بصمة انصراف';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 20),
                  ),
                  title: Text(
                    day.date,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  subtitle: Text(
                    typeText,
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  trailing: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    child: const Text('تصحيح', style: TextStyle(fontSize: 12)),
                    onPressed: () async {
                      Navigator.pop(context);
                      final preselect = (day.missingCheckOut && !day.missingCheckIn)
                          ? 'missing_check_out'
                          : 'missing_check_in';
                      final result = await showModalBottomSheet<Map<String, dynamic>>(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => _QuickCorrectionSheet(
                          dateStr: day.date,
                          preselectType: preselect,
                        ),
                      );
                      if (result != null && context.mounted) {
                        try {
                          await ref.read(mobileCommandsProvider).requestAttendanceCorrection(
                                workDate: DateTime.parse(day.date),
                                type: result['type'] as String,
                                reason: result['reason'] as String,
                                checkIn: result['checkIn'] as DateTime?,
                                checkOut: result['checkOut'] as DateTime?,
                              );
                          ref.invalidate(myMonthlyStatementProvider((statement.year, statement.month)));
                          ref.invalidate(mobileRequestsProvider);
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
                    },
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ─── شريحة توضيح الألوان (Legend Chip) ─────────────────────────────────

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── زر فلترة التقويم الشهري ──────────────────────────────────────

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = color ?? scheme.primary;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: isSelected ? activeColor.withValues(alpha: 0.15) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? activeColor : scheme.outlineVariant.withValues(alpha: 0.5),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (color != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: activeColor,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? activeColor : scheme.onSurface,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected ? activeColor : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── التقويم الشهري (شبكة 7 أعمدة مع فلترة سريعة) ────────────────

class _MonthlyCalendarGrid extends StatefulWidget {
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
  State<_MonthlyCalendarGrid> createState() => _MonthlyCalendarGridState();
}

class _MonthlyCalendarGridState extends State<_MonthlyCalendarGrid> {
  String _activeFilter = 'all';

  static const _weekDayHeaders = ['سبت', 'أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'];

  bool _matchesFilter(AttendanceStatementDay? d, String filter) {
    if (filter == 'all') return true;
    if (d == null) return filter == 'absent';
    switch (filter) {
      case 'present':
        return d.status == 'حاضر';
      case 'absent':
        return d.status == 'غائب دون إذن' || d.isAbsent;
      case 'convoy':
        return (d.status.contains('قافلة') || d.hasConvoyFundi) && !d.status.contains('فاندي');
      case 'fundi':
        return d.status.contains('فاندي');
      case 'mission':
        return d.hasMission || d.status.contains('مأمورية');
      case 'leave':
        return d.hasLeave || d.status.contains('إجازة');
      case 'missing':
        return d.missingCheckIn || d.missingCheckOut;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final isCurrentMonth = today.year == widget.year && today.month == widget.month;

    // بناء خريطة الأيام (رقم اليوم → بيانات اليوم)
    final dayMap = <int, AttendanceStatementDay>{};
    for (final d in widget.days) {
      final parsed = DateTime.tryParse(d.date);
      if (parsed != null) dayMap[parsed.day] = d;
    }

    final firstOfMonth = DateTime(widget.year, widget.month, 1);
    final daysInMonth = DateTime(widget.year, widget.month + 1, 0).day;
    final firstWeekdayCol = (firstOfMonth.weekday + 1) % 7;
    final totalCells = firstWeekdayCol + daysInMonth;
    final rows = (totalCells / 7).ceil();

    final s = widget.statement.summary;
    final missingPunches = s.missingCheckInCount + s.missingCheckOutCount;
    final convoyCount = widget.days.where((d) => (d.status.contains('قافلة') || d.hasConvoyFundi) && !d.status.contains('فاندي')).length;
    final fundiCount = widget.days.where((d) => d.status.contains('فاندي')).length;
    final cCount = widget.days.isNotEmpty ? convoyCount : s.convoyFundiDays;
    final fCount = widget.days.isNotEmpty ? fundiCount : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─ شريط الفلترة السريع لأيام الشهر ─
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChipButton(
                label: 'الكل',
                count: widget.statement.days.length,
                isSelected: _activeFilter == 'all',
                onTap: () => setState(() => _activeFilter = 'all'),
              ),
              _FilterChipButton(
                label: 'حضور',
                count: s.presentDays,
                color: const Color(0xFF0F9F6E),
                isSelected: _activeFilter == 'present',
                onTap: () => setState(() => _activeFilter = 'present'),
              ),
              _FilterChipButton(
                label: 'غياب',
                count: s.absentDays,
                color: const Color(0xFFDC2626),
                isSelected: _activeFilter == 'absent',
                onTap: () => setState(() => _activeFilter = 'absent'),
              ),
              _FilterChipButton(
                label: 'قوافل',
                count: cCount,
                color: const Color(0xFF7C3AED),
                isSelected: _activeFilter == 'convoy',
                onTap: () => setState(() => _activeFilter = 'convoy'),
              ),
              _FilterChipButton(
                label: 'فاندي',
                count: fCount,
                color: const Color(0xFFDB2777),
                isSelected: _activeFilter == 'fundi',
                onTap: () => setState(() => _activeFilter == 'fundi'),
              ),
              _FilterChipButton(
                label: 'مأموريات',
                count: s.missionDays,
                color: const Color(0xFF0284C7),
                isSelected: _activeFilter == 'mission',
                onTap: () => setState(() => _activeFilter = 'mission'),
              ),
              _FilterChipButton(
                label: 'إجازات',
                count: s.leaveDays,
                color: const Color(0xFF4F46E5),
                isSelected: _activeFilter == 'leave',
                onTap: () => setState(() => _activeFilter = 'leave'),
              ),
              if (missingPunches > 0)
                _FilterChipButton(
                  label: 'نقص بصمة',
                  count: missingPunches,
                  color: const Color(0xFFD97706),
                  isSelected: _activeFilter == 'missing',
                  onTap: () => setState(() => _activeFilter = 'missing'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        Card(
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
                      final dayDate = DateTime(widget.year, widget.month, dayNum);
                      final isFuture = dayDate.isAfter(
                        DateTime(today.year, today.month, today.day),
                      );
                      final matches = _matchesFilter(dayData, _activeFilter);
                      final isDimmed = _activeFilter != 'all' && !matches;

                      return Expanded(
                        child: _CalendarDayCell(
                          statement: widget.statement,
                          dayNum: dayNum,
                          dayData: dayData,
                          isToday: isToday,
                          isFuture: isFuture,
                          year: widget.year,
                          month: widget.month,
                          isDimmed: isDimmed,
                          isHighlighted: _activeFilter != 'all' && matches,
                        ),
                      );
                    }),
                  );
                }),
              ],
            ),
          ),
        ),
        if (_activeFilter != 'all') ...[
          const SizedBox(height: 8),
          Center(
            child: ActionChip(
              avatar: const Icon(Icons.close_rounded, size: 16),
              label: Text(
                'إلغاء التصفية (عرض الكل)',
                style: TextStyle(fontSize: 11, color: scheme.primary),
              ),
              onPressed: () => setState(() => _activeFilter = 'all'),
            ),
          ),
        ],
      ],
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
    this.isDimmed = false,
    this.isHighlighted = false,
  });
  final MonthlyAttendanceStatement statement;
  final int dayNum;
  final AttendanceStatementDay? dayData;
  final bool isToday;
  final bool isFuture;
  final int year;
  final int month;
  final bool isDimmed;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _resolveStyle(scheme);

    return Semantics(
      button: true,
      label: 'يوم $dayNum${dayData?.status != null ? " - ${dayData!.status}" : ""}',
      child: GestureDetector(
        onTap: () => _showDayDetail(context),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isDimmed ? 0.22 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 56,
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: style.bg,
              borderRadius: BorderRadius.circular(12),
              border: isToday
                  ? Border.all(color: style.accent, width: 2.5)
                  : isHighlighted
                      ? Border.all(color: style.accent, width: 2.2)
                      : Border.all(color: style.accent.withValues(alpha: .25)),
              boxShadow: isToday || isHighlighted
                  ? [
                      BoxShadow(
                        color: style.accent.withValues(alpha: .35),
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

    // اليوم الحالي — معالجة خاصة تمنع وسم اليوم قيد العمل كغياب غير مبرر
    if (isToday) {
      if (dayData?.status == 'حاضر') {
        final late = (dayData?.lateMinutes ?? 0) > 0;
        return (
          bg: late ? const Color(0xFFFFF9E9) : const Color(0xFFE9F7F0),
          fg: late ? const Color(0xFF9A5B00) : const Color(0xFF15734F),
          accent: late ? const Color(0xFFF59E0B) : const Color(0xFF0F9F6E),
          dot: late ? const Color(0xFFF59E0B) : const Color(0xFF0F9F6E),
        );
      }
      if (dayData?.hasLeave == true) {
        return (
          bg: const Color(0xFFEEF0FB),
          fg: const Color(0xFF3D4FA8),
          accent: const Color(0xFF4F46E5),
          dot: const Color(0xFF4F46E5),
        );
      }
      if (dayData?.hasMission == true) {
        return (
          bg: const Color(0xFFE5F6FB),
          fg: const Color(0xFF0B6B80),
          accent: const Color(0xFF0284C7),
          dot: const Color(0xFF0284C7),
        );
      }
      if (dayData?.hasConvoyFundi == true) {
        final isFundi = dayData!.status.contains('فاندي');
        return isFundi
            ? (
                bg: const Color(0xFFFDF2F8),
                fg: const Color(0xFF9D174D),
                accent: const Color(0xFFDB2777),
                dot: const Color(0xFFDB2777),
              )
            : (
                bg: const Color(0xFFF4ECF8),
                fg: const Color(0xFF6D3FA0),
                accent: const Color(0xFF7C3AED),
                dot: const Color(0xFF7C3AED),
              );
      }
      if (dayData?.status == 'راحة' || dayData?.status == 'راحة أسبوعية') {
        return (
          bg: const Color(0xFFF4F6F7),
          fg: const Color(0xFF90A0A8),
          accent: scheme.primary,
          dot: null,
        );
      }
      // اليوم لا يزال جارياً — تمييزه بلون المنظومة الأساسي الحيوي وليس بالأحمر التحذيري
      return (
        bg: scheme.primaryContainer.withValues(alpha: 0.25),
        fg: scheme.primary,
        accent: scheme.primary,
        dot: scheme.primary,
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
    // غائب دون إذن — أحمر (للأيام السابقة المكتملة فقط)
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
        accent: const Color(0xFF4F46E5),
        dot: const Color(0xFF4F46E5),
      );
    }
    // مأمورية — سماوي
    if (d.hasMission) {
      return (
        bg: const Color(0xFFE5F6FB),
        fg: const Color(0xFF0B6B80),
        accent: const Color(0xFF0284C7),
        dot: const Color(0xFF0284C7),
      );
    }
    // قوافل مساعدات خارجية وفاندي ترفيهي
    if (d.hasConvoyFundi) {
      final isFundi = d.status.contains('فاندي');
      if (isFundi) {
        return (
          bg: const Color(0xFFFDF2F8),
          fg: const Color(0xFF9D174D),
          accent: const Color(0xFFDB2777),
          dot: const Color(0xFFDB2777),
        );
      }
      return (
        bg: const Color(0xFFF4ECF8),
        fg: const Color(0xFF6D3FA0),
        accent: const Color(0xFF7C3AED),
        dot: const Color(0xFF7C3AED),
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
                            'الحالة المعتمدة: ${day?.adminOverride?['dayType'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF3D4FA8)),
                          ),
                          if (cleanAttendanceNote(day?.adminOverride?['reason'] as String?) != null)
                            Text(
                              'السبب: ${cleanAttendanceNote(day!.adminOverride!['reason'] as String?)}',
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
                    _DetailChip(
                      icon: day!.status.contains('فاندي') ? Icons.celebration : Icons.volunteer_activism,
                      label: day!.status.contains('فاندي') ? 'فاندي (يوم ترفيهي)' : 'قافلة مساعدات (كامب)',
                      color: day!.status.contains('فاندي') ? const Color(0xFFDB2777) : const Color(0xFF7C3AED),
                    ),
                  if (day!.missingCheckIn)
                    _DetailChip(icon: Icons.warning_amber, label: 'لم يسجل حضور', color: scheme.error),
                  if (day!.missingCheckOut)
                    _DetailChip(icon: Icons.warning_amber, label: 'لم يسجل انصراف', color: scheme.error),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // ─ ملاحظة التصحيح ─
            if (cleanAttendanceNote(day?.correctionNote) != null) ...[
              Text('📝 ${cleanAttendanceNote(day!.correctionNote)!}',
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
    if (isToday) {
      if (day?.status == 'حاضر') return 'present';
      if (day?.hasLeave == true) return 'on_leave';
      if (day?.hasMission == true) return 'mission';
      if (day?.hasConvoyFundi == true) {
        return day!.status.contains('فاندي') ? 'fundi' : 'convoy';
      }
      if (day?.status == 'راحة' || day?.status == 'راحة أسبوعية') return 'rest';
      return 'in_progress';
    }
    if (day == null) return 'absent';
    final s = day!.status;
    if (s == 'حاضر') return 'present';
    if (s == 'غائب دون إذن') return 'absent';
    if (s == 'عطلة رسمية') return 'holiday';
    if (s == 'راحة' || s == 'راحة أسبوعية') return 'rest';
    if (s == 'يحتاج مراجعة') return 'flagged';
    if (day!.hasLeave) return 'on_leave';
    if (day!.hasMission) return 'mission';
    if (day!.hasConvoyFundi) {
      return s.contains('فاندي') ? 'fundi' : 'convoy';
    }
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
      day!.missingCheckIn || day!.missingCheckOut);

  List<Widget> _buildActions(BuildContext context, WidgetRef ref, ColorScheme scheme) {
    final actions = <Widget>[];

    final now = DateTime.now();
    final isSameMonth = year == now.year && month == now.month;
    final canModifyDay = !isFuture && isSameMonth;
    // طلبات الإجازة والأذونات والتصحيح وتعديل حالة اليوم تُقدَّم باسم من يستخدم
    // التطبيق، فلا تظهر على كشف موظف آخر (كان المدير يراها على كشف مرؤوسه فيقدّمها
    // باسمه هو). هناك يظهر التعديل الإداري وحده، بقرار الخادم (canEditDays).
    final isOwn = _isOwnStatement(ref, statement);

    // ── تعديل حالة اليوم بأثر رجعي في نفس الشهر (إجازة/مأمورية/قافلة مساعدات/فاندي) ──
    if (isOwn && canModifyDay) {
      actions.add(_ActionTile(
        icon: Icons.published_with_changes_rounded,
        label: 'تعديل حالة هذا اليوم',
        subtitle: 'طلب تحويل اليوم إلى إجازة، مأمورية عمل، قافلة مساعدات، أو يوم ترفيهي (فاندي).',
        color: const Color(0xFF4F46E5),
        onTap: () => _openRetroactiveDayChange(context, ref),
      ));
    }

    // ── اليوم الحالي الجاري الذي لم تُسجل بصمته بعد ──
    if (isOwn && isToday && (day == null || day!.status == 'غائب دون إذن')) {
      actions.add(_ActionTile(
        icon: Icons.fingerprint,
        label: 'تسجيل بصمة اليوم',
        subtitle: 'تسجيل بصمة الحضور أو إثبات التواجد لليوم الحالي.',
        color: scheme.primary,
        onTap: () => _openCorrectionRequest(context, ref),
      ));
    }

    // ── يوم ماضٍ غائب → طلب إجازة أو نسيان بصمة ──
    if (isOwn && !isFuture && !isToday && day != null && day!.status == 'غائب دون إذن') {
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
    if (isOwn && !isFuture && day != null && day!.status != 'غائب دون إذن' &&
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
    if (isOwn && !isFuture && day != null && day!.lateMinutes > 0 && !day!.hasPermit) {
      actions.add(_ActionTile(
        icon: Icons.schedule,
        label: 'طلب إذن حضور',
        subtitle: 'تغطية ${day!.lateMinutes} دقيقة تأخير بإذن مُعتمَد.',
        color: const Color(0xFFF59E0B),
        onTap: () => _openPermitRequest(context, ref, 'late_arrival'),
      ));
    }

    // ── خروج مبكر → إذن انصراف ──
    if (isOwn && !isFuture && day != null && day!.earlyLeaveMinutes > 0 && !day!.hasPermit) {
      actions.add(_ActionTile(
        icon: Icons.exit_to_app,
        label: 'طلب إذن انصراف',
        subtitle: 'تغطية ${day!.earlyLeaveMinutes} دقيقة خروج مبكر.',
        color: const Color(0xFFF59E0B),
        onTap: () => _openPermitRequest(context, ref, 'early_departure'),
      ));
    }

    // ── يوم قادم → طلب إجازة مسبقة ──
    if (isOwn && isFuture) {
      actions.add(_ActionTile(
        icon: Icons.beach_access_outlined,
        label: 'طلب إجازة مسبقة',
        subtitle: 'تقديم طلب إجازة لهذا اليوم — يعتمده المدير المباشر.',
        color: const Color(0xFF6366F1),
        onTap: () => _openLeaveRequest(context, ref),
      ));
    }

    // ── التعديل الإداري لليوم أو إلغاؤه — الموارد البشرية والإدارة (canEditDays من الخادم) ──
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
          child: Text(
              isOwn
                  ? 'لا توجد إجراءات متاحة لهذا اليوم.'
                  : 'للاطلاع فقط — الطلبات يقدّمها الموظف من حسابه، والتعديل الإداري للموارد البشرية.',
              textAlign: TextAlign.center,
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

  // ── فتح نموذج تعديل حالة اليوم بأثر رجعي (إجازة / مأمورية / قافلة / حملة تبرعات) ──
  Future<void> _openRetroactiveDayChange(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context); // إغلاق ورقة التفاصيل
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RetroactiveDayChangeSheet(
        dateStr: _dateStr,
        dayNameAr: day?.dayNameAr ?? _dayNameFull,
        currentStatus: day?.status ?? 'غير مسجل',
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(mobileCommandsProvider).submitRequest(
            result['type'] as String,
            result['title'] as String,
            result['reason'] as String,
            result['payload'] as Map<String, dynamic>,
          );
      _invalidateProviders(ref);
      ref.invalidate(myLeaveBalancesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب تعديل حالة اليوم بنجاح.')),
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
            checkIn: result['checkIn'] as DateTime?,
            checkOut: result['checkOut'] as DateTime?,
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
    'weekly_rest_comp': 'بدل راحة',
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
        'dayMark': true,
      },
    });
  }
}

// ─── ورقة تعديل حالة اليوم بأثر رجعي (إجازة / مأمورية / قافلة / حملة تبرعات) ───

class _RetroactiveDayChangeSheet extends StatefulWidget {
  const _RetroactiveDayChangeSheet({
    required this.dateStr,
    required this.dayNameAr,
    required this.currentStatus,
  });
  final String dateStr;
  final String dayNameAr;
  final String currentStatus;

  @override
  State<_RetroactiveDayChangeSheet> createState() => _RetroactiveDayChangeSheetState();
}

class _RetroactiveDayChangeSheetState extends State<_RetroactiveDayChangeSheet> {
  String _category = 'leave';
  String _leaveType = 'casual';
  final _locationCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _locationCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  static const _categories = [
    (id: 'leave', label: 'إجازة معتمدة', icon: Icons.beach_access_rounded, color: Color(0xFF4F46E5)),
    (id: 'mission', label: 'مأمورية عمل', icon: Icons.directions_car_rounded, color: Color(0xFF0EA5E9)),
    (id: 'convoy', label: 'قافلة مساعدات (كامب)', icon: Icons.volunteer_activism_rounded, color: Color(0xFF8B5CF6)),
    (id: 'fundraising', label: 'يوم ترفيهي (فاندي / Fun Day)', icon: Icons.celebration_rounded, color: Color(0xFFEC4899)),
  ];

  static const _leaveOptions = [
    (
      id: 'casual',
      label: 'إجازة عارضة',
      badge: 'تنفيذ فوري',
      desc: 'تخصم مباشرة من رصيد الإجازات العارضة المتاح.',
      color: Color(0xFF0F9F6E),
    ),
    (
      id: 'annual',
      label: 'إجازة اعتيادية',
      badge: 'اعتماد المدير',
      desc: 'تخصم من رصيدك السنوي بعد موافقة المدير المباشر.',
      color: Color(0xFF6366F1),
    ),
    (
      id: 'weekly_rest_comp',
      label: 'بدل راحة',
      badge: 'اعتماد المدير',
      desc: 'تعويض عن يوم راحة أسبوعية عملت به سابقاً.',
      color: Color(0xFFF59E0B),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // مقبض السحب
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // الرأس: العنوان وتاريخ اليوم والحالة الحالية
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.published_with_changes_rounded, color: Color(0xFF4F46E5), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تعديل حالة اليوم',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${widget.dayNameAr} ${widget.dateStr}',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
                ),
                child: Text(
                  widget.currentStatus,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // تنبيه توضيحي
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Color(0xFF4F46E5), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'متاح تعديل حالة هذا اليوم طالما يقع في نفس الشهر الحالي. سيتم رفع الطلب لمديرك المباشر لاعتماده.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF3730A3), height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 1. اختيار الفئة
          Text(
            'الحالة الجديدة المطلوبة لهذا اليوم:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: scheme.onSurface),
          ),
          const SizedBox(height: 10),

          // بطاقات الفئات الأربع
          Row(
            children: _categories.map((cat) {
              final isSelected = _category == cat.id;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _category = cat.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? cat.color.withValues(alpha: .15) : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? cat.color : scheme.outlineVariant.withValues(alpha: .4),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.icon, size: 22, color: isSelected ? cat.color : scheme.onSurfaceVariant),
                        const SizedBox(height: 6),
                        Text(
                          cat.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                            color: isSelected ? cat.color : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // 2. إذا كانت الفئة إجازة: عرض خيارات الإجازة (عارضة / اعتيادية / بدل راحة)
          if (_category == 'leave') ...[
            Text(
              'نوع الإجازة المطلوبة:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            ..._leaveOptions.map((opt) {
              final isSelected = _leaveType == opt.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected ? opt.color.withValues(alpha: .09) : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _leaveType = opt.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? opt.color : scheme.outlineVariant.withValues(alpha: .3),
                          width: isSelected ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? opt.color : scheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      opt.label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected ? opt.color : scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: opt.color.withValues(alpha: .15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        opt.badge,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: opt.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  opt.desc,
                                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],

          // 3. إذا كانت مأمورية أو قافلة أو فاندي ترفيهي: إدخال الوجهة / الموقع
          if (_category != 'leave') ...[
            TextFormField(
              controller: _locationCtrl,
              decoration: InputDecoration(
                labelText: switch (_category) {
                  'mission' => 'وجهة / موضوع المأمورية الخارجية',
                  'convoy' => 'مقر القافلة / القرية المستهدفة للمساعدات (كامب)',
                  'fundraising' => 'مكان اليوم الترفيهي (اسم الفيلا / المنتجع / المكان)',
                  _ => 'الموقع / الوجهة',
                },
                hintText: switch (_category) {
                  'mission' => 'مثال: زيارة فرع، مأمورية عمل خارجية...',
                  'convoy' => 'مثال: قافلة مساعدات أسقف ومياه - قرى الفيوم...',
                  'fundraising' => 'مثال: فيلا سقارة / منتجع وادي النخيل...',
                  _ => 'اكتب المكان أو الوجهة...',
                },
                prefixIcon: Icon(
                  switch (_category) {
                    'mission' => Icons.directions_car_rounded,
                    'convoy' => Icons.volunteer_activism_rounded,
                    'fundraising' => Icons.celebration_rounded,
                    _ => Icons.place_rounded,
                  },
                  size: 20,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 6),

          // 4. حقل سبب التعديل (إلزامي)
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'سبب التعديل أو الملاحظات (إلزامي)',
              hintText: 'وضح سبب طلب تعديل حالة هذا اليوم...',
              prefixIcon: const Icon(Icons.edit_note_rounded, size: 22),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),

          const SizedBox(height: 20),

          // زر الإرسال
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: const Color(0xFF4F46E5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _submit,
            icon: const Icon(Icons.send_rounded, size: 20),
            label: const Text(
              'إرسال طلب التعديل للاعتماد',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال سبب التعديل (3 أحرف على الأقل)')),
      );
      return;
    }

    String title;
    final Map<String, dynamic> payload = {
      'startDate': widget.dateStr,
      'endDate': widget.dateStr,
      'dayMark': true,
    };

    if (_category == 'leave') {
      const leaveNames = {
        'casual': 'عارضة',
        'annual': 'اعتيادية',
        'weekly_rest_comp': 'بدل راحة',
      };
      payload['leaveType'] = _leaveType;
      title = 'طلب إجازة ${leaveNames[_leaveType] ?? _leaveType} — ${widget.dateStr}';
    } else {
      var loc = _locationCtrl.text.trim();
      if (loc.isEmpty) {
        loc = switch (_category) {
          'mission' => 'مأمورية عمل خارجية',
          'convoy' => 'قافلة مساعدات خارجية (كامب)',
          'fundraising' => 'يوم ترفيهي للموظفين (فاندي / Fun Day)',
          _ => 'نشاط عمل',
        };
      }
      payload['location'] = loc;
      title = switch (_category) {
        'mission' => 'مأمورية عمل خارجية — ${widget.dateStr}',
        'convoy' => 'قافلة مساعدات — ${widget.dateStr}',
        'fundraising' => 'يوم ترفيهي (فاندي) — ${widget.dateStr}',
        _ => 'تكليف عمل — ${widget.dateStr}',
      };
    }

    Navigator.pop(context, {
      'type': _category,
      'title': title,
      'reason': reason,
      'payload': payload,
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
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    _type = widget.preselectType;
    _time = _type == 'missing_check_in'
        ? const TimeOfDay(hour: 9, minute: 0)
        : const TimeOfDay(hour: 17, minute: 0);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: _type == 'missing_check_in'
          ? 'تحديد وقت الحضور التقريبي'
          : 'تحديد وقت الانصراف التقريبي',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;
    final isCheckIn = _type == 'missing_check_in';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.fingerprint_rounded, color: scheme.error, size: 22),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'نسيان بصمة',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: scheme.error,
                    ),
                  ),
                  Text(
                    'اليوم: ${widget.dateStr}',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'missing_check_in', label: Text('نسيان حضور')),
              ButtonSegment(value: 'missing_check_out', label: Text('نسيان انصراف')),
            ],
            selected: {_type},
            onSelectionChanged: (v) {
              setState(() {
                final newType = v.first;
                if (newType != _type) {
                  if (_type == 'missing_check_in' &&
                      _time == const TimeOfDay(hour: 9, minute: 0)) {
                    _time = const TimeOfDay(hour: 17, minute: 0);
                  } else if (_type == 'missing_check_out' &&
                      _time == const TimeOfDay(hour: 17, minute: 0)) {
                    _time = const TimeOfDay(hour: 9, minute: 0);
                  }
                  _type = newType;
                }
              });
            },
          ),
          const SizedBox(height: 14),
          // ── حقل الساعة لاختيار الوقت التقريبي ──
          InkWell(
            onTap: _pickTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: .35),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.access_time_filled_rounded,
                      color: scheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCheckIn ? 'وقت الحضور التقريبي' : 'وقت الانصراف التقريبي',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _time.format(context),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_rounded, size: 14, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'تغيير',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
            icon: const Icon(Icons.send_rounded),
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
    DateTime? checkIn;
    DateTime? checkOut;
    final date = DateTime.tryParse(widget.dateStr);
    if (date != null) {
      final dt = DateTime(
        date.year,
        date.month,
        date.day,
        _time.hour,
        _time.minute,
      );
      if (_type == 'missing_check_in') {
        checkIn = dt;
      } else {
        checkOut = dt;
      }
    }
    Navigator.pop(context, {
      'type': _type,
      'reason': reason,
      'checkIn': checkIn,
      'checkOut': checkOut,
      'time': _time,
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
    ('convoy', 'قافلة مساعدات (كامب)', Icons.volunteer_activism_outlined),
    ('fundraising', 'يوم ترفيهي (فاندي / Fun Day)', Icons.celebration_outlined),
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
                : 'اعتماد الحالة',
            notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
            leaveType: _dayType == 'leave' || _dayType == 'absent' ? _leaveType : null,
          );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التعديل بنجاح.')),
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
              'تعديل يوم ${widget.dateStr}',
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

