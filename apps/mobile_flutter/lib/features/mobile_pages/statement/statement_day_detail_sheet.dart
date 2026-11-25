part of '../monthly_attendance_statement_page.dart';

class _DayDetailSheet extends ConsumerWidget {
  const _DayDetailSheet({
    required this.statement,
    required this.day,
    required this.dayNum,
    required this.isFuture,
    required this.isToday,
    required this.year,
    required this.month,
  });
  final MonthlyAttendanceStatement statement;
  final AttendanceStatementDay? day;
  final int dayNum;
  final bool isFuture;
  final bool isToday;
  final int year;
  final int month;

  static const _warn = {'غائب دون إذن', 'يحتاج مراجعة'};

  String get _dateStr =>
      '$year-${month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // 0449: عرض الوقت بنظام 12 ساعة مع ص/م بدل اقتطاع HH24 الخام
    String fmt(String? t) {
      if (t == null || t.length < 5) return '—';
      final h = int.tryParse(t.substring(0, 2));
      final m = int.tryParse(t.substring(3, 5));
      if (h == null || m == null) return '—';
      final period = h < 12 ? 'ص' : 'م';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:${m.toString().padLeft(2, '0')} $period';
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // ─ المقبض ─
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ─ رأس: التاريخ + الحالة ─
            Row(
              children: [
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'اليوم',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      color: scheme.onPrimary,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    '${day?.dayNameAr ?? _dayNameFull} $_dateStr',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                MobileStatusPill(isFuture ? 'scheduled' : _statusPillKey),
              ],
            ),

            const SizedBox(height: 16),

            if (day?.hasAdminOverride == true) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF0FB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الحالة المعتمدة: ${day?.adminOverride?['dayType'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF3D4FA8),
                          ),
                          ),
                          if (cleanAttendanceNote(
                                day?.adminOverride?['reason'] as String?,
                              ) !=
                              null)
                            Text(
                              'السبب: ${cleanAttendanceNote(day!.adminOverride!['reason'] as String?)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF475569),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ─ بطاقة الحضور/الانصراف (أيام فائتة فقط) ─
            if (!isFuture && day != null) ...[
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        // حضور
                        Expanded(
                          child: Column(
                            children: [
                              const Icon(
                                Icons.login,
                                size: 20,
                                color: Color(0xFF0F9F6E),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'حضور',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                              Text(
                                fmt(day!.checkIn),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        // انصراف
                        Expanded(
                          child: Column(
                            children: [
                              Icon(
                                Icons.logout,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'انصراف',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                              Text(
                                fmt(day!.checkOut),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ساعات العمل
                        if (day!.workHours > 0) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  day!.workHours.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                Text(
                                  'ساعة',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                  textDirection: TextDirection.rtl,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ─ تفاصيل المخالفات والعلامات ─
            if (day != null && _hasDetails) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (day!.lateMinutes > 0)
                    _DetailChip(
                      icon: Icons.schedule,
                      label: 'تأخير ${day!.lateMinutes} د',
                      color: _warn.contains(day!.status)
                          ? scheme.error
                          : const Color(0xFFF59E0B),
                    ),
                  if (day!.earlyLeaveMinutes > 0)
                    _DetailChip(
                      icon: Icons.exit_to_app,
                      label: 'خروج مبكر ${day!.earlyLeaveMinutes} د',
                      color: const Color(0xFFF59E0B),
                    ),
                  if (day!.overtimeMinutes > 0)
                    _DetailChip(
                      icon: Icons.more_time,
                      label: 'إضافي ${day!.overtimeMinutes} د',
                      color: const Color(0xFF0F9F6E),
                    ),
                  if (day!.hasLeave)
                    _DetailChip(
                      icon: Icons.beach_access,
                      label: 'إجازة',
                      color: const Color(0xFF6366F1),
                    ),
                  if (day!.hasPermit)
                    _DetailChip(
                      icon: Icons.assignment_turned_in,
                      label: 'إذن',
                      color: const Color(0xFFF59E0B),
                    ),
                  if (day!.hasMission)
                    _DetailChip(
                      icon: Icons.directions_car,
                      label: 'مأمورية',
                      color: const Color(0xFF0EA5E9),
                    ),
                  if (day!.hasConvoyFundi)
                    _DetailChip(
                      icon: day!.status.contains('فاندي')
                          ? Icons.celebration
                          : Icons.volunteer_activism,
                      label: day!.status.contains('فاندي')
                          ? 'فاندي (يوم ترفيهي)'
                          : 'قافلة مساعدات (كامب)',
                      color: day!.status.contains('فاندي')
                          ? const Color(0xFFDB2777)
                          : const Color(0xFF7C3AED),
                    ),
                  if (day!.missingCheckIn)
                    _DetailChip(
                      icon: Icons.warning_amber,
                      label: 'لم يسجل حضور',
                      color: scheme.error,
                    ),
                  if (day!.missingCheckOut)
                    _DetailChip(
                      icon: Icons.warning_amber,
                      label: 'لم يسجل انصراف',
                      color: scheme.error,
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // ─ ملاحظة التصحيح ─
            if (cleanAttendanceNote(day?.correctionNote) != null) ...[
              Text(
                '📝 ${cleanAttendanceNote(day!.correctionNote)!}',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
            ],

            // ─ الإجراءات المتاحة ─
            const Divider(height: 24),
            Text(
              'الإجراءات المتاحة',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            ..._buildActions(context, ref, scheme),
          ],
        );
      },
    );
  }

  String get _statusPillKey {
    if (isToday) {
      if (day?.status == 'حاضر') return 'present';
      if (day?.hasLeave == true) return 'on_leave';
      if (day?.hasMission == true) return 'mission';
      if (day?.hasConvoyFundi == true) {
        return day!.status.contains('فاندي') ? 'fundi' : 'convoy';
      }
      if (day?.status == 'راحة' || day?.status == 'راحة أسبوعية') return 'rest';
      return 'in_progress';
    }
    if (day == null) return 'absent';
    final s = day!.status;
    if (s == 'حاضر') return 'present';
    if (s == 'غائب دون إذن') return 'absent';
    if (s == 'عطلة رسمية') return 'holiday';
    if (s == 'راحة' || s == 'راحة أسبوعية') return 'rest';
    if (s == 'يحتاج مراجعة') return 'flagged';
    if (day!.hasLeave) return 'on_leave';
    if (day!.hasMission) return 'mission';
    if (day!.hasConvoyFundi) {
      return s.contains('فاندي') ? 'fundi' : 'convoy';
    }
    return 'unregistered';
  }

  /// اسم اليوم كاملاً — من الـ backend، أو احتياطي محلي مضبوط على weekday الصحيح
  String get _dayNameFull {
    final fromServer = day?.dayNameAr.trim() ?? '';
    if (fromServer.isNotEmpty) return fromServer;
    const names = {
      1: 'الاثنين',
      2: 'الثلاثاء',
      3: 'الأربعاء',
      4: 'الخميس',
      5: 'الجمعة',
      6: 'السبت',
      7: 'الأحد',
    };
    return names[DateTime(year, month, dayNum).weekday] ?? '';
  }

  bool get _hasDetails =>
      day != null &&
      (day!.lateMinutes > 0 ||
          day!.earlyLeaveMinutes > 0 ||
          day!.overtimeMinutes > 0 ||
          day!.hasLeave ||
          day!.hasPermit ||
          day!.hasMission ||
          day!.hasConvoyFundi ||
          day!.missingCheckIn ||
          day!.missingCheckOut);

}
