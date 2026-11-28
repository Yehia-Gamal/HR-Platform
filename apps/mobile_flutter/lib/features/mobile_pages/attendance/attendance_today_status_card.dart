part of '../mobile_attendance_page.dart';

class _TodayStatusCard extends StatelessWidget {
  const _TodayStatusCard({
    required this.state,
    this.deviceLockConfigured,
    this.currentShift,
  });
  final AttendanceState state;
  final bool? deviceLockConfigured;
  final CurrentWorkShift? currentShift;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('h:mm a', 'ar');
    final scheme = Theme.of(context).colorScheme;
    final hasEvent = state.lastEventType != null;
    final liveDurationMins = state.workMinutes > 0
        ? state.workMinutes
        : (state.todayCheckInAt != null
            ? (state.todayCheckOutAt != null
                ? state.todayCheckOutAt!.difference(state.todayCheckInAt!).inMinutes
                : DateTime.now().difference(state.todayCheckInAt!).inMinutes)
            : 0);
    final isEightHoursFulfilled = liveDurationMins >= 480;
    final effectiveTodayStatus = (isEightHoursFulfilled &&
            (state.todayStatus == 'late' ||
                (state.todayStatus == 'missing_checkout' && state.todayCheckOutAt != null)))
        ? 'present'
        : (state.todayStatus ?? 'not_recorded');
    final hasStatus =
        state.todayStatus != null &&
        state.todayStatus != '—' &&
        state.todayStatus!.isNotEmpty;
    final nonWorkingDay = _isNonWorkingAttendanceDay(state);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.today_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'حالة اليوم',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                if (hasStatus)
                  Flexible(child: MobileStatusPill(effectiveTodayStatus))
                else if (state.missionToday != null)
                  Flexible(child: MobileStatusPill(state.missionToday!.type))
                else
                  const Flexible(child: MobileStatusPill('not_recorded')),
              ],
            ),
            const SizedBox(height: 12),

            if (nonWorkingDay &&
                state.todayCheckInAt == null &&
                state.todayCheckOutAt == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('لا توجد بصمة مطلوبة اليوم.'),
              ),
            if (state.todayCheckInAt != null ||
                state.todayCheckOutAt != null ||
                (!nonWorkingDay && currentShift != null)) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.login_rounded,
                                size: 16,
                                color: state.todayCheckInAt != null
                                    ? AppColors.statusSuccess
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'وقت الحضور',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.todayCheckInAt != null
                                ? formatter.format(AppTime.toCairo(state.todayCheckInAt!))
                                : 'لم يُسجل بعد',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: state.todayCheckInAt != null ? scheme.onSurface : scheme.onSurfaceVariant,
                            ),
                          ),
                          if (currentShift != null) ...[
                            const SizedBox(height: 3),
                            Builder(
                              builder: (_) {
                                if (state.todayCheckInAt != null) {
                                  final metric = _computeShiftDisciplineMetric(
                                    startTime: currentShift!.activeStartTime,
                                    graceInMinutes: currentShift!.graceInMinutes,
                                    todayCheckInAt: state.todayCheckInAt,
                                    todayCheckOutAt: state.todayCheckOutAt,
                                    workMinutes: state.workMinutes,
                                    hasPermit: currentShift!.hasTodayPermit,
                                    permitMinutes: currentShift!.todayPermit?.permitMinutes,
                                    originalStartTime: currentShift!.startTime,
                                  );
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(metric.icon, size: 12, color: metric.color),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          metric.badgeLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: metric.color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                } else {
                                  return Text(
                                    currentShift!.hasTodayPermit && currentShift!.todayPermit?.isLateArrival == true
                                        ? 'المقرر: ${currentShift!.formattedActiveStartTime} (إذن \u200E+${currentShift!.todayPermit!.permitMinutes} د)'
                                        : 'المقرر: ${currentShift!.formattedStartTime}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 42,
                      color: scheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                size: 16,
                                color: state.todayCheckOutAt != null
                                    ? AppColors.statusSuccess
                                    : AppColors.statusWarning,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'وقت الانصراف',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.todayCheckOutAt != null
                                ? formatter.format(AppTime.toCairo(state.todayCheckOutAt!))
                                : (state.todayCheckInAt != null ? 'قيد العمل الآن' : '—'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: state.todayCheckOutAt != null
                                  ? scheme.onSurface
                                  : (state.todayCheckInAt != null ? AppColors.statusWarning : scheme.onSurfaceVariant),
                            ),
                          ),
                          if (currentShift != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              state.todayCheckOutAt != null
                                  ? 'نهاية الوردية: ${currentShift!.formattedActiveEndTime}'
                                  : (currentShift!.hasTodayPermit && currentShift!.todayPermit?.isEarlyDeparture == true
                                      ? 'المقرر: ${currentShift!.formattedActiveEndTime} (إذن -${currentShift!.todayPermit!.permitMinutes} د)'
                                      : 'المقرر: ${currentShift!.formattedEndTime}'),
                              style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // صندوق الوقت الإضافي واستيفاء ساعات العمل (8 ساعات)
            if (state.todayCheckInAt != null && liveDurationMins >= 480) ...[
              Builder(
                builder: (context) {
                  final overtimeMins = state.overtimeMinutes > 0
                      ? state.overtimeMinutes
                      : (liveDurationMins > 480 ? liveDurationMins - 480 : 0);
                  final otHours = overtimeMins ~/ 60;
                  final otRemainingMins = overtimeMins % 60;
                  final totalWorkHours = liveDurationMins ~/ 60;
                  final totalWorkRemainingMins = liveDurationMins % 60;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: overtimeMins > 0
                          ? const Color(0xFF10B981).withValues(alpha: 0.12)
                          : scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: overtimeMins > 0
                            ? const Color(0xFF10B981).withValues(alpha: 0.45)
                            : scheme.primary.withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: overtimeMins > 0
                                ? const Color(0xFF10B981).withValues(alpha: 0.22)
                                : scheme.primary.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            overtimeMins > 0 ? Icons.more_time_rounded : Icons.verified_rounded,
                            color: overtimeMins > 0 ? const Color(0xFF059669) : scheme.primary,
                            size: 20,
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
                                      overtimeMins > 0
                                          ? 'وقت إضافي: $overtimeMins دقيقة'
                                          : 'تم استيفاء 8 ساعات عمل كاملة ✓',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: overtimeMins > 0
                                            ? const Color(0xFF047857)
                                            : scheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: overtimeMins > 0
                                          ? const Color(0xFF10B981).withValues(alpha: 0.25)
                                          : scheme.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      overtimeMins > 0
                                          ? '+$overtimeMins د إضافي'
                                          : 'مكتمل 100%',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: overtimeMins > 0
                                            ? const Color(0xFF047857)
                                            : scheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                overtimeMins > 0
                                    ? (otHours > 0
                                        ? 'إجمالي الدوام: $totalWorkHours س و$totalWorkRemainingMins د (إضافي: $overtimeMins دقيقة = $otHours س و$otRemainingMins د) · زال التأخير تماماً'
                                        : 'إجمالي الدوام: $totalWorkHours س و$totalWorkRemainingMins د (إضافي: $overtimeMins دقيقة) · زال التأخير تماماً')
                                    : 'إجمالي الدوام: 8 ساعات كاملة · تم تعويض ساعات التأخير بنجاح وزالت أي خصومات',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],

            // الوردية المعتمدة
            if (currentShift != null) ...[
              _StatusRow(
                icon: Icons.schedule_rounded,
                label: 'الوردية المعتمدة',
                value: '${currentShift!.name} (${currentShift!.formattedRange})',
                trailing: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    if (currentShift!.hasTodayPermit && currentShift!.todayPermit != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD97706).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFD97706).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          currentShift!.todayPermit!.isLateArrival
                              ? 'إذن \u200E+${currentShift!.todayPermit!.durationLabel}'
                              : 'إذن \u200E-${currentShift!.todayPermit!.durationLabel}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (currentShift!.isAssigned ? AppColors.statusSuccess : scheme.primary).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        currentShift!.badgeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: currentShift!.isAssigned ? AppColors.statusSuccess : scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // التكليف الميداني الحالي إن وُجد
            if (state.missionToday != null) ...[
              _StatusRow(
                icon: Icons.location_on_outlined,
                label: 'التكليف الميداني',
                value: switch (state.missionToday!.type) {
                  'convoy' => 'قافلة معتمدة',
                  'fundraising' => 'يوم ترفيهي (فاندي)',
                  _ => 'مأمورية عمل خارجية',
                },
                valueColor: switch (state.missionToday!.type) {
                  'convoy' => const Color(0xFF7C3AED),
                  'fundraising' => const Color(0xFF0D9488),
                  _ => const Color(0xFF2563EB),
                },
              ),
              const SizedBox(height: 8),
            ],

            // أمان الجهاز
            _StatusRow(
              icon: Icons.lock_outline,
              label: 'أمان الجهاز',
              value: !state.hasActiveLocalDevice
                  ? 'غير مفعلة'
                  : (deviceLockConfigured == false)
                      ? 'مفعلة (قفل الشاشة مطلوب)'
                      : 'مفعلة',
              valueColor: !state.hasActiveLocalDevice
                  ? scheme.error
                  : (deviceLockConfigured == false)
                      ? AppColors.statusWarning
                      : AppColors.statusSuccess,
            ),

            // آخر عملية (فقط عند وجود بيانات)
            if (hasEvent) ...[
              const SizedBox(height: 8),
              _StatusRow(
                icon: state.lastEventType == 'CHECK_IN'
                    ? Icons.login
                    : Icons.logout,
                label: 'آخر عملية',
                value:
                    '${state.lastEventType == 'CHECK_IN' ? 'حضور' : 'انصراف'}'
                    '${state.lastEventAt != null ? ' · ${formatter.format(AppTime.toCairo(state.lastEventAt!))}' : ''}',
              ),
            ],

            // حالة التحقق (فقط عند وجودها)
            if (state.lastEventStatus != null) ...[
              const SizedBox(height: 8),
              _StatusRow(
                icon: Icons.verified_outlined,
                label: 'التحقق',
                trailing: MobileStatusPill(state.lastEventStatus!),
              ),
            ],

            // رسالة عندما لا يوجد أي نشاط
            if (!hasEvent && !hasStatus) ...[
              const SizedBox(height: 4),
              Text(
                'لم تُسجَّل أي عملية حضور اليوم',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

