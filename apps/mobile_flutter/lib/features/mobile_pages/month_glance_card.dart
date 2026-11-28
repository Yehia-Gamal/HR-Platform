import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

/// «شهري في لمحة»: الشهر الجاري في بطاقة واحدة تفاعلية — الحضور والتأخير
/// ورصيد الإجازات وغرامات الشهر وإجمالي إجازات وأذونات الشهر.
/// كل خانة قابلة للنقر وتوجّه للقسم المخصص لها مباشرة.
class MonthGlanceCard extends ConsumerWidget {
  const MonthGlanceCard({super.key});

  /// غرامة ما زالت مستحقة الدفع.
  static const _duePenalty = {'pending_payment', 'doubled', 'suspended'};

  /// غرامة سقطت (أُلغيت أو قُبل عذرها) — لا تُحسب على الشهر.
  static const _voidPenalty = {'cancelled', 'excused', 'waived'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final statement = ref
        .watch(myMonthlyStatementProvider((now.year, now.month)))
        .asData
        ?.value;
    final balances = ref.watch(myLeaveBalancesProvider).asData?.value;
    final penalties = ref.watch(myInstantPenaltiesProvider).asData?.value;
    final permitBalance = ref.watch(myPermitBalanceProvider).asData?.value;

    if (statement == null && balances == null && penalties == null) {
      return const SizedBox.shrink();
    }

    final s = statement?.summary;
    final dueDays = s?.attendanceRateDueDays ?? 0;
    final rate = dueDays > 0 ? s?.attendanceRate : null;
    final lateDays =
        statement?.days.where((d) => d.lateMinutes > 0 && !d.isFuture).length ??
        0;
    final lateMinutes = s?.totalLateMinutes ?? 0;

    MobileLeaveBalance? balance(String code) {
      for (final b in balances ?? const <MobileLeaveBalance>[]) {
        if (b.code == code) return b;
      }
      return null;
    }

    final annual = balance('annual');
    final casual = balance('casual');

    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final monthPenalties = (penalties ?? const <MobileInstantPenalty>[])
        .where(
          (p) =>
              p.workDate.startsWith(monthKey) &&
              !_voidPenalty.contains(p.status),
        )
        .toList();
    final dueAmount = monthPenalties
        .where((p) => _duePenalty.contains(p.status))
        .fold<double>(0, (sum, p) => sum + p.currentAmount);

    // إجمالي إجازات الشهر
    final monthLeaveDays =
        s?.leaveDays ??
        statement?.days.where((d) => d.hasLeave && !d.isFuture).length ??
        0;

    // إجمالي أذونات الشهر والمتبقي
    final usedPermits =
        permitBalance?.totalUsed ??
        s?.permitCount ??
        statement?.days.where((d) => d.hasPermit && !d.isFuture).length ??
        0;
    final remainingPermits =
        permitBalance?.remainingPermits ?? (4 - usedPermits).clamp(0, 4);
    final remainingHours =
        permitBalance?.remainingHours ?? (remainingPermits * 2);

    void openMonthlyStatement() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const MonthlyAttendanceStatementPage(),
        ),
      );
    }

    void openPenalties() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyInstantPenaltiesPage()),
      );
    }

    void openRequests() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MobileRequestsPage()),
      );
    }

    final tiles = <_GlanceTile>[
      _GlanceTile(
        id: 'attendance',
        icon: Icons.how_to_reg_rounded,
        label: 'نسبة الحضور',
        value: rate == null ? '—' : '${rate.round()}%',
        detail: rate == null
            ? 'لا أيام عمل مستحقة بعد'
            : '${s?.attendanceRatePresentDays ?? 0} من $dueDays يوم عمل',
        color: rate == null
            ? null
            : rate >= 90
            ? AppColors.statusSuccess
            : rate >= 75
            ? AppColors.statusWarning
            : AppColors.statusDanger,
        onTap: openMonthlyStatement,
      ),
      _GlanceTile(
        id: 'lateness',
        icon: Icons.schedule_rounded,
        label: 'التأخير',
        value: statement == null
            ? '—'
            : (lateDays == 0 ? 'لا تأخير' : arDays(lateDays)),
        detail: lateMinutes > 0 ? arDurationMinutes(lateMinutes) : 'هذا الشهر',
        color: statement == null
            ? null
            : (lateDays == 0
                  ? AppColors.statusSuccess
                  : AppColors.statusWarning),
        onTap: openMonthlyStatement,
      ),
      _GlanceTile(
        id: 'annual-leave',
        icon: Icons.beach_access_rounded,
        label: 'رصيد السنوية',
        value: annual == null ? '—' : arDays(annual.availableUnits.floor()),
        detail: casual == null
            ? 'الإجازات'
            : 'العارضة: ${fmtUnits(casual.availableUnits)}',
        color: AppColors.statusInfo,
        onTap: openRequests,
      ),
      _GlanceTile(
        id: 'penalties',
        icon: Icons.receipt_long_rounded,
        label: 'غرامات الشهر',
        value: penalties == null
            ? '—'
            : (monthPenalties.isEmpty
                  ? 'لا غرامات'
                  : '${monthPenalties.length}'),
        detail: dueAmount > 0
            ? 'مستحق ${fmtUnits(dueAmount)} ج.م'
            : 'لا مستحقات',
        color: penalties == null
            ? null
            : (dueAmount > 0
                  ? AppColors.statusDanger
                  : AppColors.statusSuccess),
        onTap: openPenalties,
      ),
      _GlanceTile(
        id: 'monthly-leave',
        icon: Icons.event_available_rounded,
        label: 'إجازات الشهر',
        value: monthLeaveDays == 0 ? 'لا إجازات' : arDays(monthLeaveDays),
        detail: monthLeaveDays == 0 ? 'دوام كامل' : 'مستهلكة هذا الشهر',
        color: monthLeaveDays == 0
            ? AppColors.statusSuccess
            : const Color(0xFF6366F1),
        onTap: openRequests,
      ),
      _GlanceTile(
        id: 'monthly-permits',
        icon: Icons.timer_outlined,
        label: 'أذونات الشهر',
        value: usedPermits == 0
            ? 'لا أذونات'
            : (usedPermits == 1
                  ? 'إذن واحد'
                  : usedPermits == 2
                  ? 'إذنان'
                  : '$usedPermits أذونات'),
        detail: 'متبقي $remainingPermits من 4 ($remainingHours س)',
        color: usedPermits >= 4
            ? AppColors.statusDanger
            : usedPermits > 0
            ? AppColors.statusWarning
            : AppColors.statusSuccess,
        onTap: openRequests,
      ),
    ];

    final theme = Theme.of(context);
    final title = 'شهري في لمحة — ${DateFormat('MMMM', 'ar').format(now)}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                Semantics(
                  container: true,
                  identifier: 'today.month.heading',
                  header: true,
                  label: title,
                  excludeSemantics: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MergeSemantics(
                  child: Semantics(
                    identifier: 'today.month.statement',
                    child: TextButton(
                      onPressed: openMonthlyStatement,
                      child: const Text('الكشف الكامل'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final minTileWidth = MediaQuery.textScalerOf(
                  context,
                ).scale(144);
                final twoColumns =
                    constraints.maxWidth >= minTileWidth * 2 + gap;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: [
                    if (!twoColumns)
                      ...tiles
                    else
                      for (var i = 0; i < tiles.length; i += 2)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: gap,
                            children: [
                              Expanded(child: tiles[i]),
                              if (i + 1 < tiles.length)
                                Expanded(child: tiles[i + 1])
                              else
                                const Spacer(),
                            ],
                          ),
                        ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GlanceTile extends StatelessWidget {
  const _GlanceTile({
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.color,
    required this.onTap,
  });

  final String id;
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.onSurfaceVariant;
    return Semantics(
      identifier: 'today.month.$id',
      button: true,
      label: '$label، $value، $detail',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: .18)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 55),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Icon(icon, size: 18, color: accent)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          detail,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 16,
                    color: accent.withValues(alpha: .5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
