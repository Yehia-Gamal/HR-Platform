part of '../mobile_attendance_page.dart';

class _ShiftTimelineBar extends StatelessWidget {
  const _ShiftTimelineBar({
    required this.startTime,
    required this.endTime,
    required this.graceInMinutes,
    this.hasPermit = false,
    this.permitMinutes,
    this.effectiveStartTime,
    this.effectiveGraceEndTime,
  });

  final String startTime;
  final String endTime;
  final int graceInMinutes;
  final bool hasPermit;
  final int? permitMinutes;
  final String? effectiveStartTime;
  final String? effectiveGraceEndTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startDisplay = startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
    final endDisplay = endTime.length >= 5 ? endTime.substring(0, 5) : endTime;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasPermit
                      ? 'مخطط محطات الوردية بعد تطبيق الإذن المعتمد:'
                      : 'مخطط محطات الوردية اليومية والاحتساب:',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              if (hasPermit)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'معدل بالإذن',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasPermit && effectiveStartTime != null) ...[
            Row(
              children: [
                Expanded(
                  child: _TimelinePoint(
                    time: startDisplay,
                    label: 'الوردية الأصلية',
                    sublabel: 'الموعد الأساسي',
                    color: scheme.onSurfaceVariant,
                    isFirst: true,
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: '\u200E+${permitMinutes ?? 120} د',
                    label: 'إذن معتمد',
                    sublabel: 'إزاحة رسمية',
                    color: const Color(0xFFD97706),
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: effectiveStartTime!,
                    label: 'الموعد المصرح',
                    sublabel: 'سماح $graceInMinutes د',
                    color: const Color(0xFF2563EB),
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: endDisplay,
                    label: 'الانصراف',
                    sublabel: 'نهاية اليوم',
                    color: const Color(0xFF059669),
                    isLast: true,
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _TimelinePoint(
                    time: startDisplay,
                    label: 'بداية الوردية',
                    sublabel: 'بدء الدوام',
                    color: scheme.primary,
                    isFirst: true,
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: '\u200E+$graceInMinutes د',
                    label: 'نهاية السماح',
                    sublabel: '0 خصم',
                    color: const Color(0xFFD97706),
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: endDisplay,
                    label: 'الانصراف المقرر',
                    sublabel: 'اكتملت الساعات',
                    color: const Color(0xFF059669),
                    isLast: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelinePoint extends StatelessWidget {
  const _TimelinePoint({
    required this.time,
    required this.label,
    required this.sublabel,
    required this.color,
    this.isFirst = false,
    this.isLast = false,
  });

  final String time;
  final String label;
  final String sublabel;
  final Color color;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: isFirst
                  ? const SizedBox.shrink()
                  : Container(
                      height: 2,
                      color: color.withValues(alpha: 0.35),
                    ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            Expanded(
              child: isLast
                  ? const SizedBox.shrink()
                  : Container(
                      height: 2,
                      color: color.withValues(alpha: 0.35),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          sublabel,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ShiftMiniChip extends StatelessWidget {
  const _ShiftMiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// V20: قسم تصحيحات وبلاغات الحضور المطور — تصميم عصري، تصفية ذكية، واختصارات فورية
class _FilterTabChip extends StatelessWidget {
  const _FilterTabChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = color ?? scheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : scheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : scheme.onSurface,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : scheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCorrectionActionChip extends StatelessWidget {
  const _QuickCorrectionActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

