import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_daily_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ManagerOperationsPage extends ConsumerStatefulWidget {
  const ManagerOperationsPage({super.key});

  @override
  ConsumerState<ManagerOperationsPage> createState() =>
      _ManagerOperationsPageState();
}

class _ManagerOperationsPageState extends ConsumerState<ManagerOperationsPage> {
  int section = 0;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(mobileManagerOperationsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mobileManagerOperationsProvider),
      child: data.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 90),
            Icon(
              Icons.sync_problem_rounded,
              size: 52,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              humanizeError(error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(mobileManagerOperationsProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
        data: _content,
      ),
    );
  }

  Widget _content(MobileManagerOperations item) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [scheme.primary, scheme.secondary],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.hub_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مركز تشغيل الفريق',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'جدول التوفر والمهام وتقارير اليوم وتنبيهات الوثائق في مكان واحد.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        height: 1.45,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        MetricGrid(
          cards: [
            (
              'مجدولون اليوم',
              item.metrics.scheduledToday.toString(),
              Icons.calendar_month_outlined,
              null,
            ),
            (
              'خارج المكتب',
              item.metrics.awayToday.toString(),
              Icons.work_off_outlined,
              null,
            ),
            (
              'مهام متأخرة',
              item.metrics.overdueTasks.toString(),
              Icons.schedule_rounded,
              null,
            ),
            (
              'تقارير ناقصة',
              item.metrics.missingReports.toString(),
              Icons.assignment_late_outlined,
              null,
            ),
          ],
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('التوفر'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.task_outlined),
                label: Text('المهام'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.summarize_outlined),
                label: Text('التقارير'),
              ),
              ButtonSegment(
                value: 3,
                icon: Icon(Icons.badge_outlined),
                label: Text('الوثائق'),
              ),
            ],
            selected: {section},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => section = value.first),
          ),
        ),
        const SizedBox(height: 18),
        switch (section) {
          0 => _calendar(item.calendar),
          1 => _tasks(item.tasks),
          2 => _reports(item.missingReports),
          _ => _documents(item.documentAlerts),
        },
      ],
    );
  }

  Widget _calendar(List<ManagerRosterEntry> entries) {
    final grouped = <DateTime, List<ManagerRosterEntry>>{};
    for (final entry in entries) {
      final day = DateUtils.dateOnly(entry.workDate);
      grouped.putIfAbsent(day, () => []).add(entry);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MobileSectionHeader(
          title: 'تقويم التوفر القادم',
          subtitle: 'الورديات والإجازات والمأموريات المنشورة للفريق.',
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          const _EmptyCard(
            icon: Icons.calendar_today_outlined,
            message: 'لا توجد جداول منشورة خلال الأسبوعين القادمين.',
          )
        else
          ...grouped.entries.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE، d MMMM', 'ar').format(group.key),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 7),
                      ...group.value.map(
                        (entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: CircleAvatar(
                            child: Text(entry.employeeName.substring(0, 1)),
                          ),
                          title: Text(entry.employeeName),
                          subtitle: Text(_shift(entry)),
                          trailing: MobileStatusPill(entry.dayStatus),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tasks(List<ManagerTaskAlert> tasks) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const MobileSectionHeader(
        title: 'متابعة مهام الفريق',
        subtitle: 'المهام المفتوحة مرتبة حسب التأخير وموعد التسليم.',
      ),
      const SizedBox(height: 10),
      if (tasks.isEmpty)
        const _EmptyCard(
          icon: Icons.task_alt_rounded,
          message: 'لا توجد مهام مفتوحة على الفريق.',
        )
      else
        ...tasks.map(
          (task) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              color: task.isOverdue
                  ? Theme.of(
                      context,
                    ).colorScheme.errorContainer.withValues(alpha: .28)
                  : null,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: CircleAvatar(
                  child: Icon(
                    task.isOverdue ? Icons.timer_off_outlined :
                    null,
                  ),
                ),
                title: Text(
                  task.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${task.employeeName}${task.dueDate == null ? '' : ' · ${DateFormat('d MMM', 'ar').format(task.dueDate!)}'}',
                ),
                trailing: MobileStatusPill(
                  task.isOverdue ? 'urgent' : task.priority,
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _reports(List<ManagerMissingReport> reports) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const MobileSectionHeader(
        title: 'تقارير اليوم',
        subtitle: 'أعضاء الفريق الذين لم يرسلوا تقريرهم اليومي بعد.',
      ),
      const SizedBox(height: 10),
      if (reports.isEmpty)
        const _EmptyCard(
          icon: Icons.verified_rounded,
          message: 'ممتاز، جميع تقارير الفريق موجودة اليوم.',
        )
      else
        Card(
          child: Column(
            children: reports
                .map(
                  (report) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    leading: const CircleAvatar(
                      child: Icon(Icons.hourglass_bottom_rounded),
                    ),
                    title: Text(
                      report.employeeName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(report.employeeCode ?? 'بدون كود'),
                    trailing: Semantics(
                      label: 'عرض تقارير الموظف',
                      button: true,
                      child: Icon(Icons.chevron_left_rounded),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MobileDailyReportsPage(
                          employeeId: report.employeeId,
                          employeeName: report.employeeName,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
    ],
  );

  Widget _documents(List<ManagerDocumentAlert> documents) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MobileSectionHeader(
        title: 'تنبيهات الوثائق',
        subtitle: '${documents.length} مستندًا منتهيًا أو ينتهي خلال 60 يومًا.',
      ),
      const SizedBox(height: 10),
      if (documents.isEmpty)
        const _EmptyCard(
          icon: Icons.verified_user_outlined,
          message: 'لا توجد وثائق قريبة الانتهاء داخل الفريق.',
        )
      else
        ...documents.map(
          (document) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: CircleAvatar(
                  child: Icon(
                    document.status == 'expired'
                        ? Icons.warning_amber_rounded
                        :
                    null,
                  ),
                ),
                title: Text(
                  document.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${document.employeeName} · ${DateFormat('d MMM y', 'ar').format(document.expiryDate)}',
                ),
                trailing: MobileStatusPill(
                  document.status == 'expired' ? 'urgent' : 'high',
                ),
              ),
            ),
          ),
        ),
    ],
  );

  static String _shift(ManagerRosterEntry item) {
    if (item.dayStatus != 'scheduled') return _dayStatus(item.dayStatus);
    final times = [
      item.startsAt?.substring(0, 5),
      item.endsAt?.substring(0, 5),
    ].whereType<String>().join(' – ');
    return [
      item.shiftName,
      times,
    ].whereType<String>().where((v) => v.isNotEmpty).join(' · ');
  }

  static String _dayStatus(String value) => switch (value) {
    'scheduled' => 'وردية',
    'rest' => 'راحة',
    'holiday' => 'عطلة',
    'leave' => 'إجازة',
    'mission' => 'مأمورية',
    _ => value,
  };
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 38),
          const SizedBox(height: 9),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
