import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// تبويبات التصفية السريعة في صفحة الملخص التشغيلي
enum _SectionTab {
  all('الكل', Icons.dashboard_outlined),
  calendar('جدول الشهر', Icons.calendar_month_outlined),
  tasks('المهام', Icons.task_alt_outlined),
  documents('المستندات', Icons.badge_outlined),
  missingReports('تقارير اليوم', Icons.newspaper_outlined);

  const _SectionTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// تصفية نطاق جدول الورديات الشهري
enum _CalendarRangeFilter {
  allMonth('كل أيام الشهر'),
  todayOnly('اليوم فقط'),
  upcoming('الأيام القادمة');

  const _CalendarRangeFilter(this.label);
  final String label;
}

/// الملخص التشغيلي الشهري — متابعة جدول الفريق للشهر كاملاً والتنبيهات المباشرة
class TeamOperationsSummaryPage extends ConsumerStatefulWidget {
  const TeamOperationsSummaryPage({super.key});

  @override
  ConsumerState<TeamOperationsSummaryPage> createState() =>
      _TeamOperationsSummaryPageState();
}

class _TeamOperationsSummaryPageState
    extends ConsumerState<TeamOperationsSummaryPage> {
  _SectionTab _activeTab = _SectionTab.all;
  _CalendarRangeFilter _calendarFilter = _CalendarRangeFilter.allMonth;

  @override
  Widget build(BuildContext context) {
    final selectedMonth = ref.watch(mobileManagerOperationsMonthProvider);
    final asyncData = ref.watch(mobileManagerOperationsProvider);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الملخص التشغيلي الشهري'),
        actions: [
          if (!isCurrentMonth)
            IconButton(
              tooltip: 'العودة للشهر الحالي',
              icon: const Icon(Icons.today_rounded),
              onPressed: () {
                ref
                    .read(mobileManagerOperationsMonthProvider.notifier)
                    .resetToCurrentMonth();
              },
            ),
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(mobileManagerOperationsProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: asyncData.when(
          loading: () => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'جاري تحميل الملخص التشغيلي للشهر...',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          error: (error, _) => RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(mobileManagerOperationsProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 80),
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  humanizeError(error),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Center(
                  child: FilledButton.icon(
                    onPressed: () =>
                        ref.invalidate(mobileManagerOperationsProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ),
              ],
            ),
          ),
          data: (data) {
            return RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(mobileManagerOperationsProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  // 1. شريط التنقل بين الشهور (الشهر الحالي أو التنقل بالسهم)
                  _MonthNavigator(
                    selectedMonth: selectedMonth,
                    isCurrentMonth: isCurrentMonth,
                    fromDate: data.from,
                    toDate: data.to,
                    onPrevMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                    onSelectMonthPicker: () => _pickMonth(selectedMonth),
                    onResetToCurrentMonth: () {
                      ref
                          .read(mobileManagerOperationsMonthProvider.notifier)
                          .resetToCurrentMonth();
                    },
                  ),
                  const SizedBox(height: 12),

                  // 2. شبكة المؤشرات التنفيذية (KPI Cards)
                  _ExecutiveMetricsGrid(
                    metrics: data.metrics,
                    calendarCount: data.calendar.length,
                    onSelectSection: (tab) {
                      setState(() => _activeTab = tab);
                    },
                  ),
                  const SizedBox(height: 12),

                  // 3. شريط تبويبات التصفية السريعة
                  _FilterChipsBar(
                    activeTab: _activeTab,
                    data: data,
                    onTabSelected: (tab) {
                      setState(() => _activeTab = tab);
                    },
                  ),
                  const SizedBox(height: 16),

                  // 4. عرض المحتوى بناءً على التبويب النشط
                  if (_activeTab == _SectionTab.all ||
                      _activeTab == _SectionTab.calendar) ...[
                    _buildCalendarSection(context, data),
                    const SizedBox(height: 16),
                  ],

                  if (_activeTab == _SectionTab.all ||
                      _activeTab == _SectionTab.tasks) ...[
                    _buildTasksSection(context, data),
                    const SizedBox(height: 16),
                  ],

                  if (_activeTab == _SectionTab.all ||
                      _activeTab == _SectionTab.documents) ...[
                    _buildDocumentsSection(context, data),
                    const SizedBox(height: 16),
                  ],

                  if (_activeTab == _SectionTab.all ||
                      _activeTab == _SectionTab.missingReports) ...[
                    _buildMissingReportsSection(context, data),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _changeMonth(int deltaMonths) {
    ref
        .read(mobileManagerOperationsMonthProvider.notifier)
        .changeMonth(deltaMonths);
  }

  Future<void> _pickMonth(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2, 1, 1),
      lastDate: DateTime(current.year + 2, 12, 31),
      helpText: 'اختر شهر الملخص التشغيلي',
      cancelText: 'إلغاء',
      confirmText: 'عرض الشهر',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      ref
          .read(mobileManagerOperationsMonthProvider.notifier)
          .setMonth(picked);
    }
  }

  Widget _buildCalendarSection(
    BuildContext context,
    MobileManagerOperations data,
  ) {
    final now = DateTime.now();
    final todayZero = DateTime(now.year, now.month, now.day);

    final grouped = _groupByDay(data.calendar);
    final filteredDays = grouped.entries.where((e) {
      if (_calendarFilter == _CalendarRangeFilter.todayOnly) {
        return DateUtils.isSameDay(e.key, todayZero);
      }
      if (_calendarFilter == _CalendarRangeFilter.upcoming) {
        return !e.key.isBefore(todayZero);
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: MobileSectionHeader(
                title: 'جدول الفريق الشهري',
                subtitle: data.calendar.isEmpty
                    ? 'لا توجد ورديات مسجلة لهذا الشهر.'
                    : 'إجمالي ${data.calendar.length} موظف مجدول عبر ${grouped.length} يوم عمل.',
              ),
            ),
          ],
        ),
        if (data.calendar.isNotEmpty) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _CalendarRangeFilter.values.map((f) {
                final selected = _calendarFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: FilterChip(
                    label: Text(f.label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _calendarFilter = f);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (filteredDays.isEmpty)
          _EmptyCard(
            icon: Icons.event_available_rounded,
            title: 'لا يوجد جدول مطابق',
            subtitle: _calendarFilter == _CalendarRangeFilter.todayOnly
                ? 'لا توجد ورديات مجدولة لأعضاء الفريق اليوم.'
                : 'لا توجد أيام عمل مسجلة في هذا النطاق.',
          )
        else
          ...filteredDays.map(
            (entry) => _MonthlyDayCard(
              date: entry.key,
              entries: entry.value,
              onEmployeeTap: _openEmployee,
            ),
          ),
      ],
    );
  }

  Widget _buildTasksSection(BuildContext context, MobileManagerOperations data) {
    final overdueCount = data.metrics.overdueTasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MobileSectionHeader(
          title: 'المهام المفتوحة لفريقك',
          subtitle: data.tasks.isEmpty
              ? 'لا توجد مهام مفتوحة حالياً.'
              : 'إجمالي ${data.tasks.length} مهمة — المتأخرة منها: $overdueCount',
        ),
        const SizedBox(height: 8),
        if (data.tasks.isEmpty)
          const _EmptyCard(
            icon: Icons.task_alt_rounded,
            title: 'لا توجد مهام مفتوحة',
            subtitle: 'جميع مهام الفريق منجزة وتسير وفق الخطة 👏',
          )
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
      ],
    );
  }

  Widget _buildDocumentsSection(
    BuildContext context,
    MobileManagerOperations data,
  ) {
    final expiringCount = data.documentAlerts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MobileSectionHeader(
          title: 'المستندات المنتهية قريباً',
          subtitle: expiringCount == 0
              ? 'كل وثائق الفريق سارية ولا تتطلب تجديداً.'
              : 'خلال 60 يوماً — عددها: $expiringCount مستند يحتاج متابعة.',
        ),
        const SizedBox(height: 8),
        if (data.documentAlerts.isEmpty)
          const _EmptyCard(
            icon: Icons.verified_user_outlined,
            title: 'وثائق الفريق مكتملة',
            subtitle: 'لا توجد إقامات أو عقود أو هويات منتهية أو قاربت على الانتهاء ✅',
          )
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
      ],
    );
  }

  Widget _buildMissingReportsSection(
    BuildContext context,
    MobileManagerOperations data,
  ) {
    final missingCount = data.missingReports.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MobileSectionHeader(
          title: 'تقارير الإنجاز اليومية',
          subtitle: missingCount == 0
              ? 'جميع أعضاء الفريق رفعوا تقاريرهم اليومية بنجاح.'
              : 'لم يرفع تقرير اليوم $missingCount من منسوبي فريقك.',
        ),
        const SizedBox(height: 8),
        if (data.missingReports.isEmpty)
          const _EmptyCard(
            icon: Icons.check_circle_outline_rounded,
            title: 'التزام تام بالتقارير',
            subtitle: 'جميع منسوبي فريقك قاموا برفع تقارير إنجاز اليوم بنجاح 🎉',
          )
        else
          ...data.missingReports.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MissingReportCard(
                report: r,
                onRemind: () => _remindEmployee(r),
                onTap: r.employeeId.isEmpty
                    ? null
                    : () => _openEmployee(context, r.employeeId),
              ),
            ),
          ),
      ],
    );
  }

  void _remindEmployee(ManagerMissingReport r) {
    final text = 'السلام عليكم ${r.employeeName}، نرجو التكرم برفع تقرير الإنجاز اليومي عبر التطبيق شاكرين تعاونك.';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم نسخ رسالة تذكير لـ ${r.employeeName} إلى الحافظة'),
        action: SnackBarAction(
          label: 'عرض الملف',
          onPressed: () => _openEmployee(context, r.employeeId),
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
}

/// شريط التنقل بين الشهور مع زر الشهر الحالي وزر اختيار التاريخ
class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({
    required this.selectedMonth,
    required this.isCurrentMonth,
    required this.fromDate,
    required this.toDate,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onSelectMonthPicker,
    required this.onResetToCurrentMonth,
  });

  final DateTime selectedMonth;
  final bool isCurrentMonth;
  final DateTime fromDate;
  final DateTime toDate;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onSelectMonthPicker;
  final VoidCallback onResetToCurrentMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthTitle = DateFormat('MMMM y', 'ar').format(selectedMonth);
    final rangeText =
        'من ${DateFormat('d MMMM', 'ar').format(fromDate)} إلى ${DateFormat('d MMMM', 'ar').format(toDate)}';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCurrentMonth
              ? theme.colorScheme.primary.withValues(alpha: .3)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            IconButton(
              tooltip: 'الشهر السابق',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: onPrevMonth,
            ),
            Expanded(
              child: InkWell(
                onTap: onSelectMonthPicker,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              monthTitle,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.calendar_month_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          if (isCurrentMonth) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'الشهر الحالي',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rangeText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'الشهر التالي',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: onNextMonth,
            ),
          ],
        ),
      ),
    );
  }
}

/// شبكة المؤشرات التنفيذية المحسنة
class _ExecutiveMetricsGrid extends StatelessWidget {
  const _ExecutiveMetricsGrid({
    required this.metrics,
    required this.calendarCount,
    required this.onSelectSection,
  });

  final ManagerOperationsMetrics metrics;
  final int calendarCount;
  final void Function(_SectionTab) onSelectSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // الصف الأول: الحضور اليومي
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'مجدول اليوم',
                count: '${metrics.scheduledToday}',
                icon: Icons.event_available_rounded,
                color: AppColors.statusSuccess,
                onTap: () => onSelectSection(_SectionTab.calendar),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'إجازة / مأمورية',
                count: '${metrics.awayToday}',
                icon: Icons.flight_takeoff_rounded,
                color: AppColors.statusInfo,
                onTap: () => onSelectSection(_SectionTab.calendar),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // الصف الثاني: التنبيهات التشغيلية
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'مهام متأخرة',
                count: '${metrics.overdueTasks}',
                icon: Icons.assignment_late_outlined,
                color: metrics.overdueTasks > 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
                hasAlert: metrics.overdueTasks > 0,
                onTap: () => onSelectSection(_SectionTab.tasks),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'مستندات تنتهي',
                count: '${metrics.expiringDocuments}',
                icon: Icons.badge_outlined,
                color: metrics.expiringDocuments > 0
                    ? AppColors.statusWarning
                    : theme.colorScheme.onSurfaceVariant,
                hasAlert: metrics.expiringDocuments > 0,
                onTap: () => onSelectSection(_SectionTab.documents),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'تقارير ناقصة',
                count: '${metrics.missingReports}',
                icon: Icons.feed_outlined,
                color: metrics.missingReports > 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
                hasAlert: metrics.missingReports > 0,
                onTap: () => onSelectSection(_SectionTab.missingReports),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
    this.hasAlert = false,
  });

  final String title;
  final String count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool hasAlert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasAlert
              ? color.withValues(alpha: .5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(
                    count,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: hasAlert ? color : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط تبويبات التصفية السريعة
class _FilterChipsBar extends StatelessWidget {
  const _FilterChipsBar({
    required this.activeTab,
    required this.data,
    required this.onTabSelected,
  });

  final _SectionTab activeTab;
  final MobileManagerOperations data;
  final void Function(_SectionTab) onTabSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _SectionTab.values.map((tab) {
          final isSelected = activeTab == tab;
          final count = switch (tab) {
            _SectionTab.calendar => data.calendar.length,
            _SectionTab.tasks => data.tasks.length,
            _SectionTab.documents => data.documentAlerts.length,
            _SectionTab.missingReports => data.missingReports.length,
            _SectionTab.all => null,
          };

          final labelText =
              count != null ? '${tab.label} ($count)' : tab.label;

          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              avatar: Icon(tab.icon, size: 16),
              label: Text(labelText),
              selected: isSelected,
              onSelected: (_) => onTabSelected(tab),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// بطاقة يوم العمل في التقويم الشهري
class _MonthlyDayCard extends StatelessWidget {
  const _MonthlyDayCard({
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
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isToday
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isToday ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: isToday
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DateFormat('EEEE d MMMM y', 'ar').format(date),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: isToday ? theme.colorScheme.primary : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if (isToday) ...[
                  const MobileStatusPill('active'),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    arEmployees(entries.length),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entries.map((entry) {
                final shiftTime = (entry.startsAt != null && entry.endsAt != null)
                    ? ' (${entry.startsAt} - ${entry.endsAt})'
                    : '';
                final chipText = '${entry.employeeName}$shiftTime';

                return ActionChip(
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text(chipText),
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
                  tooltip: entry.notes ?? entry.shiftName,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة المهمة المفتوحة
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap});

  final ManagerTaskAlert task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: task.isOverdue
              ? theme.colorScheme.error.withValues(alpha: .5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
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
                'الاستحقاق: ${DateFormat('d MMMM y', 'ar').format(task.dueDate!)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: task.isOverdue
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: task.isOverdue ? FontWeight.bold : FontWeight.normal,
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

/// بطاقة المستند المنتهي
class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc, required this.onTap});

  final ManagerDocumentAlert doc;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isExpired = doc.status == 'expired' || doc.expiryDate.isBefore(today);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isExpired
              ? theme.colorScheme.error.withValues(alpha: .5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
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
              DateFormat('d MMM y', 'ar').format(doc.expiryDate),
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

/// بطاقة التقرير اليومي الناقص مع زر تذكير مباشر
class _MissingReportCard extends StatelessWidget {
  const _MissingReportCard({
    required this.report,
    required this.onRemind,
    required this.onTap,
  });

  final ManagerMissingReport report;
  final VoidCallback onRemind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: .4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.errorContainer,
          child: Icon(
            Icons.newspaper_outlined,
            color: theme.colorScheme.error,
            size: 20,
          ),
        ),
        title: Text(
          report.employeeName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'كود: ${report.employeeCode ?? '—'} · لم يرفع تقرير اليوم بعد',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'نسخ رسالة تذكير',
              icon: const Icon(Icons.notifications_active_outlined, size: 20),
              color: theme.colorScheme.primary,
              onPressed: onRemind,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'بلا تقرير',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// بطاقة حالة فارغة مشجعة
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 36,
                color: theme.colorScheme.primary.withValues(alpha: .7),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
