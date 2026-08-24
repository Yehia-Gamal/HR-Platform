import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_attendance_tab.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_risk_center_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/location_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_inbox_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_operations_center_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/people_hub_page.dart';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ExecutiveBriefPage extends ConsumerStatefulWidget {
  const ExecutiveBriefPage({super.key});

  @override
  ConsumerState<ExecutiveBriefPage> createState() => _ExecutiveBriefPageState();
}

class _ExecutiveBriefPageState extends ConsumerState<ExecutiveBriefPage> {
  // يوم عمل كامل — لا شيفتات صباحية/مسائية
  static const _period = 'morning';

  @override
  Widget build(BuildContext context) {
    final brief = ref.watch(mobileExecutiveBriefProvider(_period));
    return Scaffold(
      appBar: AppBar(title: const Text('الملخص التنفيذي اليومي')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(mobileExecutiveBriefProvider(_period)),
        child: brief.when(
          loading: () => LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: constraints.maxHeight,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 90),
              Semantics(
                excludeSemantics: true,
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 52,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.invalidate(mobileExecutiveBriefProvider(_period)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(MobileExecutiveBrief item) {
    final scheme = Theme.of(context).colorScheme;
    final access = ref.watch(accessContextProvider).value;
    // 0439+: كل بطاقة رقم تفتح وجهتها — الصفحات التي تحتاج صلاحية تعطل
    // النقر فقط إذا لم يُحمَّل سياق الوصول بعد.
    final operationsTap = access == null
        ? null
        : () => _openPage(MobileOperationsCenterPage(access: access));
    final kpiTap = access == null
        ? null
        : () => _openPage(MobileKpiPage(access: access));
    final locationRequestsTap = access == null
        ? null
        : () => _openPage(LocationRequestsPage(access: access));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [AppColors.brandPrimaryStrong, AppColors.accent],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, color: Colors.white),
                  const SizedBox(width: 9),
                  const Text(
                    'ملخص اليوم',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('d MMMM', 'ar').format(item.briefDate),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                item.decisions.urgentActions > 0
                    ? '${item.decisions.urgentActions} إجراءات تحتاج قرارك الآن.'
                    : 'لا توجد إجراءات حرجة بمهلة قصيرة الآن.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'أهم خمسة تنبيهات فقط، مع مقارنة تشغيلية مباشرة ووقت تحديث واضح.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .75),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const MobileSectionHeader(
          title: 'الحضور مقارنة بأمس',
          subtitle: 'الأرقام المجمعة فقط دون كشف بيانات شخصية غير لازمة.',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ComparisonCard(
                label: 'حضور اليوم',
                value: item.attendance.presentToday,
                previous: item.attendance.presentYesterday,
                icon: Icons.groups_rounded,
                positiveWhenHigher: true,
                onTap: () => _openPage(const ExecutiveAttendanceTab()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ComparisonCard(
                label: 'تأخير اليوم',
                value: item.attendance.lateToday,
                previous: item.attendance.lateYesterday,
                icon: Icons.schedule_rounded,
                positiveWhenHigher: false,
                onTap: () => _openPage(const ExecutiveAttendanceTab()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _AttendanceTrendChart(),
        const SizedBox(height: 10),
        MetricGrid(
          cards: [
            (
              'غياب اليوم',
              item.attendance.absentToday.toString(),
              Icons.person_off_outlined,
              () => _openPage(const ExecutiveAttendanceTab()),
            ),
            (
              'إجازات اليوم',
              item.attendance.onLeaveToday.toString(),
              Icons.event_busy_outlined,
              () => _openPage(const ExecutiveAttendanceTab()),
            ),
            (
              'اعتمادات معلقة',
              item.decisions.pendingApprovals.toString(),
              Icons.approval_outlined,
              () => _openPage(const MobileActionInboxPage()),
            ),
            (
              'تقارير جاهزة',
              item.decisions.reportsReadyToday.toString(),
              Icons.analytics_outlined,
              () => _openPage(const ExecutiveReportsPage()),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const MobileSectionHeader(
          title: 'تقرير التشغيل اليومي الكامل',
          subtitle: 'يبدأ من جميع الموظفين النشطين، مع مصدر ووقت تحديث واضحين.',
        ),
        const SizedBox(height: 10),
        MetricGrid(
          cards: [
            (
              'الموظفون النشطون',
              _daily(item, 'employees', 'active').toString(),
              Icons.groups_rounded,
              () => _openPage(const PeopleHubPage()),
            ),
            (
              'المطلوب حضورهم',
              _daily(item, 'employees', 'requiredToday').toString(),
              Icons.badge_outlined,
              () => _openPage(const ExecutiveAttendanceTab()),
            ),
            (
              'لم يسجلوا بعد',
              _daily(item, 'attendance', 'notYet').toString(),
              Icons.hourglass_top_rounded,
              () => _openPage(const ExecutiveAttendanceTab()),
            ),
            (
              'لم يسجلوا الانصراف',
              _daily(item, 'attendance', 'missingCheckout').toString(),
              Icons.logout_rounded,
              () => _openPage(const ExecutiveAttendanceTab()),
            ),
            (
              'مأموريات',
              _daily(item, 'workStatus', 'missions').toString(),
              Icons.work_history_outlined,
              operationsTap,
            ),
            (
              'قوافل',
              _daily(item, 'workStatus', 'convoys').toString(),
              Icons.directions_bus_outlined,
              operationsTap,
            ),
            (
              'فاندي',
              _daily(item, 'workStatus', 'fundraising').toString(),
              Icons.volunteer_activism_outlined,
              operationsTap,
            ),
            (
              'KPI عند الموظف',
              _daily(item, 'kpi', 'atEmployee').toString(),
              Icons.person_outline,
              kpiTap,
            ),
            (
              'KPI عند المدير',
              _daily(item, 'kpi', 'atManager').toString(),
              Icons.supervisor_account_outlined,
              kpiTap,
            ),
            (
              'KPI عند HR',
              _daily(item, 'kpi', 'atHr').toString(),
              Icons.fact_check_outlined,
              kpiTap,
            ),
            (
              'تقارير KPI جاهزة',
              _daily(item, 'kpi', 'ready').toString(),
              Icons.analytics_outlined,
              () => _openPage(const ExecutiveReportsPage()),
            ),
            (
              'طلبات موقع بلا رد',
              _daily(item, 'followUp', 'unansweredLocationRequests').toString(),
              Icons.location_searching_rounded,
              locationRequestsTap,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const MobileSectionHeader(
          title: 'ما يحتاج انتباهك',
          subtitle: 'مرتب حسب الأثر والمهلة، وبحد أقصى خمسة عناصر.',
        ),
        const SizedBox(height: 10),
        if (item.highlights.isEmpty)
          Card(
            color: scheme.primaryContainer.withValues(alpha: .5),
            child: const ListTile(
              contentPadding: EdgeInsets.all(16),
              leading: CircleAvatar(child: Icon(Icons.verified_rounded)),
              title: Text(
                'لا توجد تنبيهات تشغيلية ذات أولوية',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                'يمكن متابعة التقارير والحوكمة وفق الجدول المعتاد.',
              ),
            ),
          )
        else
          ...item.highlights.map(
            (highlight) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: _color(
                      highlight.severity,
                    ).withValues(alpha: .12),
                    child: Icon(
                      _icon(highlight.kind),
                      color: _color(highlight.severity),
                    ),
                  ),
                  title: Text(
                    highlight.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(highlight.detail),
                  trailing: Text(
                    highlight.value.toString(),
                    style: TextStyle(
                      color: _color(highlight.severity),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onTap: () => _openHighlight(highlight.kind),
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Card(
          color: scheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.sync_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${item.sourceLabel} · ${DateFormat('h:mm a', 'ar').format(item.generatedAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openPage(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _openHighlight(String kind) {
    final Widget page = switch (kind) {
      'risk' || 'incident' => const ExecutiveRiskCenterPage(),
      'report' => Scaffold(
        appBar: AppBar(title: const Text('التقارير التنفيذية')),
        body: const ExecutiveReportsPage(),
      ),
      _ => Scaffold(
        appBar: AppBar(title: const Text('صندوق الإجراءات')),
        body: const MobileActionInboxPage(),
      ),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  int _daily(MobileExecutiveBrief item, String section, String key) {
    final sectionValue = item.dailyReport[section];
    if (sectionValue is! Map) return 0;
    return (sectionValue[key] as num?)?.toInt() ?? 0;
  }

  static IconData _icon(String kind) => switch (kind) {
    'incident' => Icons.crisis_alert_rounded,
    'risk' => Icons.warning_amber_rounded,
    'kpi' => Icons.speed_outlined,
    'report' => Icons.analytics_outlined,
    'attendance' => Icons.schedule_rounded,
    _ => Icons.approval_outlined,
  };

  Color _color(String severity) => switch (severity) {
    'critical' => AppColors.statusDanger,
    'high' => AppColors.statusWarning,
    _ => Theme.of(context).colorScheme.primary,
  };
}

/// رسم بياني شريطي لاتجاه الحضور — آخر 14 يوماً من attendance_daily.
/// كل عمود: حضور (أخضر) + تأخير (برتقالي) + غياب (أحمر) بنِسَب اليوم.
/// النقر يفتح تبويب الحضور التنفيذي.
class _AttendanceTrendChart extends ConsumerWidget {
  const _AttendanceTrendChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final trend = ref.watch(mobileAttendanceTrendProvider(14));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExecutiveAttendanceTab()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.insights_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'اتجاه الحضور — آخر 14 يوماً',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              trend.when(
                loading: () => const SizedBox(
                  height: 90,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (_, _) => Text(
                  'تعذر تحميل الاتجاه — اسحب للتحديث.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                data: (points) {
                  if (points.isEmpty) {
                    return Text(
                      'لا توجد بيانات حضور بعد.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    );
                  }
                  // أعلى إجمالي يومي لتحديد ارتفاع الأعمدة نسبياً.
                  var maxTotal = 1;
                  for (final p in points) {
                    if (p.total > maxTotal) maxTotal = p.total;
                  }
                  return Column(
                    children: [
                      SizedBox(
                        height: 90,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final p in points)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (p.absent > 0)
                                        _TrendSegment(
                                          fraction: p.absent / maxTotal,
                                          color: AppColors.statusDanger,
                                        ),
                                      if (p.late > 0)
                                        _TrendSegment(
                                          fraction: p.late / maxTotal,
                                          color: AppColors.statusWarning,
                                        ),
                                      if (p.present > 0)
                                        _TrendSegment(
                                          fraction: p.present / maxTotal,
                                          color: AppColors.statusSuccess,
                                        ),
                                      if (p.total == 0)
                                        _TrendSegment(
                                          fraction: 0.04,
                                          color: scheme.outlineVariant,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          for (final p in points)
                            Expanded(
                              child: Text(
                                p.asDate == null ? '' : '${p.asDate!.day}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _TrendLegend(
                            color: AppColors.statusSuccess,
                            label: 'حاضر',
                          ),
                          const SizedBox(width: 12),
                          _TrendLegend(
                            color: AppColors.statusWarning,
                            label: 'متأخر',
                          ),
                          const SizedBox(width: 12),
                          _TrendLegend(
                            color: AppColors.statusDanger,
                            label: 'غائب',
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريحة ملونة داخل عمود الاتجاه — الارتفاع نسبي من أعلى إجمالي.
class _TrendSegment extends StatelessWidget {
  const _TrendSegment({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: (fraction.clamp(0.0, 1.0)) * 90,
      width: double.infinity,
      color: color,
    );
  }
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.label,
    required this.value,
    required this.previous,
    required this.icon,
    required this.positiveWhenHigher,
    this.onTap,
  });

  final String label;
  final int value;
  final int previous;
  final IconData icon;
  final bool positiveWhenHigher;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final delta = value - previous;
    final positive = positiveWhenHigher ? delta >= 0 : delta <= 0;
    final color = positive ? AppColors.statusSuccess : AppColors.statusDanger;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                value.toString(),
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Icon(
                    delta == 0
                        ? Icons.remove_rounded
                        : delta > 0
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 15,
                    color: color,
                  ),
                  Text(
                    delta == 0 ? 'مثل أمس' : '${delta.abs()} عن أمس',
                    style: textTheme.labelSmall?.copyWith(color: color),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
