part of '../monthly_attendance_statement_page.dart';

class _AttendancePercentageCard extends StatelessWidget {
  const _AttendancePercentageCard({required this.statement});
  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final s = statement.summary;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isCurrentMonth =
        statement.year == now.year && statement.month == now.month;

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
        final isFutureDay =
            isCurrentMonth &&
            date != null &&
            date.isAfter(DateTime(now.year, now.month, now.day));
        final isRest =
            d.status == 'راحة' ||
            d.status == 'راحة أسبوعية' ||
            d.status == 'عطلة رسمية';

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
            final isTodayDay =
                isCurrentMonth &&
                date != null &&
                date.year == now.year &&
                date.month == now.month &&
                date.day == now.day;
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
    final double displayPct = rateAvailable
        ? statement.attendancePercentage.clamp(0.0, 100.0)
        : 0;
    final pctText = isExempt
        ? 'معفى'
        : rateAvailable
            ? '${(displayPct >= 99.5 && displayPct < 100 ? 99 : displayPct.round())}%'
            : '—';
    final excludedLeave = s.attendanceRateExcludedLeaveDays;

    final purePresenceRate = rateAvailable
        ? ((presentInOffice / dueDays) * 100).clamp(0.0, 100.0)
        : 0.0;

    final pctColor = !rateAvailable
        ? scheme.onSurfaceVariant
        : displayPct >= 85
            ? const Color(0xFF0F9F6E)
            : displayPct >= 70
                ? const Color(0xFFF59E0B)
                : scheme.error;
    // حلقة النسبة تحتاج مساحة أكبر عندما يكبّر المستخدم خط النظام.
    final ringSize = MediaQuery.textScalerOf(
      context,
    ).scale(94).clamp(94.0, 128.0).toDouble();

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
                  width: ringSize,
                  height: ringSize,
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
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
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
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (isCurrentMonth) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
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
                                ? '${s.attendanceRatePresentDays} من $dueDays'
                                : 'لا توجد أيام عمل مستحقة بعد',
                        color: pctColor,
                      ),
                      if (excludedLeave > 0 && rateAvailable)
                        _PctDetailRow(
                          label: 'مستبعد من النسبة',
                          value: '${arDays(excludedLeave)} إجازة',
                        ),
                      _PctDetailRow(
                        label: 'حضور بالجمعية',
                        value: arDays(presentInOffice),
                      ),
                      if (convoysCount > 0)
                        _PctDetailRow(
                          label: 'قوافل خارجية',
                          value: arDays(convoysCount),
                        ),
                      if (fundiCount > 0)
                        _PctDetailRow(
                          label: 'فاندي (ترفيهي)',
                          value: arDays(fundiCount),
                        ),
                      if (missionsCount > 0)
                        _PctDetailRow(
                          label: 'مأموريات خارجية',
                          value: arDays(missionsCount),
                        ),
                      if (leavesCount > 0)
                        _PctDetailRow(
                          label: 'إجازات',
                          value: arDays(leavesCount),
                        ),
                      if (unexcusedAbsences > 0)
                        _PctDetailRow(
                          label: 'غياب غير مبرر',
                          value: arDays(unexcusedAbsences),
                          color: scheme.error,
                        ),
                      if (upcomingWorkDays > 0)
                        _PctDetailRow(
                          label: 'أيام عمل قادمة',
                          value: arDays(upcomingWorkDays),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceAround,
              spacing: 12,
              runSpacing: 6,
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
                  label: 'حضور الجمعية فقط',
                  value: rateAvailable
                      ? '${purePresenceRate.toStringAsFixed(0)}%'
                      : '—',
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
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
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
  const _PctDetailRow({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      // القيمة تأخذ المساحة المتبقية وتلتف — كانت «لا توجد أيام عمل مستحقة بعد»
      // تتجاوز البطاقة على الهواتف.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── بطاقة مؤشر إنجاز ساعات العمل المستهدفة ─────────────────────

