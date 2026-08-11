import 'package:ahla_shabab_management_os/core/network/session_cleanup.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/location_incoming_overlay.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_announcement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_attendance_tab.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_brief_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_decisions_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_disputes_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_emergency_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_governance_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_people_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_risk_center_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_inbox_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/daily_reports_feed_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_disputes_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_notifications_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_official_feed_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/org_chart_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkspaceScaffold extends ConsumerWidget {
  const WorkspaceScaffold({
    required this.title,
    required this.workspace,
    required this.contextData,
    required this.body,
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final String title;
  final WorkspaceId workspace;
  final AccessContext contextData;
  final Widget body;
  final List<NavigationDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(myNotificationsProvider);
    final unread =
        notifications.asData?.value.where((item) => !item.isRead).length ?? 0;
    // V20: اعرض الاسم الثنائي (الاسم + الأب) بدل الاسم الأول فقط،
    // مع تجنّب الاسماء الطويلة التي تُقصّ في الشريط.
    final nameTokens =
        contextData.displayName.trim().split(RegExp(r'\s+'));
    final fullName = nameTokens.length >= 2
        ? '${nameTokens[0]} ${nameTokens[1]}'
        : contextData.displayName.trim();
    final greeting = _greetingForNow();

    return LocationIncomingListener(
      employeeId: contextData.employeeId,
      child: LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = constraints.maxWidth >= 980;
        return Scaffold(
          extendBody: false,
          appBar: AppBar(
            toolbarHeight: 78,
            titleSpacing: 16,
            title: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showProfile(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandLogoMark(size: 43),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$greeting $fullName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton.filledTonal(
                tooltip: 'الإشعارات',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MobileNotificationsPage(),
                  ),
                ),
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : unread.toString()),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'حسابي',
                onPressed: () => _showProfile(context),
                icon: AppAvatar(name: contextData.displayName, photoUrl: contextData.photoUrl, radius: 17),
              ),
              IconButton(
                tooltip: 'الخدمات والمزيد',
                onPressed: () => _showMore(context, ref),
                icon: const Icon(Icons.grid_view_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: useNavigationRail
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: currentIndex,
                        onDestinationSelected: onDestinationSelected,
                        extended: constraints.maxWidth >= 1240,
                        labelType: constraints.maxWidth >= 1240
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        leading: const Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: BrandLogo(compact: true, markSize: 48),
                        ),
                        destinations: destinations
                            .map(
                              (item) => NavigationRailDestination(
                                icon: item.icon,
                                selectedIcon: item.selectedIcon,
                                label: Text(item.label),
                              ),
                            )
                            .toList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1440),
                            child: body,
                          ),
                        ),
                      ),
                    ],
                  )
                : body,
          ),
          bottomNavigationBar: useNavigationRail
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: NavigationBar(
                        selectedIndex: currentIndex,
                        onDestinationSelected: onDestinationSelected,
                        destinations: destinations,
                      ),
                    ),
                  ),
                ),
        );
      },
    ),
    );
  }

  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير،';
    if (hour < 18) return 'مساء الخير،';
    return 'أهلًا،';
  }

  void _showMore(BuildContext context, WidgetRef ref) {
    final isExecutive = workspace == WorkspaceId.executive;
    final isManagerOrOps = workspace == WorkspaceId.manager ||
        workspace == WorkspaceId.fieldOperations;
    final items = <_MoreItem>[
      if (isExecutive) ...[
        // §1 — صفحات تنفيذية فقط، دون تكرار اختصارات الصفحة الرئيسية
        // ودون صفحات الموظفين الشخصية (البصمة/تصحيحاتي/تقاريري) فلا تخص
        // المدير التنفيذي هنا.
        _MoreItem(
          icon: Icons.auto_awesome_outlined,
          label: 'الملخص التنفيذي اليومي',
          page: const ExecutiveBriefPage(),
        ),
        _MoreItem(
          icon: Icons.manage_search_rounded,
          label: 'دليل الموظفين التنفيذي',
          page: const ExecutivePeoplePage(),
        ),
        _MoreItem(
          icon: Icons.people_alt_outlined,
          label: 'حضور الموظفين اليوم',
          page: Scaffold(
            appBar: AppBar(title: const Text('حضور الموظفين اليوم')),
            body: const ExecutiveAttendanceTab(),
          ),
        ),
        _MoreItem(
          icon: Icons.fact_check_outlined,
          label: 'التقييمات النهائية KPI',
          page: MobileKpiPage(access: contextData),
        ),
        _MoreItem(
          icon: Icons.description_outlined,
          label: 'إصدار قرار',
          page: const ExecutiveDecisionsPage(),
        ),
        _MoreItem(
          icon: Icons.record_voice_over_outlined,
          label: 'نشر تعميم',
          page: const ExecutiveAnnouncementPage(),
        ),
        _MoreItem(
          icon: Icons.admin_panel_settings_outlined,
          label: 'مركز القيادة والحوكمة',
          page: Scaffold(
            appBar: AppBar(title: const Text('مركز القيادة والحوكمة')),
            body: const ExecutiveGovernancePage(),
          ),
        ),
        _MoreItem(
          icon: Icons.warning_amber_rounded,
          label: 'مركز المخاطر والحوادث',
          page: const ExecutiveRiskCenterPage(),
        ),
        _MoreItem(
          icon: Icons.emergency_outlined,
          label: 'الاستجابة السريعة',
          page: const ExecutiveEmergencyPage(),
        ),
        _MoreItem(
          icon: Icons.gavel_outlined,
          label: 'القضايا التنفيذية',
          page: const ExecutiveDisputesPage(),
        ),
        _MoreItem(
          icon: Icons.approval_outlined,
          label: 'الطلبات والاعتمادات',
          page: const MobileRequestsPage(),
        ),
      ],
      // §9.1 — صندوق الإجراءات متاح لجميع الأدوار الإدارية
      if (isManagerOrOps) ...[
        _MoreItem(
          icon: Icons.inbox_rounded,
          label: 'صندوق الإجراءات',
          page: Scaffold(
            appBar: AppBar(title: const Text('صندوق الإجراءات')),
            body: const MobileActionInboxPage(),
          ),
        ),
      ],
      // V20: التقارير اليومية للجميع — زر إضافة تقرير داخل الصفحة نفسها
      _MoreItem(
        icon: Icons.newspaper_outlined,
        label: 'تقارير الجميع',
        page: const DailyReportsFeedPage(),
      ),
      _MoreItem(
        icon: Icons.campaign_outlined,
        label: 'القرارات والتعاميم',
        page: MobileOfficialFeedPage(
          canPublish: isExecutive ||
              contextData.hasAnyPermission(const [
                'posts.publish',
                'comms.announcement.manage',
                'comms.decision.manage',
              ]),
        ),
      ),
      // V20: الهيكل التنظيمي والشكاوى متاحة للجميع
      _MoreItem(
        icon: Icons.account_tree_rounded,
        label: 'الهيكل التنظيمي',
        page: const OrgChartPage(),
      ),
      _MoreItem(
        icon: Icons.gavel_rounded,
        label: 'الشكاوى ولجنة الخلافات',
        page: const MobileDisputesPage(),
      ),
      _MoreItem(
        icon: Icons.account_circle_rounded,
        label: 'حسابي وملفي',
        page: const MobileProfilePage(),
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MobileSectionHeader(
                title: 'الخدمات والمزيد',
                subtitle: 'خدماتك الإضافية حسب صلاحيات الحساب.',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.7,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Semantics(
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => item.page),
                          );
                        },
                        child: Ink(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                child: Icon(
                                  item.icon,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await cleanupOnSignOut();
                  await ref.read(supabaseProvider).auth.signOut();
                  ref.invalidate(accessContextProvider);
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfile(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(name: contextData.displayName, photoUrl: contextData.photoUrl, radius: 34),
            const SizedBox(height: 12),
            Text(
              contextData.displayName,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              contextData.employeeCode ?? 'بدون كود موظف',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('الأدوار'),
                    subtitle: Text(contextData.roles.join('، ')),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.security_outlined),
                    title: const Text('الصلاحيات الفعالة'),
                    subtitle: Text('${contextData.permissions.length} صلاحية'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MobileProfilePage()),
                );
              },
              icon: const Icon(Icons.person_outline_rounded),
              label: const Text('فتح الملف الكامل'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MoreItem {
  const _MoreItem({
    required this.icon,
    required this.label,
    required this.page,
  });
  final IconData icon;
  final String label;
  final Widget page;
}
