part of '../monthly_attendance_statement_page.dart';

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
    final pct = targetHours > 0
        ? (workedHours / targetHours * 100).clamp(0.0, 150.0)
        : 0.0;
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
                      child: Icon(
                        Icons.speed_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'مؤشر ساعات العمل المستهدفة',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'مستهدف: ${targetHours.toStringAsFixed(0)} ساعة',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
                    valueColor: s.totalOvertimeMinutes > 0
                        ? const Color(0xFF0F9F6E)
                        : null,
                  ),
                ),
                Expanded(
                  child: _MiniMetric(
                    label: 'إجمالي التأخير',
                    value: '${s.totalLateMinutes} د',
                    icon: Icons.history_toggle_off_rounded,
                    valueColor: s.totalLateMinutes > 0
                        ? const Color(0xFFD97706)
                        : null,
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
          desc:
              'لديك ${s.missingCheckInCount + s.missingCheckOutCount} بصمات تحتاج لتصحيح لتفادي احتساب عجز بالساعات.',
        ),
      );
    }

    if (s.convoyFundiDays > 0) {
      insights.add(
        _InsightItem(
          icon: Icons.celebration_rounded,
          color: const Color(0xFF7C3AED),
          title: 'أنشطة خارجية وميدانية معتمدة',
          desc:
              'سجلت ${s.convoyFundiDays} أيام في قوافل المساعدات الإنسانية والأنشطة الترفيهية (فاندي).',
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
          desc:
              'حققت $hours ساعة إضافية معتمدة تُضاف إلى رصيدك وسجل أدائك الشهري.',
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
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...insights.map(
          (item) => Padding(
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
                        Text(
                          item.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: item.color,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        item.desc,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
          ),
        ),
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
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: valueColor ?? scheme.onSurface,
          ),
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
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 19,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── بطاقة ملخص (قيمة + وحدة) ────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.unit,
  });
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
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
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

