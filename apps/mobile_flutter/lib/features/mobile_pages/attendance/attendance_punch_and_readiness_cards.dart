part of '../mobile_attendance_page.dart';

/// بطاقة فحص جاهزية البصمة قبل الضغط:
/// تعرض حالة GPS والدقة والنطاق الجغرافي وحالة الجهاز المسجّل.
class _PrePunchReadinessStrip extends StatelessWidget {
  const _PrePunchReadinessStrip({
    required this.state,
    required this.preflight,
    required this.onRefresh,
  });

  final AttendanceState state;
  final AsyncValue<GpsPreflightResult> preflight;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gpsResult = preflight.asData?.value;
    final gpsReady = gpsResult?.isReady ?? false;
    final accuracy = gpsResult?.accuracyMeters;
    final isMocked = gpsResult?.isMocked == true;

    final String gpsLabel;
    final Color gpsColor;
    if (preflight.isLoading) {
      gpsLabel = 'GPS: جارٍ الفحص...';
      gpsColor = scheme.onSurfaceVariant;
    } else if (!gpsReady) {
      gpsLabel = gpsResult?.arabicSummary ?? 'GPS: غير جاهز';
      gpsColor = AppColors.statusDanger;
    } else if (isMocked) {
      gpsLabel = 'تحذير: موقع مزيّف مفعّل';
      gpsColor = AppColors.statusDanger;
    } else if (accuracy != null) {
      final ok = accuracy <= 150;
      gpsLabel = 'GPS جاهز · دقة ${accuracy.round()} م (الحد 150 م)';
      gpsColor = ok ? AppColors.statusSuccess : AppColors.statusWarning;
    } else {
      gpsLabel = 'GPS جاهز (تُقاس الدقة عند البصمة)';
      gpsColor = AppColors.statusSuccess;
    }

    final String deviceLabel;
    final Color deviceColor;
    if (state.hasActiveLocalDevice) {
      deviceLabel = 'الجهاز: مسجّل ومفعّل ✓';
      deviceColor = AppColors.statusSuccess;
    } else if (state.localDeviceStatus == 'pending') {
      deviceLabel = 'الجهاز: بانتظار موافقة المسؤول';
      deviceColor = AppColors.statusWarning;
    } else {
      deviceLabel = 'الجهاز: غير مسجّل بعد';
      deviceColor = AppColors.statusDanger;
    }

    final String geofenceLabel;
    final Color geofenceColor;
    if (state.lastEventStatus == 'accepted') {
      geofenceLabel = 'النطاق: آخر بصمة داخل النطاق المعتمد ✓';
      geofenceColor = AppColors.statusSuccess;
    } else if (state.lastEventStatus == 'rejected' ||
        state.lastEventStatus == 'flagged') {
      geofenceLabel = 'النطاق: يتطلب مراجعة — سجّل من داخل المقر';
      geofenceColor = AppColors.statusWarning;
    } else {
      geofenceLabel = 'النطاق: يُتحقق من المجمع على الخادم لحظة البصمة';
      geofenceColor = scheme.primary;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 17, color: scheme.primary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'جاهزية البصمة قبل التسجيل',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'تحديث الجاهزية',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _ReadinessRow(
              icon: Icons.gps_fixed_rounded,
              label: gpsLabel,
              color: gpsColor,
            ),
            const SizedBox(height: 4),
            _ReadinessRow(
              icon: Icons.location_searching_rounded,
              label: geofenceLabel,
              color: geofenceColor,
            ),
            const SizedBox(height: 4),
            _ReadinessRow(
              icon: Icons.phonelink_lock_rounded,
              label: deviceLabel,
              color: deviceColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقة البصمة الرئيسية — إجراء واحد واضح
// ═══════════════════════════════════════════════════════════════════════════════

class _PunchCard extends StatefulWidget {
  const _PunchCard({
    required this.actionLabel,
    required this.actionIcon,
    required this.isCheckIn,
    required this.hasActiveDevice,
    required this.devicePending,
    required this.canPunch,
    required this.working,
    required this.onRegister,
    required this.onPunch,
    this.currentShift,
    this.todayCheckInAt,
  });

  final String actionLabel;
  final IconData actionIcon;
  final bool isCheckIn;
  final bool hasActiveDevice;
  final bool devicePending;
  final bool canPunch;
  final bool working;
  final VoidCallback onRegister;
  final VoidCallback onPunch;
  final CurrentWorkShift? currentShift;
  final DateTime? todayCheckInAt;

  @override
  State<_PunchCard> createState() => _PunchCardState();
}

class _PunchCardState extends State<_PunchCard> {
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _checkCooldownTimer();
  }

  @override
  void didUpdateWidget(covariant _PunchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todayCheckInAt != widget.todayCheckInAt ||
        oldWidget.isCheckIn != widget.isCheckIn) {
      _checkCooldownTimer();
    }
  }

  void _checkCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    if (!widget.isCheckIn && widget.todayCheckInAt != null) {
      final elapsed = DateTime.now().toUtc().difference(widget.todayCheckInAt!.toUtc()).inSeconds;
      if (elapsed < 120) {
        _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          final currentElapsed = DateTime.now().toUtc().difference(widget.todayCheckInAt!.toUtc()).inSeconds;
          if (currentElapsed >= 120) {
            timer.cancel();
            setState(() {});
          } else {
            setState(() {});
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  int get _cooldownRemainingSeconds {
    if (widget.isCheckIn || widget.todayCheckInAt == null) return 0;
    final elapsed = DateTime.now().toUtc().difference(widget.todayCheckInAt!.toUtc()).inSeconds;
    final remaining = 120 - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  @override
  Widget build(BuildContext context) {
    final cooldownRemaining = _cooldownRemainingSeconds;
    final inCooldown = !widget.isCheckIn && cooldownRemaining > 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // البانر العلوي
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.isCheckIn
                    ? [AppColors.brandPrimary, const Color(0xFF1E3A8A)]
                    : [const Color(0xFFD97706), const Color(0xFF9A3412)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  widget.isCheckIn ? Icons.fingerprint : Icons.logout_rounded,
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.actionLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (widget.currentShift != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isCheckIn ? Icons.schedule_rounded : Icons.timer_outlined,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            widget.isCheckIn
                                ? (widget.currentShift!.hasTodayPermit
                                    ? 'الوردية: ${widget.currentShift!.formattedStartTime} · إذن حتى ${widget.currentShift!.formattedActiveStartTime} (سماح ${widget.currentShift!.formattedActiveGraceEndTime})'
                                    : 'الوردية: ${widget.currentShift!.formattedStartTime} · سماح حتى ${widget.currentShift!.formattedGraceEndTime}')
                                : (widget.currentShift!.hasTodayPermit && widget.currentShift!.todayPermit?.isEarlyDeparture == true
                                    ? 'الانصراف المصرح: ${widget.currentShift!.formattedActiveEndTime} (إذن -${widget.currentShift!.todayPermit!.permitMinutes} د)'
                                    : 'الانصراف الرسمي: ${widget.currentShift!.formattedEndTime}'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  widget.isCheckIn
                      ? 'بصمة أو نقش + الموقع → يتم التحقق تلقائياً'
                      : (inCooldown
                          ? 'سُجّل حضورك للتو — الانصراف متاح بعد دقيقتين'
                          : 'تسجيل انصراف اليوم وحفظ ساعات العمل'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          // زر الإجراء
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildActionButton(context, inCooldown, cooldownRemaining),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, bool inCooldown, int cooldownRemaining) {
    if (widget.devicePending) {
      return _WarningBanner(
        icon: Icons.hourglass_top_outlined,
        text: 'جهازك مسجل وينتظر موافقة المسؤول',
      );
    }

    if (!widget.hasActiveDevice) {
      return Semantics(
        button: true,
        label: 'تفعيل الحضور بأمان الجهاز',
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.working ? null : widget.onRegister,
            icon: widget.working
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fingerprint),
            label: const Text('تفعيل الحضور بأمان الجهاز'),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (inCooldown) ...[
          Builder(builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFFB45309).withValues(alpha: 0.16) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : const Color(0xFFF59E0B),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'سُجّل حضورك للتو! الانصراف متاح بعد $cooldownRemaining ثانية لمنع الانصراف غير المقصود.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            );
          })
        ],
        Semantics(
          button: true,
          label: inCooldown
              ? 'الانصراف متاح بعد $cooldownRemaining ثانية'
              : widget.actionLabel,
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: widget.working || !widget.canPunch || inCooldown ? null : widget.onPunch,
              icon: widget.working
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(inCooldown ? Icons.hourglass_top_rounded : widget.actionIcon),
              label: Text(
                inCooldown
                    ? 'الانصراف متاح بعد ($cooldownRemaining ث)'
                    : widget.actionLabel,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: widget.isCheckIn ? null : (inCooldown ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : Colors.grey.shade400) : const Color(0xFFD97706)),
                foregroundColor: widget.isCheckIn ? null : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 0450: بطاقات دورة يوم المأمورية — تحل محل زر البصمة في يوم التكليف
// ═══════════════════════════════════════════════════════════════════════════════

