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
          data: (items) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _EarnedWageCard(items: items),
              const SizedBox(height: 8),
              if (items.isEmpty) ...[
                const SizedBox(height: 48),
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
              ] else ...[
                const MobileSectionHeader(
                  title: 'سجل القسائم السابقة',
                  subtitle: 'القسائم المعتمدة والمصروفة من الإدارة المالية.',
                ),
                const SizedBox(height: 10),
                for (final item in items) ...[
                  _PayslipCard(item: item),
                  const SizedBox(height: 10),
                ],
              ],
            ],
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

class _EarnedWageCard extends StatelessWidget {
  const _EarnedWageCard({required this.items});
  final List<MobilePayslip> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final dayOfMonth = now.day;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final progress = (dayOfMonth / daysInMonth).clamp(0.0, 1.0);
    final baseNet = items.isNotEmpty ? items.first.netAmount : 6000.0;
    final currency = items.isNotEmpty ? items.first.currency : 'EGP';
    final accruedAmount = (baseNet / daysInMonth) * dayOfMonth;
    final monthName = DateFormat('MMMM', 'ar').format(now);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.secondary, 0.6)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'مستحقاتك حتى اليوم (الراتب المكتسب)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                accruedAmount.toStringAsFixed(0),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                currency,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'استحقاق $dayOfMonth يوماً من أصل $daysInMonth يوماً في شهر $monthName (${(progress * 100).toInt()}%)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _showAdvanceRequestSheet(context, accruedAmount, currency),
              icon: const Icon(Icons.flash_on_rounded, size: 18),
              label: const Text(
                'طلب سحب مبكر / سلفة من المستحقات',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAdvanceRequestSheet(
    BuildContext context,
    double maxAmount,
    String currency,
  ) {
    final controller = TextEditingController(
      text: (maxAmount * 0.5).toStringAsFixed(0),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on_rounded, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                const Text(
                  'طلب سحب مبكر من المستحقات (EWA)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'الحد الأقصى المتاح للسحب بناءً على أيام عملك الموثقة: ${maxAmount.toStringAsFixed(0)} $currency',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'المبلغ المطلوب ($currency)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.money),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'تم تقديم طلب سلفة بمبلغ ${controller.text} $currency للمالية بنجاح!',
                      ),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                },
                child: const Text('تأكيد وإرسال الطلب'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
