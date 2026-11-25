part of '../my_instant_penalties_page.dart';

class _FundTab extends ConsumerWidget {
  const _FundTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(fellowshipFundSummaryProvider);
    final txs = ref.watch(fellowshipFundTransactionsProvider);
    final canWithdraw = canWithdrawFromFund(ref);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(fellowshipFundSummaryProvider);
        ref.invalidate(fellowshipFundTransactionsProvider);
      },
      child: summary.when(
        loading: () => const _Loading(),
        error: (error, _) => _ErrorView(
          message: humanizeError(error),
          onRetry: () => ref.invalidate(fellowshipFundSummaryProvider),
        ),
        data: (s) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          children: [
            Card(
              color: AppColors.statusSuccess.withValues(alpha: .08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: AppColors.statusSuccess.withValues(alpha: .35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(
                      Icons.volunteer_activism_rounded,
                      color: AppColors.statusSuccess,
                      size: 30,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'رصيد صندوق الزمالة والتكافل',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _money(s.currentBalance),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.statusSuccess,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _CountTile(
                          label: 'إجمالي الوارد',
                          count: s.inflowsCount,
                          amount: s.totalInflows,
                          color: AppColors.statusSuccess,
                        ),
                        const SizedBox(width: 8),
                        _CountTile(
                          label: 'إجمالي المصروف',
                          count: s.outflowsCount,
                          amount: s.totalOutflows,
                          color: AppColors.statusDanger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'هذا الشهر: وارد ${_money(s.monthlyInflows)} · مصروف ${_money(s.monthlyOutflows)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const _Notice(
              icon: Icons.info_outline_rounded,
              color: AppColors.statusInfo,
              text:
                  'تُودَع غرامات التأخير كاملة في الصندوق ولا تُخصم من الرواتب، ويُصرف منه لدعم الزملاء في الحالات الطارئة والرعاية الصحية والمناسبات الاجتماعية.',
            ),
            if (s.categories.isNotEmpty) ...[
              const SizedBox(height: 16),
              const _SectionTitle(title: 'حسب البند'),
              const SizedBox(height: 6),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      for (final c in s.categories)
                        _DetailRow(
                          label: c.category,
                          value:
                              '${c.type == 'outflow' ? 'مصروف' : 'وارد'} ${_money(c.total)} (${c.count})',
                          color: c.type == 'outflow'
                              ? AppColors.statusDanger
                              : AppColors.statusSuccess,
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (canWithdraw) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: s.currentBalance > 0
                    ? () => _showWithdrawSheet(context, ref, s.currentBalance)
                    : null,
                icon: const Icon(Icons.outbox_rounded),
                label: Text(
                  s.currentBalance > 0
                      ? 'تسجيل صرف من الصندوق'
                      : 'لا يوجد رصيد للصرف',
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
              ),
              onPressed: () async {
                final now = DateTime.now();
                final todayStr = DateFormat('yyyy-MM-dd').format(now);
                final text =
                    '*🤝 تقرير صندوق الزمالة والتكافل الاجتماعي — أحلى شباب*\n'
                    '📅 التاريخ: $todayStr\n'
                    '💰 الرصيد الحالي: ${_money(s.currentBalance)}\n'
                    '📥 إجمالي الوارد: ${_money(s.totalInflows)} (${s.inflowsCount} حركة)\n'
                    '📤 إجمالي المصروف: ${_money(s.totalOutflows)} (${s.outflowsCount} حركة)\n'
                    '📊 هذا الشهر: وارد ${_money(s.monthlyInflows)} | مصروف ${_money(s.monthlyOutflows)}\n\n'
                    '🤝 *تذكير:* جميع حصيلة الغرامات تذهب كاملة لصندوق الزمالة والتكافل لدعم الزملاء والتكافل الاجتماعي.';
                final uri = Uri.parse(
                  'https://wa.me/?text=${Uri.encodeComponent(text)}',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('مشاركة تقرير الصندوق عبر واتساب'),
            ),
            const SizedBox(height: 16),
            const _SectionTitle(title: 'حركات الصندوق'),
            const SizedBox(height: 6),
            txs.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(humanizeError(error)),
              data: (list) => list.isEmpty
                  ? const _EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'لا توجد حركات بعد',
                      subtitle:
                          'تظهر هنا مبالغ الغرامات المسددة وما يُصرف من الصندوق.',
                    )
                  : Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < list.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _FundTxTile(tx: list[i]),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FundTxTile extends StatelessWidget {
  const _FundTxTile({required this.tx});

  final FellowshipFundTransaction tx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tx.isInflow
        ? AppColors.statusSuccess
        : AppColors.statusDanger;
    final String title;
    if (tx.isInflow) {
      if (tx.sourceType == 'instant_penalty') {
        title = tx.employeeName != null && tx.employeeName!.isNotEmpty
            ? 'سداد غرامة تأخير — ${tx.employeeName}'
            : 'سداد غرامة تأخير';
      } else {
        title = tx.category ?? 'إيداع';
      }
    } else {
      title = tx.category ?? 'صرف من الصندوق';
    }
    final sub = [
      if (tx.employeeName != null && tx.sourceType != 'instant_penalty')
        'الزميل: ${tx.employeeName}',
      if (tx.reason != null &&
          tx.reason != tx.category &&
          tx.reason != tx.employeeName)
        tx.reason!,
      '${DateFormat('d MMMM y', 'ar').format(AppTime.toCairo(tx.createdAt))} · ${DateFormat('h:mm a', 'ar').format(AppTime.toCairo(tx.createdAt))}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(
              tx.isInflow ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                for (final line in sub)
                  Text(
                    humanizeIsoLike(line),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // الاتجاه بالأيقونة واللون — علامة +/− تنقلب مع «ج.م» في سياق عربي
              Text(
                _money(tx.amount),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              if (tx.balanceAfter != null)
                Text(
                  'الرصيد ${_money(tx.balanceAfter!)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// عناصر مشتركة
// ═══════════════════════════════════════════════════════════════════════════

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.count,
    required this.color,
    this.amount,
  });

  final String label;
  final int count;
  final double? amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            // سطر واحد دائمًا — كانت «مضاعفة / موقوفة» تنكسر فتختلف الارتفاعات
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            if (amount != null && amount! > 0) ...[
              const SizedBox(height: 2),
              Text(
                _money(amount!),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

