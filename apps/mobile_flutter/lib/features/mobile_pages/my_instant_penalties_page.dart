import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// صفحة غرامات الحضور الفورية للموظف — تعرض غراماته وحالتها.
class MyInstantPenaltiesPage extends ConsumerWidget {
  const MyInstantPenaltiesPage({this.highlightId, super.key});

  /// معرّف الغرامة القادمة من إشعار — تُبرز بطاقتها عند الفتح.
  final String? highlightId;

  static final _dateFmt = DateFormat('d MMMM yyyy', 'ar');
  static final _currencyFmt = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final penalties = ref.watch(myInstantPenaltiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('غرامات الحضور الفورية')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myInstantPenaltiesProvider),
        child: penalties.when(
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
                  onPressed: () => ref.invalidate(myInstantPenaltiesProvider),
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
              _SummaryCard(items: items),
              const SizedBox(height: 8),
              if (items.isEmpty) ...[
                const SizedBox(height: 48),
                Icon(
                  Icons.check_circle_outline,
                  size: 54,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'لا توجد غرامات فورية',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'ممتاز! لم تُسجَّل أي غرامات تأخير على حسابك.\nاستمر في الحضور في الوقت المحدد (10:00 ص).',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ] else ...[
                const MobileSectionHeader(
                  title: 'سجل الغرامات',
                  subtitle: 'جميع غرامات الحضور المسجلة على حسابك.',
                ),
                const SizedBox(height: 10),
                for (final item in items) ...[
                  _PenaltyCard(
                    item: item,
                    currencyFmt: _currencyFmt,
                    dateFmt: _dateFmt,
                    highlighted: highlightId != null && item.id == highlightId,
                  ),
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

/// بطاقة ملخص الغرامات في الأعلى.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.items});
  final List<MobileInstantPenalty> items;

  static final _currencyFmt = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final pending = items.where((p) => p.status == 'pending_payment').toList();
    final doubled = items.where((p) => p.status == 'doubled').toList();
    final suspended = items.where((p) => p.status == 'suspended').toList();
    final paid = items.where((p) => p.status == 'paid').toList();

    final pendingAmount =
        pending.fold<double>(0, (s, p) => s + p.currentAmount);
    final doubledAmount =
        doubled.fold<double>(0, (s, p) => s + p.currentAmount);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.gavel,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'ملخص الغرامات الفورية',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'الحضور يبدأ 10:00 ص — أول 15 دقيقة سماح. '
              'بعد ذلك: 20 ج.م (حتى 10:30) | 50 ج.م (حتى 11:00) | 150 ج.م (حتى 12:00).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _StatChip(
                  label: 'بانتظار الدفع',
                  count: pending.length,
                  amount: pendingAmount > 0
                      ? _currencyFmt.format(pendingAmount)
                      : null,
                  color: Colors.amber,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'مضاعفة / معلّقة',
                  count: doubled.length + suspended.length,
                  amount: doubledAmount > 0
                      ? _currencyFmt.format(doubledAmount)
                      : null,
                  color: Colors.red,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'مدفوعة',
                  count: paid.length,
                  color: Colors.green,
                ),
              ],
            ),
            if (suspended.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.block, size: 18, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'حسابك معلّق — يجب التوجه للـ HR وسداد الغرامة المضاعفة (500 ج.م) لإعادة فتح حسابك.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.count,
    this.amount,
    required this.color,
  });
  final String label;
  final int count;
  final String? amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
            if (amount != null) ...[
              const SizedBox(height: 2),
              Text(
                amount!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
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

/// بطاقة غرامة فردية.
class _PenaltyCard extends StatelessWidget {
  const _PenaltyCard({
    required this.item,
    required this.currencyFmt,
    required this.dateFmt,
    this.highlighted = false,
  });
  final MobileInstantPenalty item;
  final NumberFormat currencyFmt;
  final DateFormat dateFmt;
  final bool highlighted;

  bool get _isExempt {
    if (item.status != 'cancelled') return false;
    final n = item.notes ?? '';
    return n.contains('إلغاء بأثر رجعي') ||
        n.contains('إلغاء تلقائي') ||
        n.contains('مأمورية') ||
        n.contains('إجازة') ||
        n.contains('قافلة') ||
        n.contains('فاندي') ||
        n.contains('المدير التنفيذي') ||
        n.contains('استثناء') ||
        n.contains('معفى');
  }

  Color _statusColor(BuildContext context) {
    if (_isExempt) return Colors.teal.shade700;
    switch (item.status) {
      case 'pending_payment':
        return Colors.amber.shade700;
      case 'paid':
        return Colors.green.shade700;
      case 'doubled':
        return Colors.orange.shade700;
      case 'suspended':
        return Colors.red.shade700;
      case 'cancelled':
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.onSurface;
    }
  }

  String _statusLabel() {
    if (_isExempt) return 'معفى (ملغاة)';
    switch (item.status) {
      case 'pending_payment':
        return 'بانتظار الدفع';
      case 'paid':
        return 'مدفوعة';
      case 'doubled':
        return 'مضاعفة';
      case 'suspended':
        return 'معلّق';
      case 'cancelled':
        return 'ملغاة';
      default:
        return item.status;
    }
  }

  IconData _statusIcon() {
    if (_isExempt) return Icons.verified_outlined;
    switch (item.status) {
      case 'pending_payment':
        return Icons.access_time;
      case 'paid':
        return Icons.check_circle;
      case 'doubled':
        return Icons.shield;
      case 'suspended':
        return Icons.block;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context);
    final workDateStr =
        item.workDate.isNotEmpty ? DateTime.tryParse(item.workDate) : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: highlighted
          ? RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: highlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .07)
              : null,
          border: Border(
            right: BorderSide(color: statusColor, width: 4),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(), size: 20, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    workDateStr != null
                        ? dateFmt.format(workDateStr)
                        : item.workDate,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _InfoChip(
                  icon: item.lateMinutes >= 240
                      ? Icons.person_off_outlined
                      : Icons.timer,
                  label: item.lateMinutes >= 240
                      ? 'لم يسجل بصمة'
                      : '${item.lateMinutes} دقيقة تأخير',
                  color: item.lateMinutes >= 240
                      ? Colors.red.shade700
                      : null,
                ),
                const SizedBox(width: 8),
                _InfoChip(
                  icon: Icons.attach_money,
                  label: 'غرامة: ${currencyFmt.format(item.originalAmount)}',
                ),
                if (item.currentAmount != item.originalAmount) ...[
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.trending_up,
                    label:
                        'الحالي: ${currencyFmt.format(item.currentAmount)}',
                    color: statusColor,
                  ),
                ],
              ],
            ),
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'ملاحظات: ${item.notes}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (item.status == 'suspended') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.block, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'حسابك مغلق — يجب سداد الغرامة المضاعفة (500 ج.م) من HR.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c,
          ),
        ),
      ],
    );
  }
}
