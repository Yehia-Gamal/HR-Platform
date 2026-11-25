part of '../my_instant_penalties_page.dart';

class _SuspendedEmployeeCard extends ConsumerWidget {
  const _SuspendedEmployeeCard({required this.emp});

  final SuspendedEmployeeInfo emp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.statusDanger.withValues(alpha: .3),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppAvatar(
                  name: emp.employeeName,
                  photoUrl: emp.photoUrl,
                  radius: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              emp.employeeName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const _Pill(
                            text: 'موقوف عن العمل',
                            color: AppColors.statusDanger,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${emp.departmentName ?? "—"}${emp.jobTitle != null ? " · ${emp.jobTitle}" : ""}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .35,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'المبلغ المطلوب حالياً (بالمضاعفة):',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        _money(emp.totalCurrentDue),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.statusDanger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'أصل الغرامات بدون مضاعفة:',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        _money(emp.totalOriginalDue),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.statusSuccess,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'عدد الغرامات غير المسددة:',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '${emp.unpaidCount}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (emp.penalties.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'الغرامات المترتبة على الإيقاف:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final pen in emp.penalties) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: .4,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: AppColors.statusWarning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'يوم ${pen["workDate"]} · تأخير ${_minutes((pen["lateMinutes"] as num?)?.toInt() ?? 0)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${_money((pen["originalAmount"] as num?)?.toDouble() ?? 0)} ← ${_money((pen["currentAmount"] as num?)?.toDouble() ?? 0)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.statusDanger,
                        ),
                      ),
                      // زر إرجاع هذه الغرامة الفردية لأصلها
                      if (((pen["currentAmount"] as num?)?.toDouble() ?? 0) >
                          ((pen["originalAmount"] as num?)?.toDouble() ?? 0))
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          icon: const Icon(
                            Icons.undo_rounded,
                            size: 15,
                            color: Color(0xFF4F46E5),
                          ),
                          tooltip:
                              'إرجاع هذه الغرامة لأصلها (${_money((pen["originalAmount"] as num?)?.toDouble() ?? 0)})',
                          onPressed: () => _runPenaltyAction(
                            context,
                            ref,
                            title: 'إرجاع الغرامة للأصل',
                            message:
                                'إرجاع غرامة يوم ${pen["workDate"]} إلى أصلها (${_money((pen["originalAmount"] as num?)?.toDouble() ?? 0)}) بدون مضاعفة لتمكين الموظف من السداد.',
                            confirmLabel: 'إرجاع للأصل',
                            inputLabel: 'ملاحظة (اختياري)',
                            inputRequired: false,
                            success: 'تم إرجاع الغرامة إلى أصلها بنجاح',
                            action: (note) => ref
                                .read(supabaseProvider)
                                .rpc<dynamic>(
                              'revert_doubled_instant_penalty',
                              params: {
                                'p_penalty_id': pen["id"],
                                'p_reason': note.isEmpty ? null : note,
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
            const Divider(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 1) سداد الغرامة ورفع الإيقاف
                if (emp.penalties.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () {
                      final firstPen = emp.penalties.first;
                      final penId = firstPen["id"] as String;
                      final currentAmt =
                          (firstPen["currentAmount"] as num?)?.toDouble() ?? 0;
                      _runPenaltyAction(
                        context,
                        ref,
                        title: 'سداد الغرامة ورفع الإيقاف',
                        message:
                            'تأكيد استلام ${_money(currentAmt)} نقداً من الزميل ${emp.employeeName} وإيداعها في صندوق الزمالة.\nسيتم رفع الإيقاف عن الزميل فوراً.',
                        confirmLabel: 'تأكيد السداد ورفع الإيقاف',
                        inputLabel: 'ملاحظة (اختياري)',
                        inputRequired: false,
                        success:
                            'تم السداد وإيداع المبلغ بالصندوق ورفع الإيقاف بنجاح',
                        action: (note) => ref
                            .read(supabaseProvider)
                            .rpc<dynamic>(
                          'confirm_instant_penalty_payment',
                          params: {
                            'p_penalty_id': penId,
                            'p_notes': note.isEmpty ? null : note,
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('سداد الغرامة ورفع الإيقاف'),
                  ),

                // 2) إرجاع كافة الغرامات للأصل
                if (emp.has500Penalty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      for (final pen in emp.penalties) {
                        final penAmt =
                            (pen["currentAmount"] as num?)?.toDouble() ?? 0;
                        final origAmt =
                            (pen["originalAmount"] as num?)?.toDouble() ?? 0;
                        if (penAmt > origAmt) {
                          await ref
                              .read(supabaseProvider)
                              .rpc<dynamic>(
                            'revert_doubled_instant_penalty',
                            params: {
                              'p_penalty_id': pen["id"],
                                  'p_reason':
                                      'إرجاع إداري جماعي للموظف الموقوف',
                            },
                          );
                        }
                      }
                      ref
                        ..invalidate(suspendedEmployeesProvider)
                        ..invalidate(teamInstantPenaltiesProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'تم إرجاع غرامات ${emp.employeeName} إلى قيمتها الأصلية (${_money(emp.totalOriginalDue)}) بنجاح.',
                            ),
                            backgroundColor: AppColors.statusSuccess,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: Text(
                      'إرجاع الغرامات للأصل (${_money(emp.totalOriginalDue)})',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4F46E5),
                    ),
                  ),

                // 3) رفع الإيقاف إدارياً
                OutlinedButton.icon(
                  onPressed: () =>
                      _liftEmployeeSuspensionAdmin(context, ref, emp),
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: const Text('رفع الإيقاف إدارياً'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.statusSuccess,
                  ),
                ),

                // 4) واتساب
                if (emp.phone != null && emp.phone!.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final text =
                          '*إشعار هام وعاجل من إدارة الموارد البشرية (جمعية أحلى شباب)* ⚠️\n\n'
                          'السلام عليكم ورحمة الله، أستاذ *${emp.employeeName}* 🌸\n\n'
                          'نود إحاطتكم بأنه قد تم *تعليق حسابكم مؤقتاً على السيستم* لتجاوز مهلة سداد غرامات الحضور والانصراف.\n\n'
                          '📌 *إجمالي المبلغ المطلوب لسداد الغرامات ورفع الإيقاف:* *${_money(emp.totalCurrentDue)}* (أصل الغرامات: *${_money(emp.totalOriginalDue)}*).\n\n'
                          'يرجى سرعة التوجه للـ HR أو التواصل مع الإدارة للسداد ورفع الإيقاف لمباشرة العمل.\n\n'
                          'مع خالص التقدير والاحترام 🌺';
                      final uri = Uri.parse(
                        'https://wa.me/${emp.phone}?text=${Uri.encodeComponent(text)}',
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('واتساب'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// صندوق الزمالة
// ═══════════════════════════════════════════════════════════════════════════

