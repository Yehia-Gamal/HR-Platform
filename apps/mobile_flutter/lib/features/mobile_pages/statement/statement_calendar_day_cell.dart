part of '../monthly_attendance_statement_page.dart';

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.statement,
    required this.dayNum,
    required this.dayData,
    required this.isToday,
    required this.isFuture,
    required this.year,
    required this.month,
    this.isDimmed = false,
    this.isHighlighted = false,
  });
  final MonthlyAttendanceStatement statement;
  final int dayNum;
  final AttendanceStatementDay? dayData;
  final bool isToday;
  final bool isFuture;
  final int year;
  final int month;
  final bool isDimmed;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _resolveStyle(scheme);

    return Semantics(
      button: true,
      label:
          'يوم $dayNum${dayData?.status != null ? " - ${dayData!.status}" : ""}',
      child: GestureDetector(
        onTap: () => _showDayDetail(context),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isDimmed ? 0.22 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 56,
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: style.bg,
              borderRadius: BorderRadius.circular(12),
              border: isToday
                  ? Border.all(color: style.accent, width: 2.5)
                  : isHighlighted
                      ? Border.all(color: style.accent, width: 2.2)
                      : Border.all(color: style.accent.withValues(alpha: .25)),
              boxShadow: isToday || isHighlighted
                  ? [
                      BoxShadow(
                        color: style.accent.withValues(alpha: .35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // رقم اليوم — داخل دائرة ممتلئة لليوم الحالي
              if (isToday)
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.accent,
                  ),
                  child: Text(
                    '$dayNum',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                )
              else
                Text(
                  '$dayNum',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: style.fg,
                    height: 1.1,
                  ),
                ),
              const SizedBox(height: 4),
              // نقطة الحالة الملوّنة (بدل الأيقونة الصغيرة)
              if (style.dot != null)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.dot,
                  ),
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    ),
  );
  }

  /// هوية لونية موحّدة لكل حالة: خلفية فاتحة + نص داكن + لون مميّز (حدود/دائرة اليوم) + نقطة صغيرة
  ({Color bg, Color fg, Color accent, Color? dot}) _resolveStyle(
    ColorScheme scheme,
  ) {
    // أيام مستقبلية — مظلّلة بهدوء بدون أي حالة
    if (isFuture) {
      return (
        bg: scheme.surfaceContainerLow,
        fg: scheme.onSurface.withValues(alpha: .25),
        accent: scheme.surfaceContainerLow,
        dot: null,
      );
    }

    // اليوم الحالي — معالجة خاصة تمنع وسم اليوم قيد العمل كغياب غير مبرر
    if (isToday) {
      if (dayData?.status == 'حاضر') {
        final late = (dayData?.lateMinutes ?? 0) > 0;
        return (
          bg: late ? const Color(0xFFFFF9E9) : const Color(0xFFE9F7F0),
          fg: late ? const Color(0xFF9A5B00) : const Color(0xFF15734F),
          accent: late ? const Color(0xFFF59E0B) : const Color(0xFF0F9F6E),
          dot: late ? const Color(0xFFF59E0B) : const Color(0xFF0F9F6E),
        );
      }
      if (dayData?.hasLeave == true) {
        return (
          bg: const Color(0xFFEEF0FB),
          fg: const Color(0xFF3D4FA8),
          accent: const Color(0xFF4F46E5),
          dot: const Color(0xFF4F46E5),
        );
      }
      if (dayData?.hasMission == true) {
        return (
          bg: const Color(0xFFE5F6FB),
          fg: const Color(0xFF0B6B80),
          accent: const Color(0xFF0284C7),
          dot: const Color(0xFF0284C7),
        );
      }
      if (dayData?.hasConvoyFundi == true) {
        final isFundi = dayData!.status.contains('فاندي');
        return isFundi
            ? (
                bg: const Color(0xFFFDF2F8),
                fg: const Color(0xFF9D174D),
                accent: const Color(0xFFDB2777),
                dot: const Color(0xFFDB2777),
              )
            : (
                bg: const Color(0xFFF4ECF8),
                fg: const Color(0xFF6D3FA0),
                accent: const Color(0xFF7C3AED),
                dot: const Color(0xFF7C3AED),
              );
      }
      if (dayData?.status == 'راحة' || dayData?.status == 'راحة أسبوعية') {
        return (
          bg: const Color(0xFFF4F6F7),
          fg: const Color(0xFF90A0A8),
          accent: scheme.primary,
          dot: null,
        );
      }
      // اليوم لا يزال جارياً — تمييزه بلون المنظومة الأساسي الحيوي وليس بالأحمر التحذيري
      return (
        bg: scheme.primaryContainer.withValues(alpha: 0.25),
        fg: scheme.primary,
        accent: scheme.primary,
        dot: scheme.primary,
      );
    }

    if (dayData == null) {
      return (
        bg: scheme.surfaceContainerLow,
        fg: scheme.onSurfaceVariant.withValues(alpha: .5),
        accent: scheme.surfaceContainerLow,
        dot: null,
      );
    }
    final d = dayData!;
    final status = d.status;
    // غائب دون إذن — أحمر (للأيام السابقة المكتملة فقط)
    if (status == 'غائب دون إذن') {
      return (
        bg: const Color(0xFFFDECEA),
        fg: const Color(0xFFBA1A1A),
        accent: const Color(0xFFDC3D4B),
        dot: const Color(0xFFDC3D4B),
      );
    }
    // يحتاج مراجعة — كهرمان
    if (status == 'يحتاج مراجعة') {
      return (
        bg: const Color(0xFFFFF4E5),
        fg: const Color(0xFF9A5B00),
        accent: const Color(0xFFF59E0B),
        dot: const Color(0xFFF59E0B),
      );
    }
    // إجازة — نيلي
    if (d.hasLeave) {
      return (
        bg: const Color(0xFFEEF0FB),
        fg: const Color(0xFF3D4FA8),
        accent: const Color(0xFF4F46E5),
        dot: const Color(0xFF4F46E5),
      );
    }
    // مأمورية — سماوي
    if (d.hasMission) {
      return (
        bg: const Color(0xFFE5F6FB),
        fg: const Color(0xFF0B6B80),
        accent: const Color(0xFF0284C7),
        dot: const Color(0xFF0284C7),
      );
    }
    // قوافل مساعدات خارجية وفاندي ترفيهي
    if (d.hasConvoyFundi) {
      final isFundi = d.status.contains('فاندي');
      if (isFundi) {
        return (
          bg: const Color(0xFFFDF2F8),
          fg: const Color(0xFF9D174D),
          accent: const Color(0xFFDB2777),
          dot: const Color(0xFFDB2777),
        );
      }
      return (
        bg: const Color(0xFFF4ECF8),
        fg: const Color(0xFF6D3FA0),
        accent: const Color(0xFF7C3AED),
        dot: const Color(0xFF7C3AED),
      );
    }
    // عطلة رسمية — بنفسجي باهت بدون نقطة
    if (status == 'عطلة رسمية') {
      return (
        bg: const Color(0xFFF4ECF8),
        fg: const Color(0xFF8A6BB5),
        accent: const Color(0xFFDCCBEE),
        dot: null,
      );
    }
    // راحة أسبوعية — رمادي مزرقّ بدون نقطة
    if (status == 'راحة' || status == 'راحة أسبوعية') {
      return (
        bg: const Color(0xFFF4F6F7),
        fg: const Color(0xFF90A0A8),
        accent: const Color(0xFFE1E7EA),
        dot: null,
      );
    }
    // حاضر — أخضر (ومؤشر تأخير كهرماني إن وُجد)
    if (status == 'حاضر') {
      final late = d.lateMinutes > 0;
      return (
        bg: late ? const Color(0xFFFFF9E9) : const Color(0xFFE9F7F0),
        fg: late ? const Color(0xFF9A5B00) : const Color(0xFF15734F),
        accent: late ? const Color(0xFFF59E0B) : const Color(0xFF0F9F6E),
        dot: late ? const Color(0xFFF59E0B) : const Color(0xFF0F9F6E),
      );
    }
    return (
      bg: scheme.surfaceContainerHighest,
      fg: scheme.onSurfaceVariant,
      accent: scheme.outlineVariant.withValues(alpha: .4),
      dot: null,
    );
  }

  void _showDayDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DayDetailSheet(
        statement: statement,
        day: dayData,
        dayNum: dayNum,
        isFuture: isFuture,
        isToday: isToday,
        year: year,
        month: month,
      ),
    );
  }
}

// ─── ورقة تفاصيل اليوم + الإجراءات ─────────────────────────────────

