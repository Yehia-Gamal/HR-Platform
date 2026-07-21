import 'package:ahla_shabab_management_os/features/mobile_pages/employee_home_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_official_feed_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_tasks_page.dart';
import 'package:ahla_shabab_management_os/features/workspaces/workspace_scaffold.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';

class EmployeeWorkspace extends StatefulWidget {
  const EmployeeWorkspace({required this.access, super.key});
  final AccessContext access;
  @override
  State<EmployeeWorkspace> createState() => _EmployeeWorkspaceState();
}

class _EmployeeWorkspaceState extends State<EmployeeWorkspace> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      EmployeeHomePage(access: widget.access),
      const MobileRequestsPage(allowDecision: false),
      const MobileTasksPage(),
      MobileKpiPage(access: widget.access),
      const MobileOfficialFeedPage(),
    ];
    return WorkspaceScaffold(
      title: 'مساحة الموظف',
      workspace: WorkspaceId.employee,
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
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description),
          label: 'طلباتي',
        ),
        NavigationDestination(
          icon: Icon(Icons.task_outlined),
          selectedIcon: Icon(Icons.task_alt),
          label: 'مهامي',
        ),
        NavigationDestination(
          icon: Icon(Icons.speed_outlined),
          selectedIcon: Icon(Icons.speed),
          label: 'تقييمي',
        ),
        NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          selectedIcon: Icon(Icons.campaign),
          label: 'القرارات',
        ),
      ],
      body: IndexedStack(index: index, children: pages),
    );
  }
}
