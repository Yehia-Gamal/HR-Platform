part of '../my_instant_penalties_page.dart';

class _MySummaryCard extends StatelessWidget {
  const _MySummaryCard({required this.items});

  final List<MobileInstantPenalty> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = items.where((p) => p.status == 'pending_payment');
    final escalated = items.where(
      (p) => p.status == 'doubled' || p.status == 'suspended',
    );
    final paid = items.where((p) => p.status == 'paid');
    final cancelled = items.where((p) => p.status == 'cancelled');
    double sum(Iterable<MobileInstantPenalty> list) =>
        list.fold<double>(0, (s, p) => s + p.currentAmount);
    final dueTotal = sum(pending) + sum(escalated);
    final hasDue = dueTotal > 0;
    final heroColor = hasDue
        ? (escalated.isNotEmpty
              ? AppColors.statusDanger
              : AppColors.statusWarning)
        : AppColors.statusSuccess;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── أهم رقم أولًا: ما عليك الآن ──
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: heroColor.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    hasDue ? Icons.payments_outlined : Icons.verified_rounded,
                    color: heroColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasDue ? 'المستحق عليك الآن' : 'لا مستحقات عليك',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasDue
                            ? _money(dueTotal)
                            : items.isEmpty
                            ? 'سجلّك نظيف'
                            : 'كل غراماتك مسددة أو ملغاة',
                        style: TextStyle(
                          fontSize: hasDue ? 24 : 16,
                          fontWeight: FontWeight.w900,
                          color: heroColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _CountTile(
                  label: 'بانتظار السداد',
                  count: pending.length,
                  amount: sum(pending),
                  color: AppColors.statusWarning,
                ),
                const SizedBox(width: 8),
                _CountTile(
                  label: 'مضاعفة',
                  count: escalated.length,
                  amount: sum(escalated),
                  color: AppColors.statusDanger,
                ),
                const SizedBox(width: 8),
                _CountTile(
                  label: 'مسددة',
                  count: paid.length,
                  amount: sum(paid),
                  color: AppColors.statusSuccess,
                ),
                const SizedBox(width: 8),
                _CountTile(
                  label: 'ملغاة/معفاة',
                  count: cancelled.length,
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
            if (items.any((p) => p.status == 'suspended')) ...[
              const SizedBox(height: 12),
              const _Notice(
                icon: Icons.block_rounded,
                color: AppColors.statusDanger,
                text:
                    'حسابك موقوف بسبب غرامة مضاعفة لم تُسدَّد — توجّه للموارد البشرية للسداد وإعادة فتح الحساب.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PolicyCard extends ConsumerWidget {
  const _PolicyCard();

  static String _formatClockOffset(String timeStr, int offsetMinutes) {
    final parts = timeStr.split(':');
    if (parts.length < 2) return '';
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final totalM = h * 60 + m + offsetMinutes;
    final targetH = (totalM ~/ 60) % 24;
    final targetM = totalM % 60;
    final period = targetH < 12 ? 'ص' : 'م';
    final h12 = targetH == 0 ? 12 : (targetH > 12 ? targetH - 12 : targetH);
    final mStr = targetM > 0 ? ':${targetM.toString().padLeft(2, '0')}' : ':00';
    return '$h12$mStr $period';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final shiftInfo = ref.watch(myWorkShiftInfoProvider).asData?.value;
    final shift = shiftInfo?.currentShift;

    final String startLabel;
    final String tier1Label;
    final String tier2Label;
    final String tier3Label;

    if (shift != null) {
      final baseStart = shift.activeStartTime;
      final grace = shift.graceInMinutes;
      final hasPermit = shift.hasPermitToday;

      tier1Label = 'حتى ${_formatClockOffset(baseStart, 30)}';
      tier2Label = 'حتى ${_formatClockOffset(baseStart, 60)}';
      tier3Label = 'حتى ${_formatClockOffset(baseStart, 120)}';

      // سطر واحد واضح بدل الأقواس المتداخلة «(10 ص – 6 م) (بداية الدوام…)»
      if (hasPermit) {
        startLabel =
            'إذن تأخير اليوم: يبدأ حسابك ${shift.formattedActiveStartTime} · سماح $grace د حتى ${shift.formattedActiveGraceEndTime}';
      } else {
        startLabel =
            '${shift.name} · يبدأ ${shift.formattedStartTime} · سماح $grace د حتى ${shift.formattedGraceEndTime}';
      }
    } else {
      startLabel = 'يبدأ الدوام 10:00 ص · سماح 15 د حتى 10:15 ص';
      tier1Label = 'حتى 10:30 ص';
      tier2Label = 'حتى 11:00 ص';
      tier3Label = 'حتى 12:00 م';
    }

    // سُلّم متدرّج اللون؛ كل خانة سطران ثابتان (المبلغ + متى) فلا تنكسر
    // «بعد 24 ساعة دون سداد» على ثلاثة أسطر.
    Widget tier(String time, String amount, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                amount,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                time,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rule_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لائحة غرامات التأخير',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (shift?.hasPermitToday ?? false)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.statusInfo.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.statusInfo.withValues(alpha: .3),
                      ),
                    ),
                    child: Text(
                      'إذن تأخير نشط اليوم',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.statusInfo,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule_rounded, size: 15, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    startLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                tier(tier1Label, '20 ج.م', AppColors.statusWarning),
                const SizedBox(width: 6),
                tier(tier2Label, '50 ج.م', const Color(0xFFE07A10)),
                const SizedBox(width: 6),
                tier(tier3Label, '150 ج.م', const Color(0xFFE2582A)),
                const SizedBox(width: 6),
                tier('دون سداد 24 س', '500 ج.م', AppColors.statusDanger),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.volunteer_activism_outlined,
                  size: 15,
                  color: AppColors.statusSuccess,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'لا تُخصم من الراتب — تُودَع كاملة في صندوق الزمالة لدعم الزملاء.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.verified_outlined,
                  size: 15,
                  color: Color(0xFF059669),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'تعويض التأخير: إذا استوفيت 8 ساعات عمل كاملة وسجلت بصمة الانصراف بمقر العمل، تُسقَط الغرامة وتُلغى تلقائياً.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF059669),
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
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

class _PayReminderCard extends StatelessWidget {
  const _PayReminderCard({required this.unpaid});

  final List<MobileInstantPenalty> unpaid;

  @override
  Widget build(BuildContext context) {
    final total = unpaid.fold<double>(0, (s, p) => s + p.currentAmount);
    return Card(
      color: AppColors.statusWarning.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.statusWarning.withValues(alpha: .4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Notice(
              icon: Icons.payments_outlined,
              color: AppColors.statusWarning,
              text:
                  'عليك ${_money(total)} — يتم السداد نقدًا إلى أ/ إبراهيم سلامة وإبلاغ باشمهندس يحيى بالدفع خلال 24 ساعة، وتظهر «مسددة» بعد تأكيد الإدارة.',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final text =
                    'السلام عليكم، أود إبلاغكم بسداد غرامة الحضور بمبلغ ${_money(total)} إلى أ/ إبراهيم سلامة لصالح صندوق الزمالة والتكافل.';
                final uri = Uri.parse(
                  'https://wa.me/?text=${Uri.encodeComponent(text)}',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('إبلاغ بالدفع عبر واتساب'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// بطاقة الغرامة — كل التفاصيل
// ═══════════════════════════════════════════════════════════════════════════

