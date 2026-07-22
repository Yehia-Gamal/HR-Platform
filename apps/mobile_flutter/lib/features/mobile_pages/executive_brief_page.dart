import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_risk_center_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_inbox_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
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
  String period = DateTime.now().hour < 15 ? 'morning' : 'evening';

  @override
  Widget build(BuildContext context) {
    final brief = ref.watch(mobileExecutiveBriefProvider(period));
    return Scaffold(
      appBar: AppBar(title: const Text('الملخص التنفيذي اليومي')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(mobileExecutiveBriefProvider(period)),
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
              Text(
                humanizeError(error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.invalidate(mobileExecutiveBriefProvider(period)),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: period == 'morning'
                  ? const [AppColors.brandPrimaryStrong, AppColors.accent]
                  : const [AppColors.eveningDark, AppColors.eveningAccent],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    period == 'morning'
                        ? Icons.wb_sunny_outlined
                        : Icons.nights_stay_outlined,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    period == 'morning'
                        ? 'ملخص بداية اليوم'
                        : 'ملخص نهاية اليوم',
                    style: const TextStyle(
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
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'morning',
              icon: Icon(Icons.wb_sunny_outlined),
              label: Text('صباحي'),
            ),
            ButtonSegment(
              value: 'evening',
              icon: Icon(Icons.nights_stay_outlined),
              label: Text('مسائي'),
            ),
          ],
          selected: {period},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => period = value.first),
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
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        MetricGrid(
          cards: [
            (
              'غياب اليوم',
              item.attendance.absentToday.toString(),
              Icons.person_off_outlined,
              null,
            ),
            (
              'إجازات اليوم',
              item.attendance.onLeaveToday.toString(),
              Icons.event_busy_outlined,
              null,
            ),
            (
              'اعتمادات معلقة',
              item.decisions.pendingApprovals.toString(),
              Icons.approval_outlined,
              null,
            ),
            (
              'تقارير جاهزة',
              item.decisions.reportsReadyToday.toString(),
              Icons.analytics_outlined,
              null,
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
            ('الموظفون النشطون', _daily(item, 'employees', 'active').toString(), Icons.groups_rounded, null),
            ('المطلوب حضورهم', _daily(item, 'employees', 'requiredToday').toString(), Icons.badge_outlined, null),
            ('لم يسجلوا بعد', _daily(item, 'attendance', 'notYet').toString(), Icons.hourglass_top_rounded, null),
            ('لم يسجلوا الانصراف', _daily(item, 'attendance', 'missingCheckout').toString(), Icons.logout_rounded, null),
            ('مأموريات', _daily(item, 'workStatus', 'missions').toString(), Icons.work_history_outlined, null),
            ('قوافل', _daily(item, 'workStatus', 'convoys').toString(), Icons.directions_bus_outlined, null),
            ('فاندي', _daily(item, 'workStatus', 'fundraising').toString(), Icons.volunteer_activism_outlined, null),
            ('KPI عند الموظف', _daily(item, 'kpi', 'atEmployee').toString(), Icons.person_outline, null),
            ('KPI عند المدير', _daily(item, 'kpi', 'atManager').toString(), Icons.supervisor_account_outlined, null),
            ('KPI عند HR', _daily(item, 'kpi', 'atHr').toString(), Icons.fact_check_outlined, null),
            ('تقارير KPI جاهزة', _daily(item, 'kpi', 'ready').toString(), Icons.analytics_outlined, null),
            ('طلبات موقع بلا رد', _daily(item, 'followUp', 'unansweredLocationRequests').toString(), Icons.location_searching_rounded, null),
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

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.label,
    required this.value,
    required this.previous,
    required this.icon,
    required this.positiveWhenHigher,
  });

  final String label;
  final int value;
  final int previous;
  final IconData icon;
  final bool positiveWhenHigher;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final delta = value - previous;
    final positive = positiveWhenHigher ? delta >= 0 : delta <= 0;
    final color = positive ? AppColors.statusSuccess : AppColors.statusDanger;
    return Card(
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
    );
  }
}
