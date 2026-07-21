import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/location_incoming_overlay.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_brief_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_emergency_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_governance_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_people_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_risk_center_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_services_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_disputes_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_learning_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_notifications_page.dart';

import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_privacy_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_official_feed_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_service_portal_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
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
    final firstName =
        contextData.displayName.trim().split(' ').firstOrNull ??
        contextData.displayName;
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
                            '$greeting $firstName',
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
                icon: _Avatar(name: contextData.displayName, radius: 17),
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
    final isManager = workspace == WorkspaceId.manager;
    final items = <_MoreItem>[
      if (isExecutive) ...[
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
          icon: Icons.emergency_outlined,
          label: 'وضع الاستجابة السريعة',
          page: const ExecutiveEmergencyPage(),
        ),
        _MoreItem(
          icon: Icons.warning_amber_rounded,
          label: 'مركز المخاطر والحوادث',
          page: const ExecutiveRiskCenterPage(),
        ),
        _MoreItem(
          icon: Icons.fact_check_outlined,
          label: 'التقييمات النهائية KPI',
          page: MobileKpiPage(access: contextData),
        ),
        _MoreItem(
          icon: Icons.campaign_outlined,
          label: 'القرارات والتعاميم',
          page: const MobileOfficialFeedPage(),
        ),
        _MoreItem(
          icon: Icons.analytics_outlined,
          label: 'صندوق التقارير التنفيذي',
          page: const _StandalonePage(
            title: 'التقارير التنفيذية',
            child: ExecutiveReportsPage(),
          ),
        ),
        _MoreItem(
          icon: Icons.account_balance_outlined,
          label: 'الحوكمة والتنفيذ',
          page: const _StandalonePage(
            title: 'الحوكمة والتنفيذ',
            child: ExecutiveGovernancePage(),
          ),
        ),
      ],
      if (isManager)
        _MoreItem(
          icon: Icons.campaign_outlined,
          label: 'القرارات والتعاميم',
          page: const MobileOfficialFeedPage(),
        ),
      if (contextData.attendancePolicy.attendanceRequired)
        _MoreItem(
          icon: Icons.edit_calendar_rounded,
          label: 'جدولي وتصحيحات الحضور',
          page: const MobileAttendanceServicesPage(),
        ),
      _MoreItem(
        icon: Icons.support_agent_rounded,
        label: 'مكتب الخدمات',
        page: const MobileServicePortalPage(),
      ),
      _MoreItem(
        icon: Icons.school_rounded,
        label: 'التدريب والتعلم',
        page: const MobileLearningPage(),
      ),
      _MoreItem(
        icon: Icons.gavel_rounded,
        label: 'الشكاوى ولجنة الخلافات',
        page: const MobileDisputesPage(),
      ),

      _MoreItem(
        icon: Icons.privacy_tip_rounded,
        label: 'الخصوصية وبياناتي',
        page: const MobilePrivacyPage(),
      ),
      if (contextData.attendancePolicy.selfPunchEnabled)
        _MoreItem(
          icon: Icons.fingerprint_rounded,
          label: 'أجهزة Passkey',
          page: const PasskeyDevicesPage(),
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
                    return InkWell(
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
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
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
            _Avatar(name: contextData.displayName, radius: 34),
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

class _StandalonePage extends StatelessWidget {
  const _StandalonePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.radius = 21});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
    child: Text(
      name.trim().isEmpty ? 'م' : name.trim().substring(0, 1),
      style: TextStyle(fontWeight: FontWeight.w900, fontSize: radius * .75),
    ),
  );
}

extension _FirstOrNullExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
