part of '../mobile_attendance_page.dart';

class _WorkShiftActiveCard extends StatelessWidget {
  const _WorkShiftActiveCard({
    required this.current,
    required this.pending,
    required this.shiftIcon,
    required this.shiftColor,
    required this.liveStatus,
    required this.disciplineMetric,
    required this.scheme,
  });

  final CurrentWorkShift current;
  final PendingShiftChange? pending;
  final IconData shiftIcon;
  final Color shiftColor;
  final _ShiftLiveStatus liveStatus;
  final _ShiftDisciplineMetric disciplineMetric;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // بطاقة الوردية المعتمدة بتصميم راقٍ
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            shiftColor.withValues(alpha: 0.07),
                            scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          ],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: shiftColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: shiftColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(shiftIcon, size: 18, color: shiftColor),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  current.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: current.isAssigned
                                      ? AppColors.statusSuccess.withValues(alpha: 0.14)
                                      : scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: current.isAssigned
                                        ? AppColors.statusSuccess.withValues(alpha: 0.4)
                                        : scheme.primary.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      current.isAssigned
                                          ? Icons.verified_rounded
                                          : Icons.schedule_outlined,
                                      size: 14,
                                      color: current.isAssigned
                                          ? AppColors.statusSuccess
                                          : scheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      current.badgeLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: current.isAssigned
                                            ? AppColors.statusSuccess
                                            : scheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _ShiftDetailChip(
                                icon: Icons.login_rounded,
                                label: 'الحضور: ${current.formattedStartTime}',
                                color: scheme.primary,
                              ),
                              _ShiftDetailChip(
                                icon: Icons.hourglass_empty_rounded,
                                label: 'سماح: ${current.graceInMinutes} دقيقة',
                                color: AppColors.statusWarning,
                              ),
                              _ShiftDetailChip(
                                icon: Icons.logout_rounded,
                                label: 'الانصراف: ${current.formattedEndTime}',
                                color: scheme.secondary,
                              ),
                            ],
                          ),

                          // شارة وبطاقة إذن الحضور أو الانصراف المعتمد لليوم (إن وُجد)
                          if (current.todayPermit != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706).withValues(alpha: 0.09),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFD97706).withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD97706).withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.verified_user_rounded,
                                      size: 18,
                                      color: Color(0xFFD97706),
                                    ),
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
                                                current.todayPermit!.isLateArrival
                                                    ? 'إذن حضور معتمد (\u200E+${current.todayPermit!.durationLabel})'
                                                    : 'إذن انصراف مبكر معتمد (${current.todayPermit!.durationLabel})',
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFB45309),
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.statusSuccess.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'معتمد لليوم',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.statusSuccess,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          current.todayPermit!.isLateArrival
                                              ? 'الموعد المصرح بعد الإذن: ${current.formattedActiveStartTime} · فترة السماح حتى ${current.formattedActiveGraceEndTime}'
                                              : 'الانصراف المصرح: ${current.formattedActiveEndTime}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: scheme.onSurface,
                                          ),
                                        ),
                                        if (current.todayPermit!.title.isNotEmpty &&
                                            current.todayPermit!.title != 'إذن معتمد') ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'السبب: ${current.todayPermit!.title}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),

                          // شريط ومؤشر الحالة اللحظية للوردية
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: liveStatus.color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: liveStatus.color.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(liveStatus.icon, size: 16, color: liveStatus.color),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        liveStatus.statusLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: liveStatus.color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        liveStatus.detailLabel,
                                        textAlign: TextAlign.end,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (liveStatus.progress != null) ...[
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: liveStatus.progress,
                                      backgroundColor: liveStatus.color.withValues(alpha: 0.15),
                                      valueColor: AlwaysStoppedAnimation<Color>(liveStatus.color),
                                      minHeight: 4,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ── بطاقة احتساب التأخير والانضباط والخصومات الفردية ──
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: disciplineMetric.color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: disciplineMetric.color.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(disciplineMetric.icon, size: 16, color: disciplineMetric.color),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        disciplineMetric.statusTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: disciplineMetric.color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: disciplineMetric.color.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        disciplineMetric.badgeLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: disciplineMetric.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  disciplineMetric.statusSubtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ── مخطط محطات الوردية اليومية ──
                          _ShiftTimelineBar(
                            startTime: current.startTime,
                            endTime: current.endTime,
                            graceInMinutes: current.graceInMinutes,
                            hasPermit: current.hasTodayPermit,
                            permitMinutes: current.todayPermit?.permitMinutes,
                            effectiveStartTime: current.hasTodayPermit ? current.formattedActiveStartTime : null,
                            effectiveGraceEndTime: current.hasTodayPermit ? current.formattedActiveGraceEndTime : null,
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'تُحتسب التأخيرات والخصومات الفردية بناءً على مواعيد هذه الوردية المعتمدة.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _showShiftPolicyDialog(context),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.info_outline, size: 13, color: scheme.primary),
                                      const SizedBox(width: 2),
                                      Text(
                                        'السياسة',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // إشعار طلب التغيير المعلق (إن وجد) بتصميم تفاعلي ينقل مباشرة للتفاصيل
                    if (pending case final pendingReq?) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MobileRequestDetailPage(
                                requestId: pendingReq.requestId,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.statusWarning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.statusWarning.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.hourglass_top_rounded,
                                size: 18,
                                color: AppColors.statusWarning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'طلب قيد المراجعة والاعتماد: ${pendingReq.requestedShiftName ?? 'تغيير الوردية'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.statusWarning,
                                      ),
                                    ),
                                    if (pendingReq.reason != null && pendingReq.reason!.trim().isNotEmpty)
                                      Text(
                                        pendingReq.reason!.trim(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.statusWarning.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'بانتظار الإدارة',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.statusWarning,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 12,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
  }
}
