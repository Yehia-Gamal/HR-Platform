part of '../mobile_attendance_page.dart';

class _MissionStartCard extends StatelessWidget {
  const _MissionStartCard({
    required this.type,
    required this.startTime,
    required this.working,
    required this.onStart,
    this.onCancel,
  });

  final String type;
  final String? startTime;
  final bool working;
  final VoidCallback onStart;
  final VoidCallback? onCancel;

  String get _typeLabel => switch (type) {
    'convoy' => 'تكليف قافلة',
    'fundraising' => 'يوم ترفيهي (فاندي)',
    _ => 'مأمورية',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.secondary],
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.tour_outlined, color: scheme.onPrimary, size: 38),
                const SizedBox(height: 10),
                Text(
                  'لديك $_typeLabel اليوم',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  startTime == null
                      ? 'ابدأ مباشرة من نقطة المهمة — لا حاجة للمرور بمقر الجمعية.'
                      : 'الوقت المتوقع للبداية: $startTime — لا حاجة للمرور بمقر الجمعية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: working ? null : onStart,
                    icon: working
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('بدء المأمورية الآن'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (onCancel != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: working ? null : onCancel,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('إلغاء المأمورية'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.statusDanger,
                        side: BorderSide(color: AppColors.statusDanger.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionPendingCard extends StatelessWidget {
  const _MissionPendingCard({
    required this.type,
    this.working = false,
    this.onStart,
    this.onCancel,
  });

  final String type;
  final bool working;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  String get _typeLabel => switch (type) {
    'convoy' => 'تكليف قافلة',
    'fundraising' => 'يوم ترفيهي (فاندي)',
    _ => 'مأمورية عمل خارجية',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.statusWarning.withValues(alpha: 0.4)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.statusWarning.withValues(alpha: 0.08),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.statusWarning.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    color: AppColors.statusWarning,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'طلب $_typeLabel قيد المراجعة',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'طلب المأمورية مرفوع وبانتظار اعتماد الإدارة. يمكنك بدؤها الآن مباشرة عند الانطلاق.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onStart != null || onCancel != null) ...[
              const SizedBox(height: 12),
              if (onStart != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: working ? null : onStart,
                    icon: working
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('بدء المأمورية الآن'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.statusWarning,
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ),
              if (onCancel != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: working ? null : onCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('إلغاء المأمورية'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.statusDanger,
                      side: BorderSide(color: AppColors.statusDanger.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _MissionInProgressCard extends StatelessWidget {
  const _MissionInProgressCard({
    required this.startedAt,
    required this.working,
    required this.onEnd,
    this.onCancel,
  });

  final DateTime? startedAt;
  final bool working;
  final VoidCallback onEnd;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final startedLabel = startedAt == null
        ? null
        : DateFormat('h:mm a', 'ar').format(AppTime.toCairo(startedAt!));
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4338CA), Color(0xFF1E1B4B)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.explore_rounded,
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(height: 10),
                const Text(
                  'إنهاء المأمورية',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
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
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF34D399),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        startedLabel != null
                            ? 'المأمورية جارية منذ $startedLabel'
                            : 'مأمورية عمل جارية الآن',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'دوامك محتسب كحضور مأمورية — اضغط أدناه عند إنجاز المهمة للعودة للجمعية أو تسجيل الانصراف المباشر.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: working ? null : onEnd,
                    icon: working
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.stop_circle_rounded),
                    label: const Text('إنهاء المأمورية الآن'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4338CA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (onCancel != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: working ? null : onCancel,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('إلغاء المأمورية (العودة للوضع الطبيعي)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.statusDanger,
                        side: BorderSide(color: AppColors.statusDanger.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقة اكتمال اليوم — تظهر مكان زر البصمة بعد حضور وانصراف اليوم
// ═══════════════════════════════════════════════════════════════════════════════

class _DayCompletedCard extends StatelessWidget {
  const _DayCompletedCard({required this.checkIn, required this.checkOut});
  final DateTime? checkIn;
  final DateTime? checkOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final formatter = DateFormat('h:mm a', 'ar');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.statusSuccess, scheme.secondary],
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: scheme.onPrimary,
                  size: 38,
                ),
                const SizedBox(height: 10),
                Text(
                  'اكتمل حضورك وانصرافك اليوم',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ستظهر بصمتك من جديد بعد منتصف الليل',
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _StatusRow(
                  icon: Icons.login,
                  label: 'الحضور',
                  value: checkIn == null
                      ? '—'
                      : formatter.format(AppTime.toCairo(checkIn!)),
                  valueColor: AppColors.statusSuccess,
                ),
                const SizedBox(height: 8),
                _StatusRow(
                  icon: Icons.logout,
                  label: 'الانصراف',
                  value: checkOut == null
                      ? '—'
                      : formatter.format(AppTime.toCairo(checkOut!)),
                  valueColor: AppColors.statusSuccess,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقة حالة اليوم — تُخفي الحقول الفارغة
// ═══════════════════════════════════════════════════════════════════════════════

