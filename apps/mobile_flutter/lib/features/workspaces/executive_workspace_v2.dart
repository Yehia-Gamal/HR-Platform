import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_brief_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/daily_reports_home_box.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/disputes_portal_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_announcement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_attendance_tab.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_emergency_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_employee_summary_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_governance_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_location_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_risk_center_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_inbox_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_notifications_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// اتجاه تنفيذي مبسط — 4 تبويبات بدلاً من 13 صفحة
class ExecutiveWorkspaceV2 extends ConsumerWidget {
  const ExecutiveWorkspaceV2({required this.access, super.key});

  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المدير التنفيذي'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.invalidate(executiveDashboardProvider);
                ref.invalidate(dailyReportsFeedProvider(null));
              },
            ),
            IconButton(
              icon: const Icon(Icons.campaign_outlined),
              onPressed: () => _showBroadcastDialog(context, ref),
              tooltip: 'تنبيه شامل',
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.auto_awesome_outlined), text: 'ملخص'),
              Tab(icon: Icon(Icons.manage_search_rounded), text: 'أشخاص'),
              Tab(icon: Icon(Icons.campaign_outlined), text: 'قرارات'),
              Tab(icon: Icon(Icons.gavel_rounded), text: 'مخاطر'),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(executiveDashboardProvider);
            ref.invalidate(dailyReportsFeedProvider(null));
          },
          child: TabBarView(
            children: [
              _BriefTab(access: access),
              _PeopleTab(access: access),
              _DecisionsTab(access: access),
              _RiskTab(access: access),
            ],
          ),
        ),
      ),
    );
  }

  void _showBroadcastDialog(BuildContext context, WidgetRef ref) {
    final commands = ref.read(mobileCommandsProvider);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إرسال تنبيه شامل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيصل التنبيه فورًا لكامل الموظفين — تومض الشاشة ويُشغَّل فلاش الجهاز والاهتزاز حتى ينتهي التنبيه أو يعطلوه. استخدمه للحالات الطارئة فقط.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'نص التنبيه (3 أحرف على الأقل)',
                hintText: 'مثال: اجتماع طارئ فورًا في المقر الرئيسي',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.length < 3) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              commands.sendBroadcastAlert(text).then((_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('أُرسل التنبيه الشامل لكل الموظفين')),
                );
              }).catchError((e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('فشل الإرسال: $e')),
                );
              });
            },
            child: const Text('إرسال الآن'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Tab 1: ملخص
// ═══════════════════════════════════════════════════════════════
class _BriefTab extends ConsumerWidget {
  const _BriefTab({required this.access});
  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(executiveDashboardProvider);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        _buildHeroCard(scheme),
        const SizedBox(height: 14),
        _buildQuickLinks(context),
        const SizedBox(height: 12),
        _DetailTile(
          icon: Icons.speed_rounded,
          label: 'التقارير التنفيذية',
          subtitle: 'مركز القيادة التشغيلية والطلبات الميدانية',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('التقارير التنفيذية')),
                body: const ExecutiveReportsPage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildUrgentAlertsSection(context, ref, scheme),
        const SizedBox(height: 20),
        const DailyReportsHomeBox(),
        const SizedBox(height: 20),
        _buildMetricsSection(context, ref, data, scheme),
        const SizedBox(height: 20),
        _buildPriorityCompass(context, ref, data, scheme),
        const SizedBox(height: 16),
        _buildSecurityNote(scheme),
        _buildDisputeSection(context, ref, scheme),
      ],
    );
  }

  Widget _buildHeroCard(ColorScheme scheme) {
    return Container(
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'الملخص التنفيذي',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              const ExcludeSemantics(
                child: Icon(Icons.auto_graph_rounded, color: Colors.white70),
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
    );
  }

  Widget _buildQuickLinks(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickLink(
            icon: Icons.auto_awesome_outlined,
            label: 'ملخص اليوم',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExecutiveBriefPage()),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _QuickLink(
            icon: Icons.manage_search_rounded,
            label: 'الموظفون',
            onTap: () => DefaultTabController.of(context).animateTo(1),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _QuickLink(
            icon: Icons.campaign_outlined,
            label: 'إعلان/قرار',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ExecutiveAnnouncementPage(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(child: _BroadcastAlertButton()),
      ],
    );
  }

  Widget _buildUrgentAlertsSection(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    final notifications = ref.watch(myNotificationsProvider);
    final urgent =
        notifications.asData?.value
            .where(
              (n) => !n.isRead && (n.priority == 'urgent' || n.priority == 'high'),
            )
            .take(3)
            .toList() ??
        const [];
    if (urgent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileSectionHeader(
          title: 'تنبيهات عاجلة',
          subtitle: 'إشعارات عالية الأولوية تنتظر اطلاعك الآن.',
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < urgent.length; i++) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: scheme.error.withValues(alpha: .12),
                    child: Icon(Icons.priority_high_rounded, color: scheme.error),
                  ),
                  title: Text(
                    urgent[i].title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    urgent[i].body?.trim().isNotEmpty == true
                        ? urgent[i].body!
                        : _urgentCategoryLabel(urgent[i].category),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MobileNotificationsPage(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _urgentCategoryLabel(String category) => switch (category) {
    'request' => 'طلب بانتظار قرار',
    'decision' => 'قرار رسمي',
    'dispute' => 'قضية مصعّدة',
    'kpi' => 'تقييم أداء',
    'announcement' => 'إعلان',
    'attendance' => 'حضور',
    'location' => 'موقع',
    _ => 'إشعار عاجل',
  };

  Widget _buildMetricsSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ExecutiveDashboardSummary> data,
    ColorScheme scheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                () => DefaultTabController.of(context).animateTo(1),
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
                    builder: (_) =>
                        MobileKpiPage(access: access, employeeOnly: false),
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
                    builder: (_) => const ExecutiveAnnouncementPage(
                      initialType: 'decision',
                    ),
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
                    builder: (_) => const DisputesPortalPage(),
                  ),
                ),
              ),
              (
                'طلبات موقع',
                item.activeLocationRequests.toString(),
                Icons.location_searching_rounded,
                () => DefaultTabController.of(context).animateTo(1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriorityCompass(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ExecutiveDashboardSummary> data,
    ColorScheme scheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                const Divider(indent: 16, endIndent: 16),
                _PriorityTile(
                  icon: Icons.gavel_rounded,
                  color: scheme.tertiary,
                  title: 'الحوكمة والامتثال',
                  subtitle: 'مراجعة السياسات والتدقيق والمخاطر المؤسسية',
                ),
                const Divider(indent: 16, endIndent: 16),
                _PriorityTile(
                  icon: Icons.warning_amber_rounded,
                  color: scheme.error,
                  title: 'إدارة الطوارئ والأزمات',
                  subtitle:
                      'خطط الاستمرارية والحوادث الحرجة والاستجابة السريعة',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityNote(ColorScheme scheme) {
    return Card(
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
    );
  }

  Widget _buildDisputeSection(BuildContext context, WidgetRef ref, ColorScheme scheme) {
    final disputeInbox = ref.watch(executiveDisputeInboxProvider);
    return disputeInbox.whenOrNull(
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
                        builder: (_) => const DisputesPortalPage(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: scheme.error.withValues(alpha: .12),
                            child: Icon(Icons.gavel_rounded, color: scheme.error),
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
        const SizedBox.shrink();
  }
}

// ════════════════════════════════════════════════════════════════
// Tab 2: أشخاص
// ═══════════════════════════════════════════════════════════════
class _PeopleTab extends ConsumerWidget {
  const _PeopleTab({required this.access});
  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people_rounded), text: 'الدليل'),
              Tab(icon: Icon(Icons.groups_rounded), text: 'الحضور'),
              Tab(icon: Icon(Icons.location_searching_rounded), text: 'الموقع'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PeopleDirectoryTab(access: access),
                const ExecutiveAttendanceTab(),
                const ExecutiveLocationPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Tab 3: قرارات
// ═══════════════════════════════════════════════════════════════
class _DecisionsTab extends ConsumerWidget {
  const _DecisionsTab({required this.access});
  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.approval_rounded), text: 'اعتمادات'),
              Tab(icon: Icon(Icons.campaign_outlined), text: 'إعلانات'),
              Tab(icon: Icon(Icons.fact_check_outlined), text: 'KPI'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const MobileActionInboxPage(),
                const ExecutiveAnnouncementPage(),
                MobileKpiPage(access: access, employeeOnly: false),
              ],
            ),
          ),
        ],
      ),
    );
    }
  }

// ════════════════════════════════════════════════════════════════
// Tab 4: مخاطر
// ═══════════════════════════════════════════════════════════════
class _RiskTab extends ConsumerWidget {
  const _RiskTab({required this.access});
  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.gavel_rounded), text: 'حوكمة'),
              Tab(icon: Icon(Icons.warning_amber_rounded), text: 'مخاطر'),
              Tab(icon: Icon(Icons.emergency_rounded), text: 'طوارئ'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const ExecutiveGovernancePage(),
                const ExecutiveRiskCenterPage(),
const ExecutiveEmergencyPage(),
              ],
            ),
          ),
        ],
      ),
);
    }
  }

/// دليـل الموظفيـن مـع تبـويب محـلي
class _PeopleDirectoryTab extends ConsumerWidget {
  const _PeopleDirectoryTab({required this.access});
  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(mobileExecutivePeopleProvider(''));
    return people.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(humanizeError(e))),
      data: (list) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = list[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: p.photoUrl != null
                    ? NetworkImage(p.photoUrl!)
                    : null,
                child: p.photoUrl == null ? const Icon(Icons.person) : null,
              ),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.jobTitle ?? p.department ?? ''),
                  if (p.pendingRequests > 0)
                    Text('${p.pendingRequests} طلبات',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExecutiveEmployeeSummaryPage(
                      employeeId: p.id,
                      employeeName: p.name,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({
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

/// بطاقة خدمة عريضة — تُستخدم لعرض خدمة كاملة بنقرة واحدة.
class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(icon, color: scheme.onPrimaryContainer),
        ),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
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

class _BroadcastAlertButton extends ConsumerStatefulWidget {
  const _BroadcastAlertButton();

  @override
  ConsumerState<_BroadcastAlertButton> createState() => _BroadcastAlertButtonState();
}

class _BroadcastAlertButtonState extends ConsumerState<_BroadcastAlertButton> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showDialog() {
    final commands = ref.read(mobileCommandsProvider);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إرسال تنبيه شامل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيصل التنبيه فورًا لكامل الموظفين — تومض الشاشة ويُشغَّل فلاش الجهاز والاهتزاز حتى ينتهي التنبيه أو يعطلوه. استخدمه للحالات الطارئة فقط.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'نص التنبيه (3 أحرف على الأقل)',
                hintText: 'مثال: اجتماع طارئ فورًا في المقر الرئيسي',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final text = _controller.text.trim();
              if (text.length < 3) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              commands.sendBroadcastAlert(text).then((_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('أُرسل التنبيه الشامل لكل الموظفين')),
                );
              }).catchError((e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('فشل الإرسال: $e')),
                );
              });
            },
            child: const Text('إرسال الآن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Semantics(
        button: true,
        label: 'تنبيه شامل',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _showDialog,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
            child: Column(
              children: [
                Icon(Icons.campaign_outlined, color: scheme.onErrorContainer),
                const SizedBox(height: 7),
                const Text(
                  'تنبيه شامل',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
}