import 'package:ahla_shabab_management_os/features/mobile_pages/employee_home_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_self_service_page.dart';
import 'package:ahla_shabab_management_os/features/workspaces/workspace_scaffold.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';

/// مساحة المدير — نفس تبويبات الموظف (يومي، الحضور، طلباتي، KPI، حسابي)
/// + ميزات إدارة الفريق متاحة من قائمة "الخدمات والمزيد".
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
    final pages = [
      EmployeeHomePage(access: widget.access),
      const MobileAttendancePage(),
      const MobileSelfServicePage(),
      MobileKpiPage(access: widget.access),
      const MobileProfilePage(),
    ];

    return WorkspaceScaffold(
      title: 'مساحة المدير',
      workspace: WorkspaceId.manager,
      contextData: widget.access,
      currentIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.today_outlined),
          selectedIcon: Icon(Icons.today),
          label: 'يومي',
        ),
        NavigationDestination(
          icon: Icon(Icons.fingerprint_outlined),
          selectedIcon: Icon(Icons.fingerprint),
          label: 'الحضور',
        ),
        NavigationDestination(
          icon: Icon(Icons.assignment_outlined),
          selectedIcon: Icon(Icons.assignment),
          label: 'طلباتي',
        ),
        NavigationDestination(
          icon: Icon(Icons.trending_up_outlined),
          selectedIcon: Icon(Icons.trending_up),
          label: 'KPI',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outlined),
          selectedIcon: Icon(Icons.person),
          label: 'حسابي',
        ),
      ],
      body: IndexedStack(index: index, children: pages),
    );
  }
}
