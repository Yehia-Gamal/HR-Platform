import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:intl/intl.dart';

/// فئات الفلترة المتاحة — تُطابق حالات الحضور.
enum _FilterCategory { all, present, late, absent, mission, onLeave, partial, weekend }

/// تبويب الحضور اليومي — يعرض حالة كل موظف اليوم للمدير التنفيذي
/// مع شرائح قابلة للنقر للفلترة + بحث فوري.
class ExecutiveAttendanceTab extends ConsumerStatefulWidget {
  const ExecutiveAttendanceTab({super.key});

  @override
  ConsumerState<ExecutiveAttendanceTab> createState() =>
      _ExecutiveAttendanceTabState();
}

class _ExecutiveAttendanceTabState
    extends ConsumerState<ExecutiveAttendanceTab> {
  _FilterCategory _selectedFilter = _FilterCategory.all;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// يُرجع مفتاح الفلترة المناسب لكل موظف.
  _FilterCategory _employeeCategory(AttendanceTodayEmployee e) {
    if (e.isOnMission) return _FilterCategory.mission;
    return switch (e.attendanceStatus) {
      'present' => _FilterCategory.present,
      'late' => _FilterCategory.late,
      'absent' => _FilterCategory.absent,
      'on_leave' => _FilterCategory.onLeave,
      'partial' => _FilterCategory.partial,
      'weekend' => _FilterCategory.weekend,
      _ => _FilterCategory.absent,
    };
  }

  /// يفلتر القائمة حسب الفئة المحددة + البحث.
  List<AttendanceTodayEmployee> _applyFilters(
    List<AttendanceTodayEmployee> employees,
  ) {
    var result = employees;
    if (_selectedFilter != _FilterCategory.all) {
      result = result
          .where((e) => _employeeCategory(e) == _selectedFilter)
          .toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      result = result.where((e) {
        final name = e.name.toLowerCase();
        final code = (e.employeeCode ?? '').toLowerCase();
        final dept = (e.department ?? '').toLowerCase();
        return name.contains(q) || code.contains(q) || dept.contains(q);
      }).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(executiveAttendanceTodayProvider);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(executiveAttendanceTodayProvider),
        child: query.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 40,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 12),
                const Text('تعذر تحميل بيانات الحضور',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () =>
                      ref.invalidate(executiveAttendanceTodayProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: (employees) {
            if (employees.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.people_outline_rounded,
                            size: 48,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        const Text('لا يوجد موظفون نشطون'),
                      ],
                    ),
                  ),
                ],
              );
            }

            // حساب الأعداد لكل فئة
            final counts = <_FilterCategory, int>{};
            for (final e in employees) {
              final cat = _employeeCategory(e);
              counts[cat] = (counts[cat] ?? 0) + 1;
            }

            // نسبة الحضور
            final presentCount = counts[_FilterCategory.present] ?? 0;
            final lateCount = counts[_FilterCategory.late] ?? 0;
            final attendancePct = employees.isNotEmpty
                ? ((presentCount + lateCount) / employees.length * 100).round()
                : 0;

            // تطبيق الفلترة
            final filtered = _applyFilters(employees);

            // تجميع النتائج المفلترة حسب القسم
            final grouped = <String, List<AttendanceTodayEmployee>>{};
            for (final emp in filtered) {
              final dept = emp.department?.isNotEmpty == true
                  ? emp.department!
                  : 'بدون قسم';
              (grouped[dept] ??= []).add(emp);
            }
            final sortedDepts = grouped.keys.toList()
              ..sort((a, b) {
                if (a == 'بدون قسم') return 1;
                if (b == 'بدون قسم') return -1;
                return a.compareTo(b);
              });

            final bottomPad = MediaQuery.of(context).padding.bottom;
            final scheme = Theme.of(context).colorScheme;

            // بناء قائمة العناصر المسطّحة
            final items = <Widget>[
              // ─── شريط نسبة الحضور البصري ──────────────────────────────
              _AttendanceProgress(
                present: presentCount,
                late: lateCount,
                absent: counts[_FilterCategory.absent] ?? 0,
                mission: counts[_FilterCategory.mission] ?? 0,
                onLeave: counts[_FilterCategory.onLeave] ?? 0,
                weekend: counts[_FilterCategory.weekend] ?? 0,
                total: employees.length,
                pct: attendancePct,
                onSegmentTap: (cat) => setState(() => _selectedFilter = cat),
              ),
              const SizedBox(height: 12),

              // ─── شريط الملخص القابل للنقر ───────────────────────────
              _SummaryBar(
                counts: counts,
                total: employees.length,
                selected: _selectedFilter,
                onTap: (cat) => setState(() => _selectedFilter = cat),
              ),
              const SizedBox(height: 12),

              // ─── شريط البحث ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو الكود أو القسم...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: scheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: scheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: scheme.primary, width: 2),
                    ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(height: 12),

              // ─── عدد النتائج أو حالة فارغة ────────────────────────────
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.filter_alt_off_outlined,
                            size: 40,
                            color: scheme.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text(
                          'لا يوجد موظفون في هذه الفئة',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _selectedFilter = _FilterCategory.all;
                              _searchQuery = '';
                            });
                          },
                          child: const Text('إظهار الكل'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${filtered.length} موظف'
                    '${_selectedFilter != _FilterCategory.all ? ' في فئة «${_filterLabel(_selectedFilter)}»' : ''}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              const SizedBox(height: 8),
            ];

            // أقسام + بطاقات
            for (final dept in sortedDepts) {
              final deptEmployees = grouped[dept]!;

              int present = 0, late = 0, absent = 0, weekend = 0;
              for (final e in deptEmployees) {
                if (e.isOnMission) continue;
                if (e.attendanceStatus == 'present') present++;
                if (e.attendanceStatus == 'late') late++;
                if (e.attendanceStatus == 'absent') absent++;
                if (e.attendanceStatus == 'weekend') weekend++;
              }
              final summaryParts = <String>[];
              if (present > 0) summaryParts.add('$present حاضر');
              if (late > 0) summaryParts.add('$late متأخر');
              if (absent > 0) summaryParts.add('$absent غائب');
              if (weekend > 0) summaryParts.add('$weekend راحة');

              items.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Row(
                    children: [
                      Icon(Icons.business_rounded,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dept,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        summaryParts.isNotEmpty
                            ? '${deptEmployees.length} موظف — ${summaryParts.join(' · ')}'
                            : '${deptEmployees.length} موظف',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              );

              for (final e in deptEmployees) {
                items.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AttendanceCard(employee: e),
                  ),
                );
              }
            }

            return ListView(
              padding: EdgeInsets.fromLTRB(0, 16, 0, 16 + bottomPad),
              children: items,
            );
          },
        ),
      ),
    );
  }
}

String _filterLabel(_FilterCategory cat) {
  return switch (cat) {
    _FilterCategory.all => 'الكل',
    _FilterCategory.present => 'حاضرون',
    _FilterCategory.late => 'متأخرون',
    _FilterCategory.absent => 'غائبون',
    _FilterCategory.mission => 'مأموريات',
    _FilterCategory.onLeave => 'إجازات',
    _FilterCategory.partial => 'جزئي',
    _FilterCategory.weekend => 'راحة أسبوعية',
  };
}

/// شريط بصري علوي يعرض نسبة الحضور بألوان مميزة قابلة للنقر.
class _AttendanceProgress extends StatelessWidget {
  const _AttendanceProgress({
    required this.present,
    required this.late,
    required this.absent,
    required this.mission,
    required this.onLeave,
    required this.weekend,
    required this.total,
    required this.pct,
    required this.onSegmentTap,
  });
  final int present;
  final int late;
  final int absent;
  final int mission;
  final int onLeave;
  final int weekend;
  final int total;
  final int pct;
  final ValueChanged<_FilterCategory> onSegmentTap;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    final segments = <_SegmentData>[
      _SegmentData(_FilterCategory.present, present, Colors.green.shade600),
      _SegmentData(_FilterCategory.late, late, Colors.orange.shade600),
      _SegmentData(_FilterCategory.mission, mission, Colors.purple.shade600),
      _SegmentData(_FilterCategory.onLeave, onLeave, Colors.blue.shade600),
      _SegmentData(_FilterCategory.weekend, weekend, Colors.teal.shade400),
      _SegmentData(_FilterCategory.absent, absent, Colors.red.shade400),
    ].where((s) => s.count > 0).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // النسبة المئوية + العدد
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'نسبة الحضور',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                '$pct%  ($present + $late من $total)',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // شريط التقدم متعدد الألوان
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 28,
              child: Row(
                children: segments.map((s) {
                  final flex = (s.count / total * 100).round();
                  return Expanded(
                    flex: flex > 0 ? flex : 1,
                    child: GestureDetector(
                      onTap: () => onSegmentTap(s.category),
                      child: Container(
                        color: s.color,
                        alignment: Alignment.center,
                        child: s.count > 2
                            ? Text(
                                '${s.count}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentData {
  const _SegmentData(this.category, this.count, this.color);
  final _FilterCategory category;
  final int count;
  final Color color;
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.counts,
    required this.total,
    required this.selected,
    required this.onTap,
  });
  final Map<_FilterCategory, int> counts;
  final int total;
  final _FilterCategory selected;
  final ValueChanged<_FilterCategory> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _SummaryChip(
            label: 'الكل',
            count: total,
            color: Theme.of(context).colorScheme.outline,
            isActive: selected == _FilterCategory.all,
            onTap: () => onTap(_FilterCategory.all),
          ),
          if ((counts[_FilterCategory.present] ?? 0) > 0)
            _SummaryChip(
              label: 'حضر',
              count: counts[_FilterCategory.present]!,
              color: Colors.green.shade700,
              isActive: selected == _FilterCategory.present,
              onTap: () => onTap(_FilterCategory.present),
            ),
          if ((counts[_FilterCategory.late] ?? 0) > 0)
            _SummaryChip(
              label: 'متأخر',
              count: counts[_FilterCategory.late]!,
              color: Colors.orange.shade700,
              isActive: selected == _FilterCategory.late,
              onTap: () => onTap(_FilterCategory.late),
            ),
          if ((counts[_FilterCategory.absent] ?? 0) > 0)
            _SummaryChip(
              label: 'غائب',
              count: counts[_FilterCategory.absent]!,
              color: Colors.red.shade700,
              isActive: selected == _FilterCategory.absent,
              onTap: () => onTap(_FilterCategory.absent),
            ),
          if ((counts[_FilterCategory.mission] ?? 0) > 0)
            _SummaryChip(
              label: 'مأمورية',
              count: counts[_FilterCategory.mission]!,
              color: Colors.purple.shade700,
              isActive: selected == _FilterCategory.mission,
              onTap: () => onTap(_FilterCategory.mission),
            ),
          if ((counts[_FilterCategory.onLeave] ?? 0) > 0)
            _SummaryChip(
              label: 'إجازة',
              count: counts[_FilterCategory.onLeave]!,
              color: Colors.blue.shade700,
              isActive: selected == _FilterCategory.onLeave,
              onTap: () => onTap(_FilterCategory.onLeave),
            ),
          if ((counts[_FilterCategory.partial] ?? 0) > 0)
            _SummaryChip(
              label: 'جزئي',
              count: counts[_FilterCategory.partial]!,
              color: Colors.amber.shade700,
              isActive: selected == _FilterCategory.partial,
              onTap: () => onTap(_FilterCategory.partial),
            ),
          if ((counts[_FilterCategory.weekend] ?? 0) > 0)
            _SummaryChip(
              label: 'راحة',
              count: counts[_FilterCategory.weekend]!,
              color: Colors.teal.shade700,
              isActive: selected == _FilterCategory.weekend,
              onTap: () => onTap(_FilterCategory.weekend),
            ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
    required this.isActive,
    required this.onTap,
  });
  final String label;
  final int count;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? color : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.3),
              width: isActive ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: isActive ? Colors.white : color,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.employee});
  final AttendanceTodayEmployee employee;

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusIcon) = _statusVisuals(employee);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shadowColor: statusColor.withValues(alpha: 0.2),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: () => _showEmployeeSummary(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppAvatar(
                    name: employee.name,
                    photoUrl: employee.photoUrl,
                    radius: 22,
                  ),
                  PositionedDirectional(
                    bottom: -2,
                    start: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Icon(statusIcon, color: Colors.white, size: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    Text(
                      [
                        employee.jobTitle,
                        employee.department,
                      ].whereType<String>().join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    _buildDetails(context),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  employee.statusAr,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmployeeSummary(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EmployeeSummarySheet(employee: employee),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final parts = <String>[];
    // §2 — اعرض سياقًا واضحًا لكل حالة حتى لو لم يُسجّل حضورًا، بدل
    // بطاقة فارغة لا تُظهر شيئًا للمدير التنفيذي.
    if (employee.isOnMission) {
      parts.add('في مأمورية خارجية');
    } else {
      switch (employee.attendanceStatus) {
        case 'present':
        case 'late':
          if (employee.firstCheckIn != null) {
            parts.add(
              'دخول ${DateFormat('h:mm a', 'ar').format(employee.firstCheckIn!.toLocal())}',
            );
          }
          if (employee.lateMinutes > 0) {
            parts.add('تأخر ${employee.lateMinutes} د');
          }
          if (employee.lastCheckOut != null) {
            parts.add(
              'خروج ${DateFormat('h:mm a', 'ar').format(employee.lastCheckOut!.toLocal())}',
            );
          }
          break;
        case 'on_leave':
          parts.add('في إجازة معتمدة');
          break;
        case 'weekend':
          parts.add('يوم راحة أسبوعية');
          break;
        case 'holiday':
          parts.add('عطلة رسمية');
          break;
        case 'partial':
          parts.add('حضور جزئي');
          break;
        case 'absent':
        default:
          parts.add('لم يُسجّل حضورًا اليوم');
          break;
      }
    }
    if (employee.lastRecordedAt != null &&
        (employee.attendanceStatus == 'present' ||
            employee.attendanceStatus == 'late')) {
      parts.add(
        'آخر موقع ${DateFormat('h:mm a', 'ar').format(employee.lastRecordedAt!.toLocal())}',
      );
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

(Color, IconData) _statusVisuals(AttendanceTodayEmployee e) {
  if (e.isOnMission) {
    return (Colors.purple.shade700, Icons.directions_car_rounded);
  }
  return switch (e.attendanceStatus) {
    'present' => (Colors.green.shade700, Icons.check_circle_outline_rounded),
    'late' => (Colors.orange.shade700, Icons.schedule_rounded),
    'absent' => (Colors.red.shade700, Icons.cancel_outlined),
    'on_leave' => (Colors.blue.shade700, Icons.beach_access_rounded),
    'holiday' => (Colors.grey.shade600, Icons.celebration_rounded),
    'weekend' => (Colors.grey.shade600, Icons.weekend_rounded),
    'partial' => (Colors.amber.shade700, Icons.timelapse_rounded),
    'pending' => (Colors.yellow.shade700, Icons.hourglass_empty_rounded),
    _ => (Colors.grey.shade500, Icons.help_outline_rounded),
  };
}

/// ورقة ملخص تفصيلي لموظف من قائمة الحضور التنفيذية.
class _EmployeeSummarySheet extends StatelessWidget {
  const _EmployeeSummarySheet({required this.employee});
  final AttendanceTodayEmployee employee;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (statusColor, _) = _statusVisuals(employee);
    final f = DateFormat('h:mm a', 'ar');
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppAvatar(
                  name: employee.name,
                  photoUrl: employee.photoUrl,
                  radius: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (employee.employeeCode != null)
                        Text(
                          employee.employeeCode!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    employee.statusAr,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _detailRow(
              context,
              icon: Icons.business_rounded,
              label: 'القسم',
              value: employee.department ?? '—',
            ),
            _detailRow(
              context,
              icon: Icons.work_outline_rounded,
              label: 'المسمى الوظيفي',
              value: employee.jobTitle ?? '—',
            ),
            _detailRow(
              context,
              icon: Icons.login_rounded,
              label: 'وقت الدخول',
              value: employee.firstCheckIn != null
                  ? f.format(employee.firstCheckIn!.toLocal())
                  : '—',
            ),
            _detailRow(
              context,
              icon: Icons.logout_rounded,
              label: 'وقت الخروج',
              value: employee.lastCheckOut != null
                  ? f.format(employee.lastCheckOut!.toLocal())
                  : '—',
            ),
            _detailRow(
              context,
              icon: Icons.schedule_rounded,
              label: 'التأخير',
              value: employee.lateMinutes > 0
                  ? '${employee.lateMinutes} دقيقة'
                  : '—',
            ),
            _detailRow(
              context,
              icon: Icons.directions_car_rounded,
              label: 'مأمورية',
              value: employee.isOnMission ? 'في مأمورية خارجية' : '—',
            ),
            if (employee.lastRecordedAt != null)
              _detailRow(
                context,
                icon: Icons.location_on_rounded,
                label: 'آخر موقع',
                value: f.format(employee.lastRecordedAt!.toLocal()),
              ),
            if (employee.lastLatitude != null &&
                employee.lastLongitude != null)
              _detailRow(
                context,
                icon: Icons.gps_fixed_rounded,
                label: 'الإحداثيات',
                value:
                    '${employee.lastLatitude!.toStringAsFixed(5)}, ${employee.lastLongitude!.toStringAsFixed(5)}',
              ),
          ],
        ),
      ),
    );
  }
}

Widget _detailRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String value,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
          ),
        ),
      ],
    ),
  );
}
