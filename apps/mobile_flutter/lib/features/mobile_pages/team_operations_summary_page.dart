import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// الملخص التشغيلي 14 يوماً — جدول الفريق القادم والتنبيهات (مهام/مستندات/تقارير)
/// عبر get_mobile_manager_operations: يتحقق الخادم من صفة المدير ويحد من النطاق
/// بـ 45 يوماً كحد أقصى، ويعود بمدى اليوم → +14 افتراضياً.
class TeamOperationsSummaryPage extends ConsumerWidget {
  const TeamOperationsSummaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mobileManagerOperationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الملخص التشغيلي 14 يوم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(mobileManagerOperationsProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(mobileManagerOperationsProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 120),
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  humanizeError(error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(mobileManagerOperationsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(mobileManagerOperationsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                MobileSectionHeader(
                  title: 'الملخص التشغيلي 14 يوم',
                  subtitle:
                      'من ${_fmtDay(data.from)} إلى ${_fmtDay(data.to)} — جدول الفريق والتنبيهات التلقائية.',
                ),
                const SizedBox(height: 8),
                _MetricsStrip(metrics: data.metrics),
                const SizedBox(height: 16),
                MobileSectionHeader(
                  title: 'جدول الفريق القادم',
                  subtitle: '${data.calendar.length} يوم عمل مجدول.',
                ),
                const SizedBox(height: 8),
                if (data.calendar.isEmpty)
                  const _EmptyHint(text: 'لا يوجد جدول في هذا النطاق.')
                else
                  ..._groupByDay(data.calendar).entries.map(
                    (entry) => _DayCard(
                      date: entry.key,
                      entries: entry.value,
                      onEmployeeTap: _openEmployee,
                    ),
                  ),
                const SizedBox(height: 16),
                MobileSectionHeader(
                  title: 'المهام المفتوحة',
                  subtitle:
                      '${data.metrics.overdueTasks} متأخرة من ${data.tasks.length} مفتوحة.',
                ),
                const SizedBox(height: 8),
                if (data.tasks.isEmpty)
                  const _EmptyHint(text: 'لا توجد مهام مفتوحة حالياً.')
                else
                  ...data.tasks.map(
                    (task) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TaskCard(
                        task: task,
                        onTap: task.employeeId.isEmpty
                            ? null
                            : () => _openEmployee(context, task.employeeId),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                MobileSectionHeader(
                  title: 'المستندات المنتهية قريباً',
                  subtitle: 'خلال 60 يوماً — ${data.documentAlerts.length} مستند.',
                ),
                const SizedBox(height: 8),
                if (data.documentAlerts.isEmpty)
                  const _EmptyHint(text: 'لا مستندات تحتاج تجديداً حالياً.')
                else
                  ...data.documentAlerts.map(
                    (doc) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _DocumentCard(
                        doc: doc,
                        onTap: doc.employeeId.isEmpty
                            ? null
                            : () => _openEmployee(context, doc.employeeId),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                MobileSectionHeader(
                  title: 'تقارير يومية ناقصة',
                  subtitle: '${data.missingReports.length} موظف لم يرفع تقرير اليوم.',
                ),
                const SizedBox(height: 8),
                if (data.missingReports.isEmpty)
                  const _EmptyHint(text: 'كل فريقك رفع تقرير اليوم.')
                else
                  ...data.missingReports.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MissingReportCard(
                        report: r,
                        onTap: r.employeeId.isEmpty
                            ? null
                            : () => _openEmployee(context, r.employeeId),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openEmployee(BuildContext context, String employeeId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeProfilePage(
          employeeId: employeeId,
          employeeName: null,
        ),
      ),
    );
  }

  Map<DateTime, List<ManagerRosterEntry>> _groupByDay(
    List<ManagerRosterEntry> entries,
  ) {
    final grouped = <DateTime, List<ManagerRosterEntry>>{};
    for (final entry in entries) {
      final day = DateTime(
        entry.workDate.year,
        entry.workDate.month,
        entry.workDate.day,
      );
      grouped.putIfAbsent(day, () => []).add(entry);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    return {for (final key in sortedKeys) key: grouped[key]!};
  }

  static String _fmtDay(DateTime value) =>
      DateFormat('d MMMM', 'ar').format(value);
}

class _MetricsStrip extends StatelessWidget {
  const _MetricsStrip({required this.metrics});

  final ManagerOperationsMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _cell(theme, '${metrics.scheduledToday}', 'مجدول اليوم'),
            _cell(theme, '${metrics.awayToday}', 'بعيد اليوم'),
            _cell(
              theme,
              '${metrics.overdueTasks}',
              'مهام متأخرة',
              accent: metrics.overdueTasks > 0
                  ? theme.colorScheme.error
                  : null,
            ),
            _cell(
              theme,
              '${metrics.expiringDocuments}',
              'مستندات تنتهي',
              accent: metrics.expiringDocuments > 0
                  ? theme.colorScheme.error
                  : null,
            ),
            _cell(
              theme,
              '${metrics.missingReports}',
              'تقارير ناقصة',
              accent: metrics.missingReports > 0
                  ? theme.colorScheme.error
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    ThemeData theme,
    String value,
    String label, {
    Color? accent,
  }) =>
      Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.date,
    required this.entries,
    required this.onEmployeeTap,
  });

  final DateTime date;
  final List<ManagerRosterEntry> entries;
  final void Function(BuildContext, String) onEmployeeTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  DateFormat('EEEE d MMMM y', 'ar').format(date),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 8),
                  MobileStatusPill('active'),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entries.map((entry) {
                return ActionChip(
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text(entry.employeeName),
                  labelStyle: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  onPressed: entry.employeeId.isEmpty
                      ? null
                      : () => onEmployeeTap(context, entry.employeeId),
                  backgroundColor: Colors.transparent,
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                  tooltip: entry.notes,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap});

  final ManagerTaskAlert task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          task.isOverdue
              ? Icons.priority_high_rounded
              : Icons.task_alt_rounded,
          color: task.isOverdue
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
        ),
        title: Text(
          task.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.employeeName),
            if (task.dueDate != null)
              Text(
                'الاستحقاق ${DateFormat('d MMM', 'ar').format(task.dueDate!)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: task.isOverdue
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MobileStatusPill(_priorityPill(task.priority)),
            if (task.isOverdue) const MobileStatusPill('rejected'),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  static String _priorityPill(String priority) => switch (priority) {
    'urgent' => 'urgent',
    'high' => 'high',
    'medium' => 'normal',
    'low' => 'low',
    _ => priority,
  };
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc, required this.onTap});

  final ManagerDocumentAlert doc;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpired = doc.status == 'expired' ||
        doc.expiryDate.isBefore(
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
        );
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          Icons.assignment_late_outlined,
          color: isExpired
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
        ),
        title: Text(
          doc.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(doc.employeeName),
        trailing: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${DateFormat('d MMM y', 'ar').format(doc.expiryDate)}'
              '${isExpired ? ' — منتهي' : ''}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: isExpired
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isExpired) const MobileStatusPill('expired'),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _MissingReportCard extends StatelessWidget {
  const _MissingReportCard({required this.report, required this.onTap});

  final ManagerMissingReport report;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          Icons.newspaper_outlined,
          color: theme.colorScheme.error,
        ),
        title: Text(
          report.employeeName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: report.employeeCode?.isNotEmpty ?? false
            ? Text('كود الموظف: ${report.employeeCode}')
            : const Text('لم يرفع تقرير اليوم بعد'),
        trailing: const MobileStatusPill('absent'),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
