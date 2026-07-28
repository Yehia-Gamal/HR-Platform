import 'package:ahla_shabab_management_os/features/mobile_pages/committee_dispute_list_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_home_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/manager_operations_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/manager_home_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/workspaces/workspace_scaffold.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';

class ManagerWorkspace extends StatefulWidget {
  const ManagerWorkspace({required this.access, super.key});

  final AccessContext access;

  @override
  State<ManagerWorkspace> createState() => _ManagerWorkspaceState();
}

class _ManagerWorkspaceState extends State<ManagerWorkspace> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    // السكرتير التنفيذي (mainAdmin) يُوجَّه إلى هذه المساحة —
    // يحتاج تبويب القضايا لإدارة لجنة حل المشكلات.
    final showDisputes =
        widget.access.workspaces.contains(WorkspaceId.mainAdmin);

    final pages = [
      EmployeeHomePage(access: widget.access),
      const ManagerHomePage(),
      const MobileRequestsPage(allowDecision: true),
      if (showDisputes) const CommitteeDisputeListPage(),
      MobileKpiPage(access: widget.access),
      const ManagerOperationsPage(),
    ];

    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'يومي',
      ),
      const NavigationDestination(
        icon: Icon(Icons.groups_outlined),
        selectedIcon: Icon(Icons.groups),
        label: 'فريقي',
      ),
      const NavigationDestination(
        icon: Icon(Icons.approval_outlined),
        selectedIcon: Icon(Icons.approval),
        label: 'الطلبات',
      ),
      if (showDisputes)
        const NavigationDestination(
          icon: Icon(Icons.gavel_outlined),
          selectedIcon: Icon(Icons.gavel),
          label: 'القضايا',
        ),
      const NavigationDestination(
        icon: Icon(Icons.speed_outlined),
        selectedIcon: Icon(Icons.speed),
        label: 'KPI',
      ),
      const NavigationDestination(
        icon: Icon(Icons.hub_outlined),
        selectedIcon: Icon(Icons.hub_rounded),
        label: 'التشغيل',
      ),
    ];

    return WorkspaceScaffold(
      title: showDisputes ? 'المساحة الإدارية' : 'مساحة المدير المباشر',
      workspace: WorkspaceId.manager,
      contextData: widget.access,
      currentIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: destinations,
      body: IndexedStack(index: index, children: pages),
    );
  }
}
