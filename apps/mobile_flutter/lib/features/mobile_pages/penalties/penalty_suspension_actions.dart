part of '../my_instant_penalties_page.dart';

Future<void> _liftEmployeeSuspensionAdmin(
  BuildContext context,
  WidgetRef ref,
  SuspendedEmployeeInfo emp,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(
            Icons.lock_open_rounded,
            color: AppColors.statusSuccess,
            size: 24,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'رفع الإيقاف عن العمل',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Text(
        'سيتم رفع الإيقاف عن الزميل ${emp.employeeName} وإعادة تفعيل حسابه فوراً، وإرجاع الغرامات لقيمتها الأصلية وإرسال إشعار فوري صوتي له.',
        style: const TextStyle(fontSize: 13.5, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: const Text('تأكيد رفع الإيقاف'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.statusSuccess,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>(
      'lift_employee_suspension_admin',
          params: {'p_employee_id': emp.employeeId},
    );
    ref
      ..invalidate(suspendedEmployeesProvider)
      ..invalidate(teamInstantPenaltiesProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'تم رفع الإيقاف عن الزميل ${emp.employeeName} بنجاح وإرسال الإشعار الفوري 🟢',
        ),
        backgroundColor: AppColors.statusSuccess,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر رفع الإيقاف: ${humanizeError(e)}')),
    );
  }
}

Future<void> _liftAllEmployeesSuspensionAdmin(
  BuildContext context,
  WidgetRef ref,
  int employeeCount,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(
            Icons.people_outline_rounded,
            color: AppColors.statusSuccess,
            size: 24,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'رفع إيقاف جميع الموظفين',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Text(
        'هل تريد رفع الإيقاف عن كافة الموظفين الموقوفين وعددهم $employeeCount موظفاً دفعة واحدة؟\n\nسيتم إعادة تفعيل كافة الحسابات فوراً، وإرجاع الغرامات لقيمتها الأصلية، وإرسال إشعارات صوتية فورية للجميع لمباشرة العمل.',
        style: const TextStyle(fontSize: 13.5, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.lock_open_rounded, size: 18),
          label: Text('رفع الإيقاف للجميع ($employeeCount)'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.statusSuccess,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(supabaseProvider)
        .rpc<dynamic>('lift_all_suspended_employees_admin');
    ref
      ..invalidate(suspendedEmployeesProvider)
      ..invalidate(teamInstantPenaltiesProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'تم رفع إيقاف جميع الموظفين ($employeeCount) وإعادة تفعيل حساباتهم بنجاح 🟢',
        ),
        backgroundColor: AppColors.statusSuccess,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر رفع الإيقاف الجماعي: ${humanizeError(e)}')),
    );
  }
}

Future<void> _liftSuspension(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) => _runPenaltyAction(
  context,
  ref,
  title: 'رفع إيقاف الحساب',
  message:
      'يُعاد فتح حساب ${item.employeeName ?? 'الموظف'}، وتعود الغرامة «بانتظار السداد».',
  confirmLabel: 'رفع الإيقاف',
  inputLabel: 'ملاحظة (اختياري)',
  inputRequired: false,
  success: 'تم رفع الإيقاف',
  action: (note) => ref
      .read(supabaseProvider)
      .rpc<dynamic>(
        'lift_instant_penalty_suspension',
        params: {
          'p_penalty_id': item.id,
          'p_notes': note.isEmpty ? null : note,
        },
      ),
);

Future<void> _reviewExcuse(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item, {
  required bool approve,
}) => _runPenaltyAction(
  context,
  ref,
  title: approve ? 'قبول العذر' : 'رفض العذر',
  message: approve
      ? 'قبول العذر يُلغي الغرامة ويُبلَّغ الموظف بالقرار.'
      : 'تبقى الغرامة مستحقة، ويُبلَّغ الموظف بسبب الرفض.',
  confirmLabel: approve ? 'قبول' : 'رفض',
  inputLabel: approve ? 'ملاحظة (اختياري)' : 'سبب الرفض (مطلوب)',
  inputRequired: !approve,
  destructive: !approve,
  success: approve ? 'تم قبول العذر وإلغاء الغرامة' : 'تم رفض العذر',
  action: (note) => ref
      .read(supabaseProvider)
      .rpc<dynamic>(
        'review_instant_penalty_excuse',
        params: {
          'p_penalty_id': item.id,
          'p_action': approve ? 'approved' : 'rejected',
          'p_notes': note.isEmpty ? null : note,
        },
      ),
);

/// صرف من صندوق الزمالة (الإدارة والمالية فقط — الخادم يتحقق ويرفض ما يتجاوز الرصيد).
Future<void> _showWithdrawSheet(
  BuildContext context,
  WidgetRef ref,
  double balance,
) async {
  final amountCtrl = TextEditingController();
  final reasonCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  const categories = [
    'مساعدة زميل',
    'رعاية صحية',
    'مناسبة اجتماعية',
    'حالة طارئة',
    'أخرى',
  ];
  var category = categories.first;
  var submitting = false;
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
        final valid =
            amount > 0 &&
            amount <= balance &&
            reasonCtrl.text.trim().length >= 3;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تسجيل صرف من صندوق الزمالة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'الرصيد المتاح: ${_money(balance)} — يُبلَّغ الفريق بالصرف وسببه للشفافية.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'المبلغ (ج.م)',
                  errorText: amount > balance
                      ? 'المبلغ أكبر من رصيد الصندوق'
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                decoration: InputDecoration(
                  labelText: 'البند',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => category = v ?? category),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'سبب الصرف (مطلوب)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: !valid || submitting
                    ? null
                    : () async {
                        setState(() => submitting = true);
                        try {
                          await ref
                              .read(supabaseProvider)
                              .rpc<dynamic>(
                                'withdraw_from_fellowship_fund',
                                params: {
                                  'p_amount': amount,
                                  'p_category': category,
                                  'p_reason': reasonCtrl.text.trim(),
                                  'p_beneficiary_employee_id': null,
                                  'p_notes': notesCtrl.text.trim().isEmpty
                                      ? null
                                      : notesCtrl.text.trim(),
                                },
                              );
                          ref
                            ..invalidate(fellowshipFundSummaryProvider)
                            ..invalidate(fellowshipFundTransactionsProvider);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم تسجيل صرف ${_money(amount)} من الصندوق',
                              ),
                            ),
                          );
                        } catch (e) {
                          setState(() => submitting = false);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('تعذر الصرف: ${humanizeError(e)}'),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.outbox_rounded, size: 18),
                label: Text(submitting ? 'جارٍ التسجيل…' : 'تسجيل الصرف'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// غرامات الموظفين — كل شخص باسمه
// ═══════════════════════════════════════════════════════════════════════════

