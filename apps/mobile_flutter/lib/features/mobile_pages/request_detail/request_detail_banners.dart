part of '../mobile_request_detail_page.dart';

class _SlaCountdownBanner extends StatefulWidget {
  const _SlaCountdownBanner({required this.request, required this.isMine});
  final MobileRequestDetail request;
  final bool isMine;

  @override
  State<_SlaCountdownBanner> createState() => _SlaCountdownBannerState();
}

class _SlaCountdownBannerState extends State<_SlaCountdownBanner>
    with WidgetsBindingObserver {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(_updateRemaining);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateRemaining();
    _startTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) setState(_updateRemaining);
      _startTimer();
    }
  }

  void _updateRemaining() {
    // SLA = createdAt + 2 hours
    final slaDeadline = widget.request.createdAt.add(const Duration(hours: 2));
    final now = DateTime.now();
    final diff = slaDeadline.difference(now);
    _remaining = diff.isNegative ? Duration.zero : diff;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$hس $mد';
    if (m > 0) return '$mد $sث';
    return '$sث';
  }

  @override
  Widget build(BuildContext context) {
    // يظهر فقط إذا الطلب pending ومن أنواع الأذونات (late_permit/early_permit)
    if (widget.request.status != 'pending') return const SizedBox.shrink();
    if (!['late_permit', 'early_permit', 'leave', 'mission', 'convoy']
        .contains(widget.request.type)) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOverdue = _remaining == Duration.zero;
    final isWarning = !isOverdue && _remaining.inMinutes <= 30;

    final bgColor = isOverdue
        ? (isDark ? const Color(0xFF3B1515) : const Color(0xFFFEF2F2))
        : isWarning
            ? (isDark ? const Color(0xFF2E1708) : const Color(0xFFFFF7ED))
            : (isDark ? const Color(0xFF0A2318) : const Color(0xFFF0FDF4));

    final borderColor = isOverdue
        ? AppColors.statusDanger.withValues(alpha: .5)
        : isWarning
            ? const Color(0xFFF97316).withValues(alpha: .6)
            : AppColors.statusSuccess.withValues(alpha: .4);

    final iconColor = isOverdue
        ? AppColors.statusDanger
        : isWarning
            ? const Color(0xFFF97316)
            : AppColors.statusSuccess;

    final textColor = isOverdue
        ? AppColors.statusDanger
        : isWarning
            ? (isDark ? const Color(0xFFFB923C) : const Color(0xFFC2410C))
            : (isDark ? const Color(0xFF34D399) : AppColors.statusSuccess);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.3),
      ),
      child: Row(
        children: [
          Icon(
            isOverdue ? Icons.warning_amber_rounded : Icons.timer_outlined,
            color: iconColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOverdue
                      ? 'انتهت مهلة المدير المباشر — تصعّد الطلب لمدير التشغيل (أبو عمار) ⚡'
                      : isWarning
                          ? 'تنبيه: متبقٍ ${_formatDuration(_remaining)} على تصعيد الطلب لأبو عمار!'
                          : 'المهلة المتاحة للمدير المباشر: ${_formatDuration(_remaining)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isOverdue
                      ? 'المدير المباشر لا يزال بإمكانه البت في الطلب حتى الآن'
                      : 'بعد انتهاء المهلة يُصعَّد تلقائياً، وللمدير المباشر حق البت حتى بعد التصعيد',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// شريط القرار الثابت أسفل الشاشة
// ═══════════════════════════════════════════════════════════════════════════

class _DecisionBar extends ConsumerWidget {
  const _DecisionBar({
    required this.request,
    required this.awaitingMe,
    required this.canDecide,
    required this.canDelegate,
    required this.currentStage,
  });

  final MobileRequestDetail request;
  final bool awaitingMe;
  final bool canDecide;
  final bool canDelegate;
  final String? currentStage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isEscalatedToOps = request.workflowStatus == 'awaiting_operator' ||
        (currentStage?.contains('مدير التشغيل') ?? false);
    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                canDecide
                    ? (isEscalatedToOps
                        ? 'الطلب عند مدير التشغيل (أبو عمار) — وبصفتك مديراً يمكنك قبوله أو رفضه الآن'
                        : (awaitingMe
                            ? 'الطلب بانتظار قرارك (مهلة ساعتان)'
                            : 'الطلب الآن عند ${currentStage ?? 'مرحلة أخرى'} — ويمكنك البت فيه بصلاحيتك'))
                    : 'القرار في هذه المرحلة لغيرك — ويمكنك تسريعه وتفويضه لمدير التشغيل (أبو عمار)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: (awaitingMe || isEscalatedToOps) && canDecide
                      ? AppColors.statusInfo
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (canDecide)
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.statusSuccess,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () =>
                            _openDecision(context, ref, request, 'approve'),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('اعتماد'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: requestReturnColor,
                          side: BorderSide(
                            color: requestReturnColor.withValues(alpha: .5),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () =>
                            _openDecision(context, ref, request, 'return'),
                        icon: const Icon(Icons.undo_rounded, size: 19),
                        label: const Text('إرجاع'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.statusDanger,
                          side: BorderSide(
                            color: AppColors.statusDanger.withValues(alpha: .5),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () =>
                            _openDecision(context, ref, request, 'reject'),
                        icon: const Icon(Icons.close_rounded, size: 19),
                        label: const Text('رفض'),
                      ),
                    ),
                  ],
                ),
              if (canDelegate) ...[
                if (canDecide) const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        const Color(0xFFD97706).withValues(alpha: .15),
                    foregroundColor: const Color(0xFFB45309),
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text(
                    'تسريع وتفويض لمدير التشغيل (م. محمد عبدالباسط)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: () async {
                    final done = await showRequestDelegateSheet(
                      context,
                      ref,
                      requestId: request.id,
                      number: request.number,
                      type: request.type,
                      employeeName: request.employeeName,
                    );
                    if (done) {
                      ref.invalidate(mobileRequestDetailProvider(request.id));
                      ref.invalidate(mobileRequestsProvider);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// البطاقة الرئيسية: النوع والرقم والحالة وصاحب الطلب
// ═══════════════════════════════════════════════════════════════════════════

class _ResubmitBanner extends StatelessWidget {
  const _ResubmitBanner({required this.returned});

  final bool returned;

  @override
  Widget build(BuildContext context) {
    final color = returned ? const Color(0xFFC2410C) : AppColors.statusDanger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.edit_note_rounded, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  returned ? 'أُعيد إليك الطلب للتعديل' : 'رُفض هذا الطلب',
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  'اقرأ ملاحظة المعتمِد في مسار الاعتماد، عدّل ما يلزم ثم أعد رفعه '
                  'ليبدأ مسار اعتماد جديد.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

