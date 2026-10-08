import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

/// «شهري في لمحة»: الشهر الجاري في بطاقة واحدة — الحضور والتأخير ورصيد
/// الإجازات وغرامات الشهر — من مزوّدات الكشف والأرصدة والغرامات القائمة.
/// الضغط يفتح الكشف الشهري الكامل.
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

    final tiles = <_GlanceTile>[
      _GlanceTile(
        icon: Icons.how_to_reg_rounded,
        label: 'الحضور',
        value: rate == null ? '—' : '${rate.round()}%',
        detail: rate == null
            ? 'لا أيام عمل مستحقة بعد'
            : '${s?.attendanceRatePresentDays ?? 0} من $dueDays',
        color: rate == null
            ? null
            : rate >= 90
            ? AppColors.statusSuccess
            : rate >= 75
            ? AppColors.statusWarning
            : AppColors.statusDanger,
      ),
      _GlanceTile(
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
      ),
      _GlanceTile(
        icon: Icons.beach_access_rounded,
        label: 'رصيد السنوية',
        value: annual == null ? '—' : arDays(annual.availableUnits.floor()),
        detail: casual == null
            ? 'الإجازات'
            : 'العارضة: ${fmtUnits(casual.availableUnits)}',
        color: AppColors.statusInfo,
      ),
      _GlanceTile(
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
      ),
    ];

    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const MonthlyAttendanceStatementPage(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights_rounded, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'شهري في لمحة — ${DateFormat('MMMM', 'ar').format(now)}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_left_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: tiles,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlanceTile extends StatelessWidget {
  const _GlanceTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color ?? scheme.onSurface,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
