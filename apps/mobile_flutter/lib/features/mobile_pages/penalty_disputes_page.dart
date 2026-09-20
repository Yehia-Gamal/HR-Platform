import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
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
      body: RefreshIndicator(
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
                    dateFmt.format(item.createdAt),
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
            Text(
              item.reason,
              style: const TextStyle(fontSize: 13),
            ),
            if (item.reviewNotes != null &&
                item.reviewNotes!.isNotEmpty) ...[
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

/// عرض حوار تقديم طعن جديد على غرامة.
Future<void> _showNewDisputeDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final penaltyIdController = TextEditingController();
  final reasonController = TextEditingController();
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
                  const Icon(Icons.gavel, color: Colors.deepPurple, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'تقديم طعن على غرامة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'أدخل معرّف الغرامة وسبب الطعن. ستقوم إدارة الموارد البشرية '
                'بمراجعة الطعن والرد عليه.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: penaltyIdController,
                decoration: InputDecoration(
                  labelText: 'معرّف الغرامة',
                  hintText: 'مثال: uuid-of-penalty',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'يرجى إدخال معرّف الغرامة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'سبب الطعن',
                  hintText: 'اكتب سبب الطعن بالتفصيل...',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 5) {
                    return 'يرجى كتابة سبب الطعن لا يقل عن 5 أحرف';
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
                          await submitPenaltyDispute(
                            penaltyId: penaltyIdController.text.trim(),
                            reason: reasonController.text.trim(),
                          );
                          ref.invalidate(penaltyDisputesProvider);
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تم تقديم الطعن بنجاح وهو قيد مراجعة الموارد البشرية',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() => isSubmitting = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('تعذر تقديم الطعن: ${humanizeError(e)}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                icon: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 18),
                label: Text(
                  isSubmitting ? 'جارٍ الإرسال...' : 'إرسال الطعن للمراجعة',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
