import 'package:ahla_shabab_management_os/features/mobile_pages/employee_home_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/manager_operations_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_disputes_page.dart';
import 'package:ahla_shabab_management_os/features/workspaces/workspace_scaffold.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';

class OperationsWorkspace extends StatefulWidget {
  const OperationsWorkspace({required this.access, super.key});
  final AccessContext access;
  @override
  State<OperationsWorkspace> createState() => _OperationsWorkspaceState();
}

class _OperationsWorkspaceState extends State<OperationsWorkspace> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      EmployeeHomePage(access: widget.access),
      const MobileRequestsPage(allowDecision: true),
      const ExecutiveDisputesPage(),
      MobileKpiPage(access: widget.access),
      const ManagerOperationsPage(),
    ];
    return WorkspaceScaffold(
      title: 'مساحة التشغيل',
      workspace: WorkspaceId.fieldOperations,
      contextData: widget.access,
      currentIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'يومي',
        ),
        NavigationDestination(
          icon: Icon(Icons.approval_outlined),
          selectedIcon: Icon(Icons.approval),
          label: 'الطلبات',
        ),
        NavigationDestination(
          icon: Icon(Icons.gavel_outlined),
          selectedIcon: Icon(Icons.gavel),
          label: 'اللجنة',
        ),
        NavigationDestination(
          icon: Icon(Icons.speed_outlined),
          selectedIcon: Icon(Icons.speed),
          label: 'KPI',
        ),
        NavigationDestination(
          icon: Icon(Icons.hub_outlined),
          selectedIcon: Icon(Icons.hub_rounded),
          label: 'التشغيل',
        ),
      ],
      body: IndexedStack(index: index, children: pages),
    );
  }
}
