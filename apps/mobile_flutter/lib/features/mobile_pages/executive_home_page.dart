import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_brief_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_people_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_decisions_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_disputes_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_attendance_tab.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_location_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_inbox_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared brand accent used for the executive hero light tint.
const Color _kBrandAccent = AppColors.accent;

class ExecutiveHomePage extends ConsumerWidget {
  const ExecutiveHomePage({required this.access, super.key});

  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(executiveDashboardProvider);
    final disputeInbox = ref.watch(executiveDisputeInboxProvider);
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(executiveDashboardProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  AppColors.darkBackground,
                  AppColors.brandPrimaryStrong,
                  AppColors.brandPrimary,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkBackground.withValues(alpha: .28),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BrandLogoMark(inverse: true, size: 40),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'الملخص التنفيذي',
                        style: TextStyle(
                          color: _kBrandAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const ExcludeSemantics(
                      child: Icon(
                        Icons.auto_graph_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'الأهم أولًا.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'القرارات والمخاطر والاعتمادات التي تحتاج متابعة الآن، دون تشتيت بتفاصيل غير ضرورية.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .76),
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          /// V17 §4.2.7 — Quick links: Brief, People, Decisions only.
          Row(
            children: [
              Expanded(
                child: _ExecutiveQuickLink(
                  icon: Icons.auto_awesome_outlined,
                  label: 'ملخص اليوم',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveBriefPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ExecutiveQuickLink(
                  icon: Icons.manage_search_rounded,
                  label: 'الموظفون',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutivePeoplePage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ExecutiveQuickLink(
                  icon: Icons.campaign_outlined,
                  label: 'إصدار قرارات',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveDecisionsPage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const MobileSectionHeader(
            title: 'مؤشرات تحتاج الانتباه',
            subtitle: 'مؤشرات مرتبطة بصلاحياتك كمدير تنفيذي.',
          ),
          const SizedBox(height: 12),
          data.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded),
                    const SizedBox(height: 8),
                    Text(humanizeError(error), textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(executiveDashboardProvider),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
            data: (item) => MetricGrid(
              cards: [
                (
                  'نسبة الحضور',
                  '${item.attendanceRate}%',
                  Icons.groups_rounded,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveAttendanceTab(),
                    ),
                  ),
                ),
                (
                  'عاجل الآن',
                  item.urgentActions.toString(),
                  Icons.priority_high_rounded,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveBriefPage(),
                    ),
                  ),
                ),
                (
                  'اعتمادات',
                  item.pendingApprovals.toString(),
                  Icons.approval_rounded,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MobileActionInboxPage(),
                    ),
                  ),
                ),
                (
                  'تقارير KPI',
                  item.pendingFinalKpi.toString(),
                  Icons.fact_check_outlined,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MobileKpiPage(access: access, employeeOnly: false),
                    ),
                  ),
                ),
                (
                  'قرارات منشورة',
                  item.publishedDecisions.toString(),
                  Icons.gavel_rounded,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveDecisionsPage(),
                    ),
                  ),
                ),
                (
                  'قضايا مفتوحة',
                  item.openCases.toString(),
                  Icons.balance_rounded,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveDisputesPage(),
                    ),
                  ),
                ),
                (
                  'طلبات موقع',
                  item.activeLocationRequests.toString(),
                  Icons.location_searching_rounded,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveLocationPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const MobileSectionHeader(
            title: 'بوصلة القرار',
            subtitle: 'ترتيب مقترح لما يجب مراجعته أولًا.',
          ),
          const SizedBox(height: 12),
          data.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded),
                    const SizedBox(height: 8),
                    Text(humanizeError(error), textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(executiveDashboardProvider),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
            data: (item) => Card(
              child: Column(
                children: [
                  _PriorityTile(
                    icon: Icons.priority_high_rounded,
                    color: scheme.error,
                    title: 'الإجراءات العاجلة',
                    subtitle:
                        '${item.urgentActions} عنصرًا بمهلة قصيرة أو أثر مرتفع',
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  _PriorityTile(
                    icon: Icons.approval_rounded,
                    color: scheme.primary,
                    title: 'الاعتمادات المنتظرة',
                    subtitle:
                        '${item.pendingApprovals} عنصرًا يحتاج قرارًا أو إعادة توضيح',
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  _PriorityTile(
                    icon: Icons.fact_check_outlined,
                    color: scheme.secondary,
                    title: 'تقارير KPI المعتمدة',
                    subtitle:
                        '${item.pendingFinalKpi} تقريرًا اعتمدها المديرون ومتاحًا للعرض',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: scheme.primaryContainer.withValues(alpha: .5),
            child: const ListTile(
              contentPadding: EdgeInsets.all(16),
              leading: CircleAvatar(child: Icon(Icons.security_rounded)),
              title: Text(
                'مساحة تنفيذية مستقلة',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                'لا توجد بصمة شخصية أو إرسال موقع للمدير التنفيذي، والاعتمادات الحساسة تحتاج إعادة مصادقة.',
              ),
            ),
          ),
          // قسم الإجراءات الإدارية للقضايا — يظهر فقط عند وجود قضايا معلقة
          disputeInbox.whenOrNull(
            data: (inbox) {
              final counts = inbox.counts;
              if (counts.awaitingDecision == 0 &&
                  counts.pendingExecution == 0) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const MobileSectionHeader(
                    title: 'الإجراءات الإدارية',
                    subtitle: 'قضايا تحتاج قرارًا أو متابعة تنفيذ.',
                  ),
                  const SizedBox(height: 12),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ExecutiveDisputesPage(),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  scheme.error.withValues(alpha: .12),
                              child: Icon(
                                Icons.gavel_rounded,
                                color: scheme.error,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (counts.awaitingDecision > 0)
                                    Text(
                                      '${counts.awaitingDecision} بانتظار القرار',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  if (counts.pendingExecution > 0)
                                    Text(
                                      '${counts.pendingExecution} بانتظار التنفيذ',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ) ??
              const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _PriorityTile extends StatelessWidget {
  const _PriorityTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
    leading: CircleAvatar(
      backgroundColor: color.withValues(alpha: .12),
      child: Icon(icon, color: color),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
  );
}

class _ExecutiveQuickLink extends StatelessWidget {
  const _ExecutiveQuickLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
