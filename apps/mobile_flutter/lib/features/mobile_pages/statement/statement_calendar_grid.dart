part of '../monthly_attendance_statement_page.dart';

class _MonthlyCalendarGrid extends StatefulWidget {
  const _MonthlyCalendarGrid({
    required this.statement,
    required this.days,
    required this.year,
    required this.month,
  });
  final MonthlyAttendanceStatement statement;
  final List<AttendanceStatementDay> days;
  final int year;
  final int month;

  @override
  State<_MonthlyCalendarGrid> createState() => _MonthlyCalendarGridState();
}

class _MonthlyCalendarGridState extends State<_MonthlyCalendarGrid> {
  String _activeFilter = 'all';

  static const _weekDayHeaders = [
    'سبت',
    'أحد',
    'إثنين',
    'ثلاثاء',
    'أربعاء',
    'خميس',
    'جمعة',
  ];

  bool _matchesFilter(AttendanceStatementDay? d, String filter) {
    if (filter == 'all') return true;
    if (d == null) return filter == 'absent';
    switch (filter) {
      case 'present':
        return d.status == 'حاضر';
      case 'absent':
        return d.status == 'غائب دون إذن' || d.isAbsent;
      case 'convoy':
        return (d.status.contains('قافلة') || d.hasConvoyFundi) &&
            !d.status.contains('فاندي');
      case 'fundi':
        return d.status.contains('فاندي');
      case 'mission':
        return d.hasMission || d.status.contains('مأمورية');
      case 'leave':
        return d.hasLeave || d.status.contains('إجازة');
      case 'missing':
        return d.missingCheckIn || d.missingCheckOut;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final isCurrentMonth =
        today.year == widget.year && today.month == widget.month;

    // بناء خريطة الأيام (رقم اليوم → بيانات اليوم)
    final dayMap = <int, AttendanceStatementDay>{};
    for (final d in widget.days) {
      final parsed = DateTime.tryParse(d.date);
      if (parsed != null) dayMap[parsed.day] = d;
    }

    final firstOfMonth = DateTime(widget.year, widget.month, 1);
    final daysInMonth = DateTime(widget.year, widget.month + 1, 0).day;
    final firstWeekdayCol = (firstOfMonth.weekday + 1) % 7;
    final totalCells = firstWeekdayCol + daysInMonth;
    final rows = (totalCells / 7).ceil();

    final s = widget.statement.summary;
    final missingPunches = s.missingCheckInCount + s.missingCheckOutCount;
    final convoyCount = widget.days
        .where(
          (d) =>
              (d.status.contains('قافلة') || d.hasConvoyFundi) &&
              !d.status.contains('فاندي'),
        )
        .length;
    final fundiCount = widget.days
        .where((d) => d.status.contains('فاندي'))
        .length;
    final cCount = widget.days.isNotEmpty ? convoyCount : s.convoyFundiDays;
    final fCount = widget.days.isNotEmpty ? fundiCount : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─ شريط الفلترة السريع لأيام الشهر ─
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChipButton(
                label: 'الكل',
                count: widget.statement.days.length,
                isSelected: _activeFilter == 'all',
                onTap: () => setState(() => _activeFilter = 'all'),
              ),
              _FilterChipButton(
                label: 'حضور',
                count: s.presentDays,
                color: const Color(0xFF0F9F6E),
                isSelected: _activeFilter == 'present',
                onTap: () => setState(() => _activeFilter = 'present'),
              ),
              _FilterChipButton(
                label: 'غياب',
                count: s.absentDays,
                color: const Color(0xFFDC2626),
                isSelected: _activeFilter == 'absent',
                onTap: () => setState(() => _activeFilter = 'absent'),
              ),
              _FilterChipButton(
                label: 'قوافل',
                count: cCount,
                color: const Color(0xFF7C3AED),
                isSelected: _activeFilter == 'convoy',
                onTap: () => setState(() => _activeFilter = 'convoy'),
              ),
              _FilterChipButton(
                label: 'فاندي (ترفيهي)',
                count: fCount,
                color: const Color(0xFFDB2777),
                isSelected: _activeFilter == 'fundi',
                onTap: () => setState(() => _activeFilter == 'fundi'),
              ),
              _FilterChipButton(
                label: 'مأموريات',
                count: s.missionDays,
                color: const Color(0xFF0284C7),
                isSelected: _activeFilter == 'mission',
                onTap: () => setState(() => _activeFilter = 'mission'),
              ),
              _FilterChipButton(
                label: 'إجازات',
                count: s.leaveDays,
                color: const Color(0xFF4F46E5),
                isSelected: _activeFilter == 'leave',
                onTap: () => setState(() => _activeFilter = 'leave'),
              ),
              if (missingPunches > 0)
                _FilterChipButton(
                  label: 'نقص بصمة',
                  count: missingPunches,
                  color: const Color(0xFFD97706),
                  isSelected: _activeFilter == 'missing',
                  onTap: () => setState(() => _activeFilter = 'missing'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                // ─ رأس الأسبوع ─
                Row(
                  children: _weekDayHeaders
                      .map(
                        (h) => Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                h,
                                style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                      ),
                    ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                // ─ صفوف الأيام ─
                ...List.generate(rows, (row) {
                  final prevMonthDays = DateTime(
                    widget.year,
                    widget.month,
                    0,
                  ).day;
                  return Row(
                    children: List.generate(7, (col) {
                      final cellIndex = row * 7 + col;
                      final dayNum = cellIndex - firstWeekdayCol + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        final adjacentDay = dayNum < 1
                            ? prevMonthDays + dayNum
                            : dayNum - daysInMonth;
                        return Expanded(
                          child: Container(
                            height: 56,
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLowest.withValues(
                                alpha: 0.25,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$adjacentDay',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface.withValues(alpha: 0.18),
                              ),
                            ),
                          ),
                        );
                      }
                      final dayData = dayMap[dayNum];
                      final isToday = isCurrentMonth && today.day == dayNum;
                      final dayDate = DateTime(
                        widget.year,
                        widget.month,
                        dayNum,
                      );
                      final isFuture = dayDate.isAfter(
                        DateTime(today.year, today.month, today.day),
                      );
                      final matches = _matchesFilter(dayData, _activeFilter);
                      final isDimmed = _activeFilter != 'all' && !matches;

                      return Expanded(
                        child: _CalendarDayCell(
                          statement: widget.statement,
                          dayNum: dayNum,
                          dayData: dayData,
                          isToday: isToday,
                          isFuture: isFuture,
                          year: widget.year,
                          month: widget.month,
                          isDimmed: isDimmed,
                          isHighlighted: _activeFilter != 'all' && matches,
                        ),
                      );
                    }),
                  );
                }),
              ],
            ),
          ),
        ),
        if (_activeFilter != 'all') ...[
          const SizedBox(height: 8),
          Center(
            child: ActionChip(
              avatar: const Icon(Icons.close_rounded, size: 16),
              label: Text(
                'إلغاء التصفية (عرض الكل)',
                style: TextStyle(fontSize: 11, color: scheme.primary),
              ),
              onPressed: () => setState(() => _activeFilter = 'all'),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── خلية يوم في التقويم ────────────────────────────────────────────

