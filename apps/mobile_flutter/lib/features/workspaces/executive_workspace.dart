import 'package:ahla_shabab_management_os/features/mobile_pages/committee_dispute_list_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_home_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_location_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_inbox_page.dart';
import 'package:ahla_shabab_management_os/features/workspaces/workspace_scaffold.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';

/// V17 §14 — Disputes tab added for admin-action workflow.
/// Tabs: Home, Inbox, Disputes, Location, Reports.
class ExecutiveWorkspace extends StatefulWidget {
  const ExecutiveWorkspace({required this.access, super.key});

  final AccessContext access;

  @override
  State<ExecutiveWorkspace> createState() => _ExecutiveWorkspaceState();
}

class _ExecutiveWorkspaceState extends State<ExecutiveWorkspace> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ExecutiveHomePage(),
      const MobileActionInboxPage(),
      const CommitteeDisputeListPage(),
      const ExecutiveLocationPage(),
      const ExecutiveReportsPage(),
    ];

    return WorkspaceScaffold(
      title: 'المساحة التنفيذية',
      workspace: WorkspaceId.executive,
      contextData: widget.access,
      currentIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'الرئيسية',
        ),
        NavigationDestination(
          icon: Icon(Icons.inbox_outlined),
          selectedIcon: Icon(Icons.inbox),
          label: 'الوارد',
        ),
        NavigationDestination(
          icon: Icon(Icons.gavel_outlined),
          selectedIcon: Icon(Icons.gavel),
          label: 'القضايا',
        ),
        NavigationDestination(
          icon: Icon(Icons.location_searching),
          selectedIcon: Icon(Icons.location_on),
          label: 'الموقع',
        ),
        NavigationDestination(
          icon: Icon(Icons.analytics_outlined),
          selectedIcon: Icon(Icons.analytics_rounded),
          label: 'التقارير',
        ),
      ],
      body: IndexedStack(index: index, children: pages),
    );
  }
}
