part of '../mobile_attendance_page.dart';

class _PenaltyCompensateBanner extends ConsumerWidget {
  const _PenaltyCompensateBanner({required this.state, this.checkInAt});

  final AttendanceState state;
  final DateTime? checkInAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final penalties =
        ref.watch(myInstantPenaltiesProvider).asData?.value ?? const [];
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // 1) فحص غرامة ملغاة اليوم لاستيفاء 8 ساعات
    final waivedToday = penalties
        .where(
          (p) =>
              p.workDate == todayStr &&
              p.status == 'cancelled' &&
              (p.cancelledReason?.contains('8 ساعات') ?? false),
        )
        .firstOrNull;

    if (waivedToday != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.statusSuccess.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.statusSuccess.withValues(alpha: .4),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_rounded,
              color: AppColors.statusSuccess,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تم إسقاط غرامة التأخير اليوم بنجاح 🎉',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.statusSuccess,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'تم إلغاء الخصم كاملاً لاستيفائك 8 ساعات عمل كاملة تعويضاً عن التأخير الصباحي.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 2) فحص هل يوجد إذن حضور/انصراف قيد الاعتماد للموظف اليوم
    final shiftInfo = ref.watch(myWorkShiftInfoProvider).asData?.value;
    final todayPermit = shiftInfo?.todayPermit ?? shiftInfo?.currentShift.todayPermit;
    final isPermitPending = todayPermit != null && todayPermit.status == 'pending';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPermitPending) {
      final isLateArrival = todayPermit.isLateArrival;
      final mins = todayPermit.permitMinutes;
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F1E36) : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF2563EB) : const Color(0xFF93C5FD),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: .3) : const Color(0xFF3B82F6).withValues(alpha: .08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1D4ED8).withValues(alpha: .35)
                    : const Color(0xFFDBEAFE),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLateArrival ? Icons.hourglass_top_rounded : Icons.logout_rounded,
                color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLateArrival
                        ? 'طلب إذن حضور ($mins دقيقة) ⏳ قيد الاعتماد'
                        : 'طلب إذن انصراف ($mins دقيقة) ⏳ قيد الاعتماد',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'طلبك مسجل وبانتظار قرار المدير المباشر. تم إيقاف أي احتساب لتأخير أو غرامات تلقائياً لحين البت في الطلب 🌿',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1E3A8A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 3) فحص الغرامة الفورية المسجلة لليوم (إن وجدت)
    final activePen = penalties
        .where(
          (p) =>
              p.workDate == todayStr &&
              (p.status == 'pending_payment' ||
                  p.status == 'doubled' ||
                  p.status == 'suspended'),
        )
        .firstOrNull;

    final hasLateFlag = state.todayStatus == 'late' ||
        state.lateMinutes > 0 ||
        state.estimatedLatePenaltyAmount > 0 ||
        state.isCompensationEligible ||
        activePen != null;

    if (!hasLateFlag) return const SizedBox.shrink();

    final effectiveCheckIn = state.todayCheckInAt ?? checkInAt ?? DateTime.now();
    final checkInStr = state.todayCheckInTime ??
        DateFormat('h:mm a', 'ar').format(AppTime.toCairo(effectiveCheckIn));
    final targetCheckout = state.targetCheckoutAt ??
        effectiveCheckIn.add(const Duration(hours: 8));
    final targetStr = state.targetCheckoutTime ??
        DateFormat('h:mm a', 'ar').format(AppTime.toCairo(targetCheckout));

    final penaltyAmount = activePen?.currentAmount ?? state.estimatedLatePenaltyAmount;
    final lateMins = activePen?.lateMinutes ?? state.lateMinutes;

    final now = DateTime.now();
    final remainingMins = state.compensationRemainingMinutes > 0
        ? state.compensationRemainingMinutes
        : targetCheckout.difference(now).inMinutes;
    final reached = state.isCompensationCompleted ||
        remainingMins <= 0 ||
        state.workMinutes >= 480;
    final overtimeMins = state.overtimeMinutes > 0
        ? state.overtimeMinutes
        : (reached ? now.difference(targetCheckout).inMinutes : 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: reached
            ? (isDark
                ? const Color(0xFF064E3B).withValues(alpha: .35)
                : AppColors.statusSuccess.withValues(alpha: .12))
            : (isDark
                ? const Color(0xFF26150B)
                : const Color(0xFFFFF7ED)),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: reached
              ? (isDark
                  ? const Color(0xFF059669)
                  : AppColors.statusSuccess.withValues(alpha: .4))
              : (isDark
                  ? const Color(0xFF9A3412)
                  : const Color(0xFFFDBA74)),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: reached
                ? (isDark
                    ? const Color(0xFF059669).withValues(alpha: .15)
                    : AppColors.statusSuccess.withValues(alpha: .06))
                : (isDark
                    ? Colors.black.withValues(alpha: .3)
                    : const Color(0xFFEA580C).withValues(alpha: .08)),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: reached
                      ? (isDark
                          ? const Color(0xFF065F46).withValues(alpha: .4)
                          : AppColors.statusSuccess.withValues(alpha: .18))
                      : (isDark
                          ? const Color(0xFF7C2D12).withValues(alpha: .45)
                          : const Color(0xFFF97316).withValues(alpha: .18)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  reached ? Icons.verified_user_rounded : Icons.lightbulb_rounded,
                  color: reached
                      ? (isDark ? const Color(0xFF34D399) : AppColors.statusSuccess)
                      : (isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C)),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reached
                          ? 'أتممت 8 ساعات عمل — سجّل انصرافك لإسقاط الغرامة 🔔'
                          : 'اقتراح ذكي لإسقاط غرامة التأخير 💡',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: reached
                            ? (isDark ? const Color(0xFF34D399) : AppColors.statusSuccess)
                            : (isDark ? const Color(0xFFFB923C) : const Color(0xFFC2410C)),
                      ),
                    ),
                    if (!reached && lateMins > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'تأخير $lateMins دقيقة • الخصم المقرر: ${penaltyAmount.toStringAsFixed(0)} ج.م',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFFDBA74) : const Color(0xFF9A3412),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reached
                ? 'لقد استوفيت وقت العمل المقرر (8 ساعات كاملة). يرجى تسجيل بصمة الانصراف الآن لتأكيد تواجدك بمقر العمل وإسقاط الغرامة تلقائياً دون أي خصم.'
                : 'حضرت اليوم في تمام الساعة $checkInStr. يتوجب عليك خصم بقيمة ${penaltyAmount.toStringAsFixed(0)} ج.م لتأخرك، ولكن إذا استكملت 8 ساعات عمل حتى الساعة $targetStr وسجلت بصمة الانصراف بمقر العمل، فسيتم تلقائياً إلغاء الغرامة وإسقاط الخصم كاملاً!',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: reached
                  ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF166534))
                  : (isDark ? const Color(0xFFFFEDD5) : const Color(0xFF431407)),
            ),
          ),
          if (!reached) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3A1C0B) : const Color(0xFFFFEDD5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF7C2D12) : const Color(0xFFFED7AA),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_filled_rounded,
                    size: 18,
                    color: isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'موعد الانصراف المقترح: $targetStr',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFFEDD5) : const Color(0xFF9A3412),
                      ),
                    ),
                  ),
                  Text(
                    remainingMins > 0
                        ? 'متبقٍ ${remainingMins ~/ 60} س و ${remainingMins % 60} د'
                        : 'دقائق معدودة',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (overtimeMins > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0D9488).withValues(alpha: 0.25)
                    : const Color(0xFF0D9488).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2DD4BF).withValues(alpha: 0.5)
                      : const Color(0xFF0D9488).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.more_time_rounded,
                    size: 16,
                    color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'الوقت الإضافي حتى الآن: +$overtimeMins دقيقة (${(overtimeMins / 60).floor()} س و ${overtimeMins % 60} د)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

