part of '../mobile_attendance_page.dart';

Future<void> showWorkShiftSelectionSheet(BuildContext context, WidgetRef ref) async {
  final shiftInfo = ref.read(myWorkShiftInfoProvider).asData?.value;
  final available = shiftInfo?.availableShifts ?? [];
  final current = shiftInfo?.currentShift;
  final pending = shiftInfo?.pendingRequest;

  String? selectedShiftId = current?.id;
  final reasonController = TextEditingController();
  bool submitting = false;

  final quickReasons = const [
    '🚌 مواعيد المواصلات',
    '👨‍👩‍👧 ظروف أسرية وعائلية',
    '👥 تنسيق مع جدول الفريق',
    '📚 التزامات دراسية/شخصية',
    '⚡ ذروة الإنتاجية اليومية',
  ];

  await showModalBottomSheet<void>(
    context: context,
      useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final scheme = Theme.of(ctx).colorScheme;
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
        final selectedShift = available.cast<MobileWorkShift?>().firstWhere(
              (s) => s?.id == selectedShiftId,
              orElse: () => null,
            );

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, viewInsets + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.schedule_rounded, color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'اختيار وتغيير فترة العمل',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'اختر الفترة الأنسب لجدولك اليومي — يتم الاعتماد والتطبيق فوراً',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                if (pending != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.statusWarning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.statusWarning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: AppColors.statusWarning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لديك طلب قيد المراجعة حالياً (${pending.requestedShiftName ?? 'تغيير الوردية'}). إرسال طلب جديد سيحدّث بيانات طلبك.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // الورديات المتاحة
                if (available.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ...available.map((shift) {
                    final isSelected = selectedShiftId == shift.id;
                    final isCurrent = current?.id == shift.id;
                    final shiftIcon = _getShiftIcon(shift.code);
                    final shiftColor = _getShiftColor(shift.code, scheme);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () {
                          setModalState(() => selectedShiftId = shift.id);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? shiftColor.withValues(alpha: 0.08)
                                : scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? shiftColor
                                  : scheme.outlineVariant.withValues(alpha: 0.3),
                              width: isSelected ? 1.8 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: shiftColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(shiftIcon, color: shiftColor, size: 20),
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
                                            shift.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                              color: isSelected
                                                  ? shiftColor
                                                  : scheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        if (isCurrent) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.statusSuccess.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'فترتك الحالية',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.statusSuccess,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        _ShiftMiniChip(
                                          label: 'الحضور: ${shift.formattedStartTime}',
                                          color: scheme.primary,
                                        ),
                                        _ShiftMiniChip(
                                          label: 'سماح: ${shift.graceInMinutes} د',
                                          color: AppColors.statusWarning,
                                        ),
                                        _ShiftMiniChip(
                                          label: 'الانصراف: ${shift.formattedEndTime}',
                                          color: scheme.secondary,
                                        ),
                                      ],
                                    ),
                                    if (shift.description != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        shift.description!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // مؤشر اختيار دائري راقٍ
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? shiftColor : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? shiftColor
                                        : scheme.outlineVariant,
                                    width: isSelected ? 0 : 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                // ملخص الانتقال عند اختيار وردية مختلفة
                if (selectedShiftId != null &&
                    selectedShiftId != current?.id &&
                    selectedShift != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.swap_horiz_rounded, size: 16, color: scheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'ملخص التغيير المطلوب:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'الوردية الحالية:\n${current?.formattedRange ?? ''}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Icon(Icons.arrow_back_rounded, size: 16, color: scheme.primary),
                            Expanded(
                              child: Text(
                                'الوردية الجديدة:\n${selectedShift.formattedRange}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'تنويه: عند اعتماد الطلب، سيتم احتساب وقت الحضور والتأخير بناءً على مواعيد الوردية الجديدة فوراً.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // رقائق أسباب سريعة (Quick Justification Chips)
                const SizedBox(height: 4),
                Text(
                  'أسباب شائعة للاختيار السريع:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: quickReasons.map((qr) {
                    return InkWell(
                      onTap: () {
                        setModalState(() {
                          final clean = qr.replaceAll(RegExp(r'[^\u0621-\u064A\s]'), '').trim();
                          if (reasonController.text.trim().isEmpty) {
                            reasonController.text = clean;
                          } else if (!reasonController.text.contains(clean)) {
                            reasonController.text = '${reasonController.text.trim()} - $clean';
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          qr,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 10),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'سبب طلب التغيير (اختياري)',
                    hintText: 'اكتب مبررات تغيير فترة العمل لمساعدة الإدارة في سرعة الاعتماد...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: submitting || selectedShiftId == null || selectedShiftId == current?.id
                      ? null
                      : () async {
                          setModalState(() => submitting = true);
                          try {
                            await ref.read(mobileCommandsProvider).adoptMyWorkShift(
                                  shiftId: selectedShiftId!,
                                );
                            ref.invalidate(myWorkShiftInfoProvider);
                            ref.invalidate(attendanceStateProvider);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم اعتماد وتثبيت فترة العمل الجديدة فورياً بنجاح ✓'),
                                  backgroundColor: AppColors.statusSuccess,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() => submitting = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(humanizeError(e)),
                                  backgroundColor: AppColors.statusDanger,
                                ),
                              );
                            }
                          }
                        },
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(
                    submitting
                        ? 'جارٍ تثبيت الوردية...'
                        : (selectedShiftId == current?.id
                            ? 'هذه هي فترتك الحالية بالفعل'
                            : 'اعتماد وتثبيت الوردية فوراً'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

