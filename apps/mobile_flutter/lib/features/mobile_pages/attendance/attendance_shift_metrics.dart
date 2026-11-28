part of '../mobile_attendance_page.dart';

// Compare the displayed Cairo clock with the scheduled wall-clock times.
DateTime _shiftClock(DateTime cairoTime) => DateTime.utc(
  cairoTime.year,
  cairoTime.month,
  cairoTime.day,
  cairoTime.hour,
  cairoTime.minute,
  cairoTime.second,
);

class _ShiftLiveStatus {
  const _ShiftLiveStatus({
    required this.statusLabel,
    required this.detailLabel,
    required this.color,
    required this.icon,
    this.progress,
    this.isGraceActive = false,
  });

  final String statusLabel;
  final String detailLabel;
  final Color color;
  final IconData icon;
  final double? progress;
  final bool isGraceActive;
}

_ShiftLiveStatus _computeShiftLiveStatus({
  required String startTime,
  required String endTime,
  required int graceInMinutes,
  bool hasPermit = false,
  String? permitActiveStartTime,
  DateTime? now,
}) {
  final current = _shiftClock(now ?? AppTime.now());
  final effectiveStart = hasPermit && permitActiveStartTime != null ? permitActiveStartTime : startTime;
  final startParts = effectiveStart.split(':');
  final endParts = endTime.split(':');
  if (startParts.length < 2 || endParts.length < 2) {
    return const _ShiftLiveStatus(
      statusLabel: 'فترة العمل المعتمدة',
      detailLabel: 'وفق الجدول المحدد',
      color: Color(0xFF2563EB),
      icon: Icons.schedule_rounded,
    );
  }
  final startH = int.tryParse(startParts[0]) ?? 10;
  final startM = int.tryParse(startParts[1]) ?? 0;
  final endH = int.tryParse(endParts[0]) ?? 18;
  final endM = int.tryParse(endParts[1]) ?? 0;

  final todayStart = DateTime.utc(current.year, current.month, current.day, startH, startM);
  final todayGraceEnd = todayStart.add(Duration(minutes: graceInMinutes));
  final todayEnd = DateTime.utc(current.year, current.month, current.day, endH, endM);

  if (current.isBefore(todayStart)) {
    final diff = todayStart.difference(current);
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    final timeText = hours > 0 ? '$hours ساعة و$mins دقيقة' : '$mins دقيقة';
    return _ShiftLiveStatus(
      statusLabel: hasPermit ? 'إذن حضور سارٍ حالياً' : 'الدوام لم يبدأ بعد',
      detailLabel: hasPermit
          ? 'يبدأ الحضور المصرح بعد $timeText (وفق الإذن المعتمد)'
          : 'يبدأ حضور الوردية بعد $timeText',
      color: hasPermit ? const Color(0xFFD97706) : const Color(0xFF0284C7),
      icon: hasPermit ? Icons.verified_user_rounded : Icons.access_time_rounded,
    );
  } else if (current.isBefore(todayGraceEnd)) {
    final diff = todayGraceEnd.difference(current);
    final mins = diff.inMinutes;
    return _ShiftLiveStatus(
      statusLabel: 'فترة السماح نشطة حالياً',
      detailLabel: hasPermit
          ? 'متبقي $mins دقيقة قبل احتساب التأخير بعد الإذن'
          : 'متبقي $mins دقيقة قبل احتساب التأخير الفردي',
      color: AppColors.statusWarning,
      icon: Icons.hourglass_top_rounded,
      isGraceActive: true,
      progress: 0.08,
    );
  } else if (current.isBefore(todayEnd)) {
    final totalDuration = todayEnd.difference(todayStart).inMinutes;
    final elapsed = current.difference(todayStart).inMinutes;
    final progress = totalDuration > 0 ? (elapsed / totalDuration).clamp(0.0, 1.0) : 0.5;
    final diff = todayEnd.difference(current);
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    final timeText = hours > 0 ? '$hours ساعة و$mins دقيقة' : '$mins دقيقة';
    return _ShiftLiveStatus(
      statusLabel: 'ساعات العمل الرسمية جارية',
      detailLabel: 'متبقي حتى نهاية الوردية: $timeText',
      color: AppColors.statusSuccess,
      icon: Icons.work_history_rounded,
      progress: progress,
    );
  } else {
    return const _ShiftLiveStatus(
      statusLabel: 'انتهت ساعات الوردية لليوم',
      detailLabel: 'اكتملت ساعات الدوام المقررة رسمياً',
      color: Color(0xFF059669),
      icon: Icons.task_alt_rounded,
      progress: 1.0,
    );
  }
}

class _ShiftDisciplineMetric {
  const _ShiftDisciplineMetric({
    required this.statusTitle,
    required this.statusSubtitle,
    required this.badgeLabel,
    required this.color,
    required this.icon,
    required this.isDeductionRisk,
    this.consumedGraceMinutes,
    this.lateMinutes,
  });

  final String statusTitle;
  final String statusSubtitle;
  final String badgeLabel;
  final Color color;
  final IconData icon;
  final bool isDeductionRisk;
  final int? consumedGraceMinutes;
  final int? lateMinutes;
}

_ShiftDisciplineMetric _computeShiftDisciplineMetric({
  required String startTime,
  required int graceInMinutes,
  required DateTime? todayCheckInAt,
  DateTime? todayCheckOutAt,
  int? workMinutes,
  bool hasPermit = false,
  int? permitMinutes,
  String? originalStartTime,
  DateTime? now,
}) {
  final currentTime = now ?? AppTime.now();
  final current = _shiftClock(currentTime);
  final startParts = startTime.split(':');
  final startH = startParts.length >= 2 ? (int.tryParse(startParts[0]) ?? 10) : 10;
  final startM = startParts.length >= 2 ? (int.tryParse(startParts[1]) ?? 0) : 0;

  final referenceDate = AppTime.tryToCairo(todayCheckInAt) ?? current;
  var todayStart = DateTime.utc(referenceDate.year, referenceDate.month, referenceDate.day, startH, startM);

  // إذا كان الموظف لديه إذن معتمد/قيد المراجعة ولم يكن توقيت البداية قد عُدّل بالفعل، يتم إضافة دقائق الإذن
  if (hasPermit && permitMinutes != null && permitMinutes > 0 && originalStartTime != null && startTime == originalStartTime) {
    todayStart = todayStart.add(Duration(minutes: permitMinutes));
  }

  final todayGraceEnd = todayStart.add(Duration(minutes: graceInMinutes));

  if (todayCheckInAt != null) {
    final checkIn = _shiftClock(referenceDate);

    // فحص ما إذا كان الموظف قد استوفى 8 ساعات عمل (480 دقيقة)
    final totalWorkMins = (workMinutes != null && workMinutes > 0)
        ? workMinutes
        : (todayCheckOutAt ?? currentTime).difference(todayCheckInAt).inMinutes;

    if (totalWorkMins >= 480) {
      final overtimeMins = totalWorkMins > 480 ? totalWorkMins - 480 : 0;
      return _ShiftDisciplineMetric(
        statusTitle: overtimeMins > 0
            ? 'تم استيفاء 8 ساعات عمل وزيادة $overtimeMins دقيقة وقت إضافي ✓'
            : 'تم استيفاء ساعات العمل الرسمية كاملة (8 ساعات) ✓',
        statusSubtitle: overtimeMins > 0
            ? 'أتم الموظف الـ 8 ساعات وزاد $overtimeMins دقيقة وقت إضافي · زال التأخير ويُصرف الإضافي'
            : 'أتم الموظف 8 ساعات عمل كاملة وعوّض أي تأخير سابق · لا يُطبق أي خصم',
        badgeLabel: overtimeMins > 0
            ? 'مستوفٍ +$overtimeMins د إضافي ✓'
            : 'مستوفٍ لـ 8 ساعات ✓',
        color: AppColors.statusSuccess,
        icon: Icons.check_circle_rounded,
        isDeductionRisk: false,
        lateMinutes: 0,
        consumedGraceMinutes: 0,
      );
    }
    if (checkIn.isBefore(todayStart) || checkIn.isAtSameMomentAs(todayStart)) {
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit ? 'حضور منضبط مع الإذن المعتمد ✓' : 'حضور مبكر ومنضبط تماماً ✓',
        statusSubtitle: hasPermit
            ? 'سُجل الحضور في موعد الإذن المصرح به · 0 دقيقة تأخير و 0 خصومات فردية'
            : 'سُجل الحضور في موعد الوردية الرسمي · 0 دقيقة تأخير و 0 خصومات فردية',
        badgeLabel: 'منضبط 100%',
        color: AppColors.statusSuccess,
        icon: Icons.verified_rounded,
        isDeductionRisk: false,
        lateMinutes: 0,
        consumedGraceMinutes: 0,
      );
    } else if (checkIn.isBefore(todayGraceEnd) || checkIn.isAtSameMomentAs(todayGraceEnd)) {
      final consumed = checkIn.difference(todayStart).inMinutes;
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit
            ? 'حضور ضمن فترة السماح للإذن ($consumed دقيقة)'
            : 'حضور ضمن فترة السماح ($consumed دقيقة)',
        statusSubtitle: hasPermit
            ? 'سُجل الحضور في نطاق سماح الإذن المعتمد ($graceInMinutes د) · لا يُحتسب أي خصم أو تأخير مالي'
            : 'سُجل الحضور في نطاق السماح المعتمد ($graceInMinutes د) · لا يُحتسب أي خصم أو تأخير مالي',
        badgeLabel: 'سماح معتمد',
        color: const Color(0xFFD97706),
        icon: Icons.shield_outlined,
        isDeductionRisk: false,
        consumedGraceMinutes: consumed,
        lateMinutes: 0,
      );
    } else {
      final lateMins = checkIn.difference(todayStart).inMinutes;
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit
            ? 'تأخير بعد انتهاء الإذن: $lateMins دقيقة'
            : 'تأخير فردي مسجل: $lateMins دقيقة',
        statusSubtitle: hasPermit
            ? 'تم تجاوز موعد الإذن المعتمد ($startTime) وفترة السماح ($graceInMinutes د) · يُطبق الخصم الفردي من الموعد المصرح'
            : 'تم استنفاد فترة السماح ($graceInMinutes د) · يُطبق الخصم الفردي من موعد الوردية وفق لائحة العمل',
        badgeLabel: hasPermit ? 'تأخير بعد الإذن' : 'تأخير مسجل',
        color: const Color(0xFFDC2626),
        icon: Icons.warning_amber_rounded,
        isDeductionRisk: true,
        lateMinutes: lateMins,
      );
    }
  } else {
    if (current.isBefore(todayStart)) {
      final diff = todayStart.difference(current);
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      final timeStr = hours > 0 ? '$hours ساعة و$mins دقيقة' : '$mins دقيقة';
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit
            ? 'إذن حضور سارٍ · يبدأ الحضور بعد $timeStr'
            : 'الدوام لم يبدأ بعد · يبدأ بعد $timeStr',
        statusSubtitle: hasPermit
            ? 'لديك إذن حضور معتمد (\u200E+${permitMinutes ?? 120} د) · موعدك المصرح حتى $startTime (سماح $graceInMinutes د)'
            : 'سجل حضورك في الموعد المعتمد للاستفادة من فترة السماح وضمان انضباط تام دون خصومات',
        badgeLabel: hasPermit ? 'إذن سارٍ' : 'بانتظار البدء',
        color: hasPermit ? const Color(0xFFD97706) : const Color(0xFF0284C7),
        icon: hasPermit ? Icons.verified_user_rounded : Icons.schedule_rounded,
        isDeductionRisk: false,
      );
    } else if (current.isBefore(todayGraceEnd)) {
      final remaining = todayGraceEnd.difference(current).inMinutes;
      return _ShiftDisciplineMetric(
        statusTitle: 'فترة السماح نشطة حالياً · متبقي $remaining دقيقة',
        statusSubtitle: hasPermit
            ? 'سارع بتسجيل الحضور للاستفادة من رصيد السماح بعد الإذن المعتمد وتفادي الخصم الفردي'
            : 'سارع بتسجيل الحضور الآن للاستفادة من رصيد السماح وتفادي احتساب التأخير الفردي',
        badgeLabel: 'سماح جارٍ',
        color: const Color(0xFFD97706),
        icon: Icons.hourglass_top_rounded,
        isDeductionRisk: false,
        consumedGraceMinutes: graceInMinutes - remaining,
      );
    } else {
      final lateSoFar = current.difference(todayStart).inMinutes;
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit
            ? 'تأخير بعد الإذن: $lateSoFar دقيقة'
            : 'تأخير غير مسجل: $lateSoFar دقيقة عن الوردية',
        statusSubtitle: hasPermit
            ? 'تم استنفاد فترة السماح بعد الإذن المعتمد · سارع بتسجيل الحضور للحد من دقائق الخصم الفردي'
            : 'تم استنفاد فترة السماح ($graceInMinutes د) · سارع بتسجيل الحضور للحد من دقائق الخصم الفردي',
        badgeLabel: hasPermit ? 'تأخير بعد الإذن' : 'تأخير جارٍ',
        color: const Color(0xFFDC2626),
        icon: Icons.alarm_on_rounded,
        isDeductionRisk: true,
        lateMinutes: lateSoFar,
      );
    }
  }
}

IconData _getShiftIcon(String code) {
  switch (code.toUpperCase()) {
    case 'SHIFT_9_5':
      return Icons.wb_sunny_rounded;
    case 'SHIFT_11_7':
      return Icons.nights_stay_rounded;
    case 'SHIFT_CLINIC_3_11':
      return Icons.medical_services_outlined;
    case 'OFFICIAL':
    default:
      return Icons.business_center_rounded;
  }
}

Color _getShiftColor(String code, ColorScheme scheme) {
  switch (code.toUpperCase()) {
    case 'SHIFT_9_5':
      return const Color(0xFFD97706);
    case 'SHIFT_11_7':
      return const Color(0xFF7C3AED);
    case 'SHIFT_CLINIC_3_11':
      return const Color(0xFF0D9488);
    case 'OFFICIAL':
    default:
      return scheme.primary;
  }
}

/// نافذة سفلية سلسة لاختيار وتغيير فترة العمل والتنقل بين الورديات
