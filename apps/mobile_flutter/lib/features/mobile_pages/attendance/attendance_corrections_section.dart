part of '../mobile_attendance_page.dart';

class _CorrectionsSection extends ConsumerStatefulWidget {
  const _CorrectionsSection();

  @override
  ConsumerState<_CorrectionsSection> createState() => _CorrectionsSectionState();
}

class _CorrectionsSectionState extends ConsumerState<_CorrectionsSection> {
  int _filterIndex = 0; // 0: الكل, 1: قيد المراجعة, 2: معتمدة, 3: مرفوضة

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(myAttendanceServicesProvider);
    final corrections = services.asData?.value.corrections ?? [];
    final scheme = Theme.of(context).colorScheme;

    final pendingList = corrections.where((c) => c.status == 'pending').toList();
    final approvedList = corrections.where((c) => c.status == 'approved').toList();
    final rejectedList = corrections.where((c) => c.status == 'rejected').toList();

    final filteredList = switch (_filterIndex) {
      1 => pendingList,
      2 => approvedList,
      3 => rejectedList,
      _ => corrections,
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.fact_check_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تصحيحات وبلاغات الحضور',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        corrections.isEmpty
                            ? 'معالجة نسيان البصمة وأخطاء التسجيل'
                            : '${corrections.length} ${corrections.length == 1 ? 'طلب مسجل' : corrections.length == 2 ? 'طلبين مسجلين' : 'طلبات مسجلة'}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'طلب تصحيح',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  onPressed: () => showAttendanceCorrectionSheet(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── شريط الاختصارات السريعة لنسيان البصمة ──
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _QuickCorrectionActionChip(
                  icon: Icons.login_rounded,
                  label: 'نسيت حضور اليوم؟',
                  color: const Color(0xFF2563EB),
                  onTap: () => showAttendanceCorrectionSheet(
                    context,
                    ref,
                    initialWorkDate: DateTime.now(),
                    initialType: 'missing_check_in',
                  ),
                ),
                _QuickCorrectionActionChip(
                  icon: Icons.logout_rounded,
                  label: 'نسيت انصراف اليوم؟',
                  color: const Color(0xFF059669),
                  onTap: () => showAttendanceCorrectionSheet(
                    context,
                    ref,
                    initialWorkDate: DateTime.now(),
                    initialType: 'missing_check_out',
                  ),
                ),
                _QuickCorrectionActionChip(
                  icon: Icons.history_toggle_off_rounded,
                  label: 'نسيت انصراف الأمس؟',
                  color: const Color(0xFFD97706),
                  onTap: () => showAttendanceCorrectionSheet(
                    context,
                    ref,
                    initialWorkDate: DateTime.now().subtract(const Duration(days: 1)),
                    initialType: 'missing_check_out',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 10),

            // ── تبويبات التصفية التفاعلية ──
            if (corrections.isNotEmpty) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterTabChip(
                      label: 'الكل',
                      count: corrections.length,
                      isSelected: _filterIndex == 0,
                      onTap: () => setState(() => _filterIndex = 0),
                    ),
                    const SizedBox(width: 6),
                    _FilterTabChip(
                      label: 'قيد المراجعة',
                      count: pendingList.length,
                      color: AppColors.statusWarning,
                      isSelected: _filterIndex == 1,
                      onTap: () => setState(() => _filterIndex = 1),
                    ),
                    const SizedBox(width: 6),
                    _FilterTabChip(
                      label: 'معتمدة',
                      count: approvedList.length,
                      color: AppColors.statusSuccess,
                      isSelected: _filterIndex == 2,
                      onTap: () => setState(() => _filterIndex = 2),
                    ),
                    const SizedBox(width: 6),
                    _FilterTabChip(
                      label: 'مرفوضة',
                      count: rejectedList.length,
                      color: AppColors.statusDanger,
                      isSelected: _filterIndex == 3,
                      onTap: () => setState(() => _filterIndex = 3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            if (services.isLoading && !services.hasValue)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (corrections.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 20,
                      color: AppColors.statusSuccess.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'لا توجد طلبات تصحيح مسجلة حالياً — يمكنك تقديم بلاغ تصحيح فوري عند نسيان الحضور أو الانصراف.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (filteredList.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    switch (_filterIndex) {
                      1 => 'لا توجد طلبات قيد المراجعة حالياً ✓',
                      2 => 'لا توجد طلبات معتمدة في هذا القسم',
                      3 => 'سجلك نظيف — لا توجد أي طلبات تصحيح مرفوضة ✓',
                      _ => 'لا توجد طلبات تطابق هذا التبويب',
                    },
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else ...[
              ...filteredList.take(3).map((c) {
                final statusColor = switch (c.status) {
                  'approved' => AppColors.statusSuccess,
                  'rejected' => AppColors.statusDanger,
                  _ => AppColors.statusWarning,
                };
                final statusIcon = switch (c.status) {
                  'approved' => Icons.check_circle_rounded,
                  'rejected' => Icons.cancel_rounded,
                  _ => Icons.hourglass_top_rounded,
                };
                final typeIcon = _getCorrectionTypeIcon(c.type);
                final typeColor = _getCorrectionTypeColor(c.type);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AttendanceCorrectionDetailPage(correctionId: c.id),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(typeIcon, size: 16, color: typeColor),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatCorrectionType(c.type),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                MobileStatusPill(c.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.event_outlined, size: 13, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('EEEE، d MMMM', 'ar').format(c.workDate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                if (c.requestedCheckIn != null || c.requestedCheckOut != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: scheme.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      c.requestedCheckIn != null
                                          ? 'المطلوب: ${DateFormat('h:mm a', 'ar').format(AppTime.toCairo(c.requestedCheckIn!))}'
                                          : 'المطلوب: ${DateFormat('h:mm a', 'ar').format(AppTime.toCairo(c.requestedCheckOut!))}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (c.reason.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  c.reason.trim(),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            // ── رد الإدارة / المراجع إن وُجد ──
                            if (c.reviewNote != null && c.reviewNote!.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(statusIcon, size: 14, color: statusColor),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'رد الإدارة: ${c.reviewNote!.trim()}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (corrections.length > 3) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.history_rounded, size: 16),
                    label: Text(
                      'عرض كافة طلبات التصحيح (${corrections.length})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MobileAttendanceServicesPage(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _formatCorrectionType(String type) => switch (type) {
    'missing_check_in' => 'بصمة حضور ناقصة',
    'missing_check_out' => 'بصمة انصراف ناقصة',
    'wrong_time' => 'تصحيح وقت البصمة',
    'wrong_status' => 'تصحيح حالة اليوم',
    'mission' => 'مأمورية عمل',
    'leave' => 'طلب إجازة',
    _ => 'تصحيح حضور',
  };

  static IconData _getCorrectionTypeIcon(String type) => switch (type) {
    'missing_check_in' => Icons.login_rounded,
    'missing_check_out' => Icons.logout_rounded,
    'wrong_time' => Icons.update_rounded,
    'wrong_status' => Icons.rule_rounded,
    'mission' => Icons.work_history_rounded,
    'leave' => Icons.beach_access_rounded,
    _ => Icons.edit_calendar_rounded,
  };

  static Color _getCorrectionTypeColor(String type) => switch (type) {
    'missing_check_in' => const Color(0xFF2563EB),
    'missing_check_out' => const Color(0xFFD97706),
    'wrong_time' => const Color(0xFF7C3AED),
    'wrong_status' => const Color(0xFF0284C7),
    'mission' => const Color(0xFF0D9488),
    'leave' => const Color(0xFFE11D48),
    _ => const Color(0xFF2563EB),
  };
}

