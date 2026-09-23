import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
              const _FellowshipFundNoticeCard(),
              const SizedBox(height: 8),
              _ComplianceHonorCard(items: items),
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

/// بطاقة توضيح صندوق الزمالة والتكافل واستقلال الغرامات عن الراتب الشهري.
class _FellowshipFundNoticeCard extends StatelessWidget {
  const _FellowshipFundNoticeCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Colors.teal.shade200.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      color: Colors.teal.shade50.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.volunteer_activism_outlined,
                size: 20,
                color: Colors.teal.shade800,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'صندوق الزمالة والتكافل الاجتماعي',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.teal.shade900,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade700,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '100% للزملاء',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'تنبيه هام: غرامات التأخير الفورية لا ترتبط بالراتب الشهري ولا تُخصم منه إطلاقاً.\n'
                    'جميع مبالغ الغرامات تودع بالكامل في صندوق الزمالة لدعم الزملاء في الحالات الطارئة، الرعاية الصحية، والمناسبات الاجتماعية.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.45,
                      color: Colors.teal.shade900.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة وسام الانضباط أو التكافل الإيجابي للموظف
class _ComplianceHonorCard extends StatelessWidget {
  const _ComplianceHonorCard({required this.items});
  final List<MobileInstantPenalty> items;

  @override
  Widget build(BuildContext context) {
    final pending = items.where((p) => p.status == 'pending_payment').toList();
    final doubled = items.where((p) => p.status == 'doubled').toList();
    final suspended = items.where((p) => p.status == 'suspended').toList();
    final paid = items.where((p) => p.status == 'paid').toList();

    final hasUnpaid = pending.isNotEmpty || doubled.isNotEmpty || suspended.isNotEmpty;

    if (items.isEmpty) {
      // سجل ناصع بدون أي غرامات
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.amber.shade300.withValues(alpha: 0.7),
            width: 1.2,
          ),
        ),
        color: Colors.amber.shade50.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.military_tech,
                  size: 24,
                  color: Colors.amber.shade800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'وسام الانضباط الشرفي 🌟',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade700,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '100% التزام',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'سجلك نظيف ومثالي تماماً بدون أي تأخيرات أو غرامات! حضورك اليومي في تمام العاشرة صباحاً قدوة مشرفة لفريقك.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: Colors.amber.shade900.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!hasUnpaid && paid.isNotEmpty) {
      // سدد كل الغرامات — مساهمة تكافلية
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.green.shade300.withValues(alpha: 0.7),
            width: 1.2,
          ),
        ),
        color: Colors.green.shade50.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.verified,
                  size: 22,
                  color: Colors.green.shade800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'التزام تام بالسداد والتكافل 🤝',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: Colors.green.shade900,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade700,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'مسدد بالكامل',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تم سداد جميع الغرامات السابقة وإيداعها بالكامل في صندوق الزمالة لدعم الزملاء. حسابك نشط وسليم تماماً.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: Colors.green.shade900.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // هناك مبالغ معلقة — بطاقة تذكير مع زر واتساب مباشر للاستفسار أو إرسال إيصال السداد
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Colors.orange.shade300.withValues(alpha: 0.7),
          width: 1.2,
        ),
      ),
      color: Colors.orange.shade50.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.access_time_filled,
                    size: 22,
                    color: Colors.orange.shade800,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سارع بالسداد لتفادي التعليق أو المضاعفة',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'سداد الغرامة خلال 24 ساعة يضمن استمرار فتح حسابك، والمبلغ يذهب كاملاً لصندوق الزمالة لدعم زملائك.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: Colors.orange.shade900.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  const text = 'السلام عليكم، أود الاستفسار بخصوص سداد غرامة الحضور لصندوق الزمالة والتكافل.';
                  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.green),
                label: const Text(
                  'استفسار أو إرسال إيصال السداد عبر واتساب',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.green.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة غرامة فردية.
class _PenaltyCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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

            // عداد تنازلي لموعد المضاعفة لـ 500 ج.م
            if (item.status == 'pending_payment') ...[
              Builder(
                builder: (context) {
                  final deadline = item.createdAt.add(const Duration(hours: 24));
                  final remaining = deadline.difference(DateTime.now());
                  if (remaining.inMinutes > 0) {
                    final hours = remaining.inHours;
                    final mins = remaining.inMinutes % 60;
                    return Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 16, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'متبقي $hours ساعة و$mins دقيقة قبل مضاعفة الغرامة إلى 500 ج.م',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],

            // حالة العذر إن وُجد
            if (item.excuseStatus == 'submitted') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.hourglass_top, size: 14, color: Colors.purple.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'عذر قيد المراجعة لدى الموارد البشرية ⏳',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.purple.shade800,
                          ),
                        ),
                      ],
                    ),
                    if (item.excuseText != null && item.excuseText!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.excuseText!,
                        style: TextStyle(fontSize: 11, color: Colors.purple.shade900),
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (item.excuseStatus == 'approved') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'تم قبول عذرك وإلغاء الغرامة بنجاح ✓${item.excuseNotes != null && item.excuseNotes!.isNotEmpty ? "\nملاحظات HR: ${item.excuseNotes}" : ""}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (item.excuseStatus == 'rejected') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'تم رفض العذر من قِبل الموارد البشرية ✗${item.excuseNotes != null && item.excuseNotes!.isNotEmpty ? "\nالسبب: ${item.excuseNotes}" : ""}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // حالة إيصال الدفع الإلكتروني إن وُجد
            if (item.receiptReferenceNumber != null || item.receiptAttachmentUrl != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, size: 16, color: Colors.teal),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'تم تسجيل إيصال تحويل (${item.paymentMethod}) — بانتظار تأكيد الإدارة المالية${item.receiptReferenceNumber != null ? "\nرقم مرجعي: #${item.receiptReferenceNumber}" : ""}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.teal.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

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

            // أزرار الإجراءات للموظف (تقديم عذر / سداد إلكتروني)
            if (item.status == 'pending_payment' || item.status == 'doubled') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (item.excuseStatus == 'none' || item.excuseStatus == 'rejected')
                    OutlinedButton.icon(
                      onPressed: () => _showSubmitExcuseSheet(context, ref, item),
                      icon: const Icon(Icons.edit_note, size: 16),
                      label: const Text('تقديم عذر', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () => _showSubmitReceiptSheet(context, ref, item, currencyFmt),
                    icon: const Icon(Icons.account_balance_wallet, size: 16),
                    label: const Text('سداد إلكتروني (InstaPay)', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _showSubmitExcuseSheet(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isSubmitting = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.amber, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'تقديم عذر عن تأخير ${item.workDate}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'اكتب تفاصيل الظرف أو العذر الذي أدى لتأخيرك (${item.lateMinutes} دقيقة). ستقوم إدارة الموارد البشرية بمراجعة العذر فوراً.',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'اكتب نص العذر هنا بالتفصيل...',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 5) {
                    return 'يرجى كتابة عذر واضح لا يقل عن 5 أحرف';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setState(() => isSubmitting = true);
                        try {
                          final client = Supabase.instance.client;
                          await client.rpc('submit_instant_penalty_excuse', params: {
                            'p_penalty_id': item.id,
                            'p_reason': controller.text.trim(),
                          });
                          ref.invalidate(myInstantPenaltiesProvider);
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تقديم العذر بنجاح وهو قيد مراجعة الموارد البشرية'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() => isSubmitting = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('تعذر تقديم العذر: ${humanizeError(e)}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                icon: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 18),
                label: Text(isSubmitting ? 'جارٍ الإرسال...' : 'إرسال العذر للمراجعة'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _showSubmitReceiptSheet(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
  NumberFormat currencyFmt,
) async {
  final refController = TextEditingController();
  final urlController = TextEditingController();
  String selectedMethod = 'instapay';
  bool isSubmitting = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.teal, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'سداد إلكتروني (إنستاباي / محفظة)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المبلغ المطلوب: ${currencyFmt.format(item.currentAmount)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.teal.shade900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'يتم تحويل المبلغ لصالح صندوق الزمالة والتكافل عبر إنستاباي أو فودافون كاش، ثم تسجيل الرقم المرجعي للتحويل أدناه.',
                    style: TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedMethod,
              decoration: InputDecoration(
                labelText: 'طريقة التحويل',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(value: 'instapay', child: Text('إنستاباي (InstaPay)')),
                DropdownMenuItem(value: 'vodafone_cash', child: Text('فودافون كاش')),
                DropdownMenuItem(value: 'wallet', child: Text('محفظة إلكترونية أخرى')),
                DropdownMenuItem(value: 'bank_transfer', child: Text('تحويل بنكي')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => selectedMethod = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: refController,
              decoration: InputDecoration(
                labelText: 'الرقم المرجعي للتحويل (Reference Number)',
                hintText: 'مثال: 1234567890',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: 'رابط صورة الإيصال (اختياري)',
                hintText: 'https://...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final refNo = refController.text.trim();
                      final url = urlController.text.trim();
                      if (refNo.isEmpty && url.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('يرجى إدخال الرقم المرجعي للتحويل أو رابط صورة الإيصال'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      setState(() => isSubmitting = true);
                      try {
                        final client = Supabase.instance.client;
                        await client.rpc('submit_instant_penalty_receipt', params: {
                          'p_penalty_id': item.id,
                          'p_payment_method': selectedMethod,
                          'p_reference_number': refNo.isNotEmpty ? refNo : null,
                          'p_receipt_url': url.isNotEmpty ? url : null,
                        });
                        ref.invalidate(myInstantPenaltiesProvider);
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم إرسال بيانات الإيصال بنجاح وسيتم التحقق منها وتأكيد السداد'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() => isSubmitting = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('تعذر إرسال الإيصال: ${humanizeError(e)}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle, size: 18),
              label: Text(isSubmitting ? 'جارٍ الإرسال...' : 'تأكيد إرسال الإيصال'),
            ),
          ],
        ),
      ),
    ),
  );
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
