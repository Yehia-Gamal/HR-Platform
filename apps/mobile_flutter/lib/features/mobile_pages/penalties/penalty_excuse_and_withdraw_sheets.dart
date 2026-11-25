part of '../my_instant_penalties_page.dart';

Future<void> _showSubmitExcuseSheet(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var isSubmitting = false;
  final work = DateTime.tryParse(item.workDate);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تقديم عذر عن تأخير ${work == null ? item.workDate : DateFormat('d MMMM y', 'ar').format(work)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'اكتب سبب التأخير (${_minutes(item.lateMinutes)}). تراجع الموارد البشرية العذر وتُبلغك بالقرار.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'اكتب العذر بالتفصيل…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (val) => val == null || val.trim().length < 5
                    ? 'اكتب عذرًا واضحًا لا يقل عن 5 أحرف'
                    : null,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setState(() => isSubmitting = true);
                        try {
                          await Supabase.instance.client.rpc<dynamic>(
                            'submit_instant_penalty_excuse',
                            params: {
                              'p_penalty_id': item.id,
                              'p_reason': controller.text.trim(),
                            },
                          );
                          ref.invalidate(myInstantPenaltiesProvider);
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('أُرسل العذر للمراجعة'),
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() => isSubmitting = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تعذر إرسال العذر: ${humanizeError(e)}',
                                ),
                              ),
                            );
                          }
                        }
                      },
                icon: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  isSubmitting ? 'جارٍ الإرسال…' : 'إرسال العذر للمراجعة',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// إجراءات الإدارة على الغرامة (الخادم يتحقق من الصلاحية)
// ═══════════════════════════════════════════════════════════════════════════

/// يطلب ملاحظة/سببًا ثم ينفّذ الإجراء ويحدّث الشاشات.
Future<void> _runPenaltyAction(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String message,
  required String confirmLabel,
  required String inputLabel,
  required bool inputRequired,
  required String success,
  required Future<void> Function(String note) action,
  bool destructive = false,
}) async {
  // لا يُتلف بعد الإغلاق مباشرة — الحوار ما زال يرسمه أثناء حركة الخروج.
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: inputLabel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.statusDanger,
                  )
                : null,
            onPressed: inputRequired && controller.text.trim().length < 3
                ? null
                : () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final note = controller.text.trim();
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action(note);
    ref
      ..invalidate(teamInstantPenaltiesProvider)
      ..invalidate(myInstantPenaltiesProvider)
      ..invalidate(fellowshipFundSummaryProvider)
      ..invalidate(fellowshipFundTransactionsProvider)
      ..invalidate(suspendedEmployeesProvider);
    messenger.showSnackBar(SnackBar(content: Text(success)));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر التنفيذ: ${humanizeError(e)}')),
    );
  }
}

Future<void> _confirmPayment(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) => _runPenaltyAction(
  context,
  ref,
  title: 'تأكيد سداد الغرامة',
  message:
      'تأكيد استلام ${_money(item.currentAmount)} نقدًا من ${item.employeeName ?? 'الموظف'}، ويُودَع المبلغ في صندوق الزمالة.',
  confirmLabel: 'تأكيد السداد',
  inputLabel: 'ملاحظة (اختياري)',
  inputRequired: false,
  success: 'تم تأكيد السداد وإيداعه في صندوق الزمالة',
  action: (note) => ref
      .read(supabaseProvider)
      .rpc<dynamic>(
        'confirm_instant_penalty_payment',
        params: {
          'p_penalty_id': item.id,
          'p_notes': note.isEmpty ? null : note,
        },
      ),
);

Future<void> _cancelPenalty(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) => _runPenaltyAction(
  context,
  ref,
  title: 'إلغاء أو إعفاء الغرامة',
  message:
      'تُلغى غرامة ${item.employeeName ?? 'الموظف'} (${_money(item.currentAmount)}) ولا تُحصَّل، ويُسجَّل السبب في ملفها.',
  confirmLabel: 'إلغاء الغرامة',
  inputLabel: 'السبب (مطلوب)',
  inputRequired: true,
  destructive: true,
  success: 'تم إلغاء الغرامة',
  action: (note) => ref
      .read(supabaseProvider)
      .rpc<dynamic>(
        'cancel_instant_penalty',
        params: {'p_penalty_id': item.id, 'p_reason': note},
      ),
);

Future<void> _revertDoubledPenalty(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) => _runPenaltyAction(
  context,
  ref,
  title: 'إرجاع الغرامة للأصل بدون مضاعفة',
  message:
      'سيتم إرجاع غرامة  ليوم  من  إلى قيمتها الأصلية () بدون مضاعفة، وتعود الحالة «بانتظار السداد» لتمكينه من الدفع دون مشاكل.',
  confirmLabel: 'إرجاع للأصل',
  inputLabel: 'ملاحظة أو سبب إداري (اختياري)',
  inputRequired: false,
  success: 'تم إرجاع الغرامة إلى أصلها () بنجاح',
  action: (note) => ref
      .read(supabaseProvider)
      .rpc<dynamic>(
        'revert_doubled_instant_penalty',
        params: {
          'p_penalty_id': item.id,
          'p_reason': note.isEmpty ? null : note,
        },
      ),
);

