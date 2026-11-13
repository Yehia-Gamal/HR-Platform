import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/penalty_dispute_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// صفحة طعون الموظف على غرامات الحضور الفورية — تعرض الطعون وحالتها مع
/// إمكانية تقديم طعن جديد.
class PenaltyDisputesPage extends ConsumerWidget {
  const PenaltyDisputesPage({super.key});

  static final _dateFmt = DateFormat('d MMMM yyyy', 'ar');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputes = ref.watch(penaltyDisputesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('طعون الغرامات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewDisputeDialog(context, ref),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('تقديم طعن جديد'),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(penaltyDisputesProvider),
          child: disputes.when(
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
                    onPressed: () => ref.invalidate(penaltyDisputesProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ),
              ],
            ),
            data: (items) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
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
                      'لا توجد طعون مسجلة',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'لم تُقدّم أي طعن على غرامة حتى الآن.\nيمكنك تقديم طعن من الزر في الأسفل.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ] else ...[
                  const MobileSectionHeader(
                    title: 'سجل الطعون',
                    subtitle: 'جميع طعونك على غرامات الحضور الفورية.',
                  ),
                  const SizedBox(height: 10),
                  for (final item in items) ...[
                    _DisputeCard(item: item, dateFmt: _dateFmt),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقة طعن فردية.
class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.item, required this.dateFmt});
  final MobilePenaltyDispute item;
  final DateFormat dateFmt;

  Color _statusColor(BuildContext context) {
    switch (item.status) {
      case 'pending':
        return Colors.amber.shade700;
      case 'approved':
        return Colors.green.shade700;
      case 'rejected':
        return Colors.red.shade700;
      default:
        return Theme.of(context).colorScheme.onSurface;
    }
  }

  String _statusLabel() {
    switch (item.status) {
      case 'pending':
        return 'قيد المراجعة';
      case 'approved':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      default:
        return item.status;
    }
  }

  IconData _statusIcon() {
    switch (item.status) {
      case 'pending':
        return Icons.hourglass_top;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: statusColor, width: 4)),
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
                    dateFmt.format(item.createdAt),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
            Text(item.reason, style: const TextStyle(fontSize: 13)),
            if (item.reviewNotes != null && item.reviewNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: item.status == 'approved'
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: item.status == 'approved'
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      item.status == 'approved'
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      size: 16,
                      color: item.status == 'approved'
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'ملاحظات المراجعة: ${item.reviewNotes}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: item.status == 'approved'
                              ? Colors.green.shade800
                              : Colors.red.shade800,
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

/// حوار تقديم طعن جديد على غرامة.
///
/// كان يطلب من الموظف كتابة معرّف الغرامة (UUID) يدويًا — وهو غير معروف له
/// عمليًا فيمنع الميزة كلها. الآن يختار الغرامة من قائمة غراماته الفعلية،
/// مع تحقق من الطول قبل الإرسال وتنظيف المتحكمات بعد الإغلاق.
Future<void> _showNewDisputeDialog(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _NewDisputeSheet(),
  );
}

class _NewDisputeSheet extends ConsumerStatefulWidget {
  const _NewDisputeSheet();

  @override
  ConsumerState<_NewDisputeSheet> createState() => _NewDisputeSheetState();
}

class _NewDisputeSheetState extends ConsumerState<_NewDisputeSheet> {
  final _reason = TextEditingController();
  String? _penaltyId;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final penaltyId = _penaltyId;
    if (penaltyId == null) {
      setState(() => _error = 'اختر الغرامة التي تريد الطعن عليها أولًا.');
      return;
    }
    if (_reason.text.trim().length < 5) {
      setState(() => _error = 'اكتب سبب الطعن بوضوح (5 أحرف على الأقل).');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await submitPenaltyDispute(
        penaltyId: penaltyId,
        reason: _reason.text.trim(),
      );
      ref.invalidate(penaltyDisputesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تقديم الطعن بنجاح وهو قيد مراجعة الموارد البشرية'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'تعذر تقديم الطعن: ${humanizeError(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final penalties = ref.watch(myInstantPenaltiesProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.gavel_rounded,
                  color: Colors.deepPurple,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تقديم طعن على غرامة',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'اختر الغرامة من سجلّك ثم اكتب سبب الطعن. ستراجع الموارد البشرية '
              'الطعن وترد عليه، وتظهر النتيجة في هذه الصفحة.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'الغرامة المطلوب الطعن عليها',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            penalties.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  humanizeError(e),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Text(
                    'لا توجد غرامات مسجّلة على حسابك، فلا حاجة لتقديم طعن.',
                    style: TextStyle(color: muted, height: 1.5),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in items)
                      ChoiceChip(
                        selected: _penaltyId == p.id,
                        label: Text(
                          '${_disputeDate(p.workDate)} · '
                          '${fmtUnits(p.currentAmount)} ج.م',
                        ),
                        onSelected: _submitting
                            ? null
                            : (_) => setState(() {
                                _penaltyId = p.id;
                                _error = null;
                              }),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLines: 4,
              minLines: 3,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: 'سبب الطعن',
                hintText: 'اكتب سبب الطعن بالتفصيل...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _submitting ? 'جارٍ الإرسال...' : 'إرسال الطعن للمراجعة',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _disputeDate(String raw) {
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  return DateFormat('d MMMM y', 'ar').format(date);
}
