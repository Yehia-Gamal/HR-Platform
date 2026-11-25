part of '../my_instant_penalties_page.dart';

class _TodayCompensationProposalBanner extends ConsumerWidget {
  const _TodayCompensationProposalBanner({
    required this.penalty,
    this.compact = false,
  });

  final MobileInstantPenalty penalty;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(attendanceStateProvider).asData?.value;
    final checkInStr =
        state?.todayCheckInTime ??
        (state?.todayCheckInAt != null
            ? DateFormat(
                'h:mm a',
                'ar',
              ).format(AppTime.toCairo(state!.todayCheckInAt!))
            : null);
    final targetStr =
        state?.targetCheckoutTime ??
        (state?.todayCheckInAt != null
            ? DateFormat('h:mm a', 'ar').format(
                AppTime.toCairo(state!.todayCheckInAt!.add(const Duration(hours: 8))),
              )
            : null);
    final remainingMins = state?.compensationRemainingMinutes ?? 0;
    final reached =
        (state?.isCompensationCompleted ?? false) ||
        (state?.workMinutes ?? 0) >= 480;

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: reached
            ? (isDark
                ? const Color(0xFF064E3B).withValues(alpha: 0.35)
                : AppColors.statusSuccess.withValues(alpha: 0.12))
            : (isDark ? const Color(0xFF2E1708) : const Color(0xFFFFF7ED)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reached
              ? (isDark
                  ? const Color(0xFF059669)
                  : AppColors.statusSuccess.withValues(alpha: 0.4))
              : (isDark ? const Color(0xFF9A3412) : const Color(0xFFFDBA74)),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                reached ? Icons.verified_user_rounded : Icons.lightbulb_rounded,
                color: reached
                    ? (isDark
                          ? const Color(0xFF34D399)
                          : AppColors.statusSuccess)
                    : (isDark
                          ? const Color(0xFFFB923C)
                          : const Color(0xFFEA580C)),
                size: compact ? 18 : 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reached
                      ? 'أتممت 8 ساعات عمل — سجّل انصرافك لإلغاء الغرامة 🎉'
                      : 'فرصة ذكية لإسقاط هذه الغرامة (${penalty.currentAmount.toStringAsFixed(0)} ج.م) 💡',
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.bold,
                    color: reached
                        ? (isDark
                              ? const Color(0xFF34D399)
                              : AppColors.statusSuccess)
                        : (isDark
                              ? const Color(0xFFFB923C)
                              : const Color(0xFFC2410C)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reached
                ? 'استوفيت ساعات العمل المطلوبة (8 ساعات كاملة). سجّل بصمة الانصراف الآن بمقر العمل لإسقاط الغرامة تلقائياً دون أي خصم.'
                : (checkInStr != null && targetStr != null)
                    ? 'حضرت اليوم الساعة $checkInStr (تأخير ${penalty.lateMinutes} د). إذا استكملت 8 ساعات عمل حتى الساعة $targetStr وسجلت بصمة الانصراف، فسيتم تلقائياً إلغاء الغرامة وإسقاط الخصم كاملاً!'
                    : 'إذا استكملت 8 ساعات عمل وسجلت بصمة الانصراف بمقر العمل، فسيتم تلقائياً إلغاء الغرامة وإسقاط الخصم كاملاً دون أي مقابل!',
            style: TextStyle(
              fontSize: compact ? 12 : 12.5,
              height: 1.4,
              color: reached
                  ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF166534))
                  : (isDark
                        ? const Color(0xFFFFEDD5)
                        : const Color(0xFF7C2D12)),
            ),
          ),
          if (!reached && targetStr != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF261205)
                    : const Color(0xFFFFEDD5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF7C2D12)
                      : const Color(0xFFFED7AA),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 15,
                        color: Color(0xFFEA580C),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'الموعد المستهدف للانصراف: $targetStr',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFFFDBA74)
                              : const Color(0xFF9A3412),
                        ),
                      ),
                    ],
                  ),
                  if (remainingMins > 0)
                    Text(
                      'متبقٍ ${remainingMins ~/ 60} س و ${remainingMins % 60} د',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFFB923C)
                            : const Color(0xFFC2410C),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            icon,
            size: 52,
            color: theme.colorScheme.primary.withValues(alpha: .6),
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: const [
      SizedBox(height: 200),
      Center(child: CircularProgressIndicator()),
    ],
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 100),
      Icon(
        Icons.error_outline,
        size: 48,
        color: Theme.of(context).colorScheme.error,
      ),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('إعادة المحاولة'),
        ),
      ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// صياغة
// ═══════════════════════════════════════════════════════════════════════════

bool _isUnpaid(String status) =>
    status == 'pending_payment' || status == 'doubled' || status == 'suspended';

String _money(num v) => '${fmtUnits(v)} ج.م';

String _minutes(int m) => switch (m) {
  1 => 'دقيقة واحدة',
  2 => 'دقيقتان',
  >= 3 && <= 10 => '$m دقائق',
  _ => '$m دقيقة',
};

String _duration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return _minutes(m);
  return m == 0 ? '$h ساعة' : '$h ساعة و$m دقيقة';
}

String _dateTime(DateTime t) {
  final local = AppTime.toCairo(t);
  return '${DateFormat('d MMMM y', 'ar').format(local)} · ${DateFormat('h:mm a', 'ar').format(local)}';
}

/// وقت تسجيل الغرامة: الساعة وحدها إن كانت يوم العمل نفسه (الغالب)، وإلا
/// التاريخ معها.
String _registeredAt(DateTime createdAt, DateTime? workDate) {
  final local = AppTime.toCairo(createdAt);
  final time = DateFormat('h:mm a', 'ar').format(local);
  final sameDay =
      workDate != null &&
      local.year == workDate.year &&
      local.month == workDate.month &&
      local.day == workDate.day;
  return sameDay ? time : '${DateFormat('d MMM', 'ar').format(local)} · $time';
}

String _paymentLabel(String? method) => switch (method) {
  null || 'cash' => 'نقدًا لدى مسؤول الصندوق',
  'vodafone_cash' => 'فودافون كاش',
  'bank_transfer' => 'تحويل بنكي',
  'wallet' => 'محفظة إلكترونية',
  'instapay' => 'تحويل إلكتروني',
  _ => 'نقدًا',
};

/// ({label, color, icon, exempt}) لحالة الغرامة.
({String label, Color color, IconData icon, bool exempt}) _statusMeta(
  MobileInstantPenalty item,
) {
  if (item.status == 'cancelled') {
    final hay = '${item.cancelledReason ?? ''} ${item.notes ?? ''}';
    final isEightHours = hay.contains('8 ساعات') || hay.contains('ثماني ساعات');
    if (isEightHours) {
      return (
        label: 'معفاة (8 ساعات عمل)',
        color: const Color(0xFF059669),
        icon: Icons.timer_outlined,
        exempt: true,
      );
    }
    final isShiftChange =
        hay.contains('وردية') ||
        hay.contains('فترة العمل') ||
        hay.contains('فترة عمل');
    if (isShiftChange) {
      return (
        label: 'ملغاة (اعتماد الوردية)',
        color: const Color(0xFF0284C7),
        icon: Icons.swap_horiz_rounded,
        exempt: true,
      );
    }
    final isFunday = hay.contains('فاندي') || hay.contains('فندى');
    if (isFunday) {
      return (
        label: 'معفاة (يوم فاندي)',
        color: const Color(0xFF7C3AED),
        icon: Icons.celebration_rounded,
        exempt: true,
      );
    }
    final isMission = hay.contains('مأمورية');
    if (isMission) {
      return (
        label: 'معفاة (مأمورية عمل)',
        color: const Color(0xFF0D9488),
        icon: Icons.work_outline_rounded,
        exempt: true,
      );
    }
    final exempt = const [
      'إعفاء',
      'معفى',
      'إلغاء تلقائي',
      'بأثر رجعي',
      'إجازة',
      'قافلة',
      'استثناء',
    ].any(hay.contains);
    return exempt
        ? (
            label: 'معفاة',
            color: const Color(0xFF0D9488),
            icon: Icons.verified_outlined,
            exempt: true,
          )
        : (
            label: 'ملغاة',
            color: const Color(0xFF64748B),
            icon: Icons.cancel_outlined,
            exempt: false,
          );
  }
  return switch (item.status) {
    'pending_payment' => (
      label: 'بانتظار السداد',
      color: AppColors.statusWarning,
      icon: Icons.schedule_rounded,
      exempt: false,
    ),
    'doubled' => (
      label: 'مضاعفة',
      color: const Color(0xFFEA580C),
      icon: Icons.trending_up_rounded,
      exempt: false,
    ),
    'suspended' => (
      label: 'الحساب موقوف',
      color: AppColors.statusDanger,
      icon: Icons.block_rounded,
      exempt: false,
    ),
    'paid' => (
      label: 'مسددة',
      color: AppColors.statusSuccess,
      icon: Icons.check_circle_rounded,
      exempt: false,
    ),
    _ => (
      label: 'غير محددة',
      color: const Color(0xFF64748B),
      icon: Icons.help_outline_rounded,
      exempt: false,
    ),
  };
}

/// الملاحظات القديمة متداخلة («تم الإلغاء بواسطة الإدارة: س (تم الإلغاء… (…)))»)
/// وبأوقات AM/PM — تُفك إلى أسباب الإلغاء وأسطر التفاصيل بالعربية.
({List<String> reasons, List<String> lines}) _parseNotes(String? notes) {
  var text = (notes ?? '').trim();
  final reasons = <String>[];
  const prefix = 'تم الإلغاء بواسطة الإدارة: ';
  while (text.startsWith(prefix)) {
    final rest = text.substring(prefix.length);
    final open = rest.indexOf(' (');
    if (open < 0) {
      reasons.add(rest.trim());
      text = '';
      break;
    }
    reasons.add(rest.substring(0, open).trim());
    var inner = rest.substring(open + 2).trim();
    if (inner.endsWith(')')) inner = inner.substring(0, inner.length - 1);
    text = inner.trim();
  }
  final lines = text.isEmpty
      ? <String>[]
      : text
            .split(' | ')
            .map((l) => humanizeIsoLike(l.trim()))
            .where((l) => l.isNotEmpty)
            .toList();
  return (reasons: reasons.toSet().toList(), lines: lines);
}

/// «11:57 AM» ← «11:57 ص»، وتواريخ ISO داخل النص بصيغة عربية لا تنقلب.
String humanizeIsoLike(String text) => text
    .replaceAllMapped(
      RegExp(r'(\d{1,2}:\d{2})\s*(AM|am)\b'),
      (m) => '${m[1]} ص',
    )
    .replaceAllMapped(
      RegExp(r'(\d{1,2}:\d{2})\s*(PM|pm)\b'),
      (m) => '${m[1]} م',
    )
    .replaceAllMapped(
      RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
      (m) => '${m[3]!.padLeft(2, '0')}/${m[2]!.padLeft(2, '0')}/${m[1]}',
    );
