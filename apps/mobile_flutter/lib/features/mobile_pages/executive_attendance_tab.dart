import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:intl/intl.dart';

/// تبويب الحضور اليومي — يعرض حالة كل موظف اليوم للمدير التنفيذي.
class ExecutiveAttendanceTab extends ConsumerWidget {
  const ExecutiveAttendanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text('تعذر تحميل بيانات الحضور', textAlign: TextAlign.center),
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
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text('لا يوجد موظفون نشطون'),
                  ],
                ),
              );
            }

            // ملخص أعداد الحضور
            final counts = <String, int>{};
            for (final e in employees) {
              final key = e.isOnMission ? 'mission' : e.attendanceStatus;
              counts[key] = (counts[key] ?? 0) + 1;
            }

            // ─── تجميع الموظفين حسب القسم ─────────────────────────────────
            final grouped = <String, List<AttendanceTodayEmployee>>{};
            for (final emp in employees) {
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

            // بناء قائمة العناصر المسطّحة: شريط الملخص + رؤوس الأقسام + بطاقات
            final items = <Widget>[
              // ─── شريط الملخص ──────────────────────────────────────────
              _SummaryBar(counts: counts, total: employees.length),
              const SizedBox(height: 16),
            ];

            for (final dept in sortedDepts) {
              final deptEmployees = grouped[dept]!;

              // حساب ملخص الحضور لكل قسم
              int present = 0, late = 0, absent = 0;
              for (final e in deptEmployees) {
                if (e.isOnMission) continue;
                if (e.attendanceStatus == 'present') present++;
                if (e.attendanceStatus == 'late') late++;
                if (e.attendanceStatus == 'absent') absent++;
              }
              final summaryParts = <String>[];
              if (present > 0) summaryParts.add('$present حاضر');
              if (late > 0) summaryParts.add('$late متأخر');
              if (absent > 0) summaryParts.add('$absent غائب');

              // رأس القسم
              items.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.business_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dept,
                          style: Theme.of(context).textTheme.titleSmall
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

              // بطاقات الموظفين في هذا القسم
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
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
              children: items,
            );
          },
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.counts, required this.total});
  final Map<String, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(
          label: 'الإجمالي',
          count: total,
          color: Theme.of(context).colorScheme.outline,
        ),
        if ((counts['present'] ?? 0) > 0)
          _SummaryChip(
            label: 'حضر',
            count: counts['present']!,
            color: Colors.green.shade700,
          ),
        if ((counts['late'] ?? 0) > 0)
          _SummaryChip(
            label: 'متأخر',
            count: counts['late']!,
            color: Colors.orange.shade700,
          ),
        if ((counts['absent'] ?? 0) > 0)
          _SummaryChip(
            label: 'غائب',
            count: counts['absent']!,
            color: Colors.red.shade700,
          ),
        if ((counts['mission'] ?? 0) > 0)
          _SummaryChip(
            label: 'مأمورية',
            count: counts['mission']!,
            color: Colors.purple.shade700,
          ),
        if ((counts['on_leave'] ?? 0) > 0)
          _SummaryChip(
            label: 'إجازة',
            count: counts['on_leave']!,
            color: Colors.blue.shade700,
          ),
        if ((counts['partial'] ?? 0) > 0)
          _SummaryChip(
            label: 'جزئي',
            count: counts['partial']!,
            color: Colors.amber.shade700,
          ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: color,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
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
      child: InkWell(
        onTap: () => _showEmployeeSummary(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // صورة الموظف مع شارة الحالة
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
              // بيل الحالة
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
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
    if (employee.firstCheckIn != null) {
      parts.add(
        'دخول ${DateFormat('h:mm a', 'ar').format(employee.firstCheckIn!.toLocal())}',
      );
    }
    if (employee.lateMinutes > 0) {
      parts.add('تأخر ${employee.lateMinutes} د');
    }
    if (employee.lastRecordedAt != null) {
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (employee.employeeCode != null)
                        Text(
                          employee.employeeCode!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
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
            if (employee.lastLatitude != null && employee.lastLongitude != null)
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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
