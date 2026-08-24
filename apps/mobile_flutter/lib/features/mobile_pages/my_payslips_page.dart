import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// صفحة «قسائمي» — قسائم الرواتب المعتمدة والصادرة والمدفوعة (0036).
/// كل قسيمة بطاقة قابلة للتوسيع تعرض بنود المكافآت والخصومات.
class MyPayslipsPage extends ConsumerWidget {
  const MyPayslipsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payslips = ref.watch(myPayslipsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('قسائم الرواتب')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myPayslipsProvider),
        child: payslips.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 120),
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () => ref.invalidate(myPayslipsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (items) => items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 160),
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 54,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        'لا توجد قسائم رواتب بعد',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        'ستظهر القسائم هنا بعد اعتمادها من المالية.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _PayslipCard(item: items[index]),
                ),
        ),
      ),
    );
  }
}

class _PayslipCard extends StatelessWidget {
  const _PayslipCard({required this.item});
  final MobilePayslip item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final monthLabel = DateFormat('MMMM y', 'ar').format(item.periodMonth);
    final currency = item.currency;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            monthLabel,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                MobileStatusPill(item.status),
                const SizedBox(width: 8),
                Text(
                  'صافي: ${item.netAmount.toStringAsFixed(0)} $currency',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.statusSuccess,
                  ),
                ),
              ],
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _AmountBox(
                      label: 'الإجمالي',
                      value: item.grossAmount,
                      currency: currency,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AmountBox(
                      label: 'الخصومات',
                      value: item.deductionAmount,
                      currency: currency,
                      color: AppColors.statusDanger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AmountBox(
                      label: 'الصافي',
                      value: item.netAmount,
                      currency: currency,
                      color: AppColors.statusSuccess,
                    ),
                  ),
                ],
              ),
            ),
            if (item.issuedAt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_available_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'تاريخ الإصدار: ${DateFormat('d MMMM y', 'ar').format(item.issuedAt!.toLocal())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            if (item.lines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'لا توجد بنود تفصيلية.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              ...item.lines.map(
                (line) => ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 0,
                  ),
                  title: Text(line.name, style: const TextStyle(fontSize: 13)),
                  trailing: Text(
                    '${line.lineType == 'deduction' ? '-' : ''}'
                    '${line.amount.toStringAsFixed(0)} $currency',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: line.lineType == 'deduction'
                          ? AppColors.statusDanger
                          : AppColors.statusSuccess,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _AmountBox extends StatelessWidget {
  const _AmountBox({
    required this.label,
    required this.value,
    required this.currency,
    required this.color,
  });

  final String label;
  final double value;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${value.toStringAsFixed(0)}\n$currency',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
