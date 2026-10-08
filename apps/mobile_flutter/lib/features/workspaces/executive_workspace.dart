import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_attendance_tab.dart';
import 'package:ahla_shabab_management_os/features/workspaces/executive_tabs.dart';
import 'package:ahla_shabab_management_os/features/workspaces/workspace_scaffold.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// المساحة التنفيذية — شريط تنقل سفلي بخمس وجهات ثابتة كبقية المساحات:
/// الرئيسية، الحضور، الاعتمادات، الموظفون، المزيد.
/// كانت ثلاث طبقات من الأشرطة والتبويبات المتداخلة (شريط المساحة + شريط
/// «المدير التنفيذي» بتبويباته + تبويبات داخلية) بلا تنقل سفلي.
class ExecutiveWorkspace extends ConsumerStatefulWidget {
  const ExecutiveWorkspace({required this.access, super.key});

  final AccessContext access;

  @override
  ConsumerState<ExecutiveWorkspace> createState() => _ExecutiveWorkspaceState();
}

class _ExecutiveWorkspaceState extends ConsumerState<ExecutiveWorkspace> {
  int _index = 0;
  final _peopleSegment = ValueNotifier<int>(0);

  @override
  void dispose() {
    _peopleSegment.dispose();
    super.dispose();
  }

  void _open(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final pending =
        ref.watch(executiveDashboardProvider).asData?.value.pendingApprovals ??
        0;
    final pages = [
      ExecutiveHomeTab(
        access: widget.access,
        onOpenTab: _open,
        onOpenLocation: () {
          _peopleSegment.value = 1;
          _open(3);
        },
      ),
      const ExecutiveAttendanceTab(),
      const ExecutiveApprovalsTab(),
      ExecutivePeopleTab(segment: _peopleSegment),
      ExecutiveMoreTab(access: widget.access),
    ];

    return WorkspaceScaffold(
      title: 'المساحة التنفيذية',
      workspace: WorkspaceId.executive,
      contextData: widget.access,
      currentIndex: _index,
      onDestinationSelected: _open,
      // «المزيد» وجهة سفلية هنا، فلا داعي لزر الخدمات المكرر في الشريط العلوي
      showServicesButton: false,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          selectedIcon: Icon(Icons.space_dashboard_rounded),
          label: 'الرئيسية',
        ),
        const NavigationDestination(
          icon: Icon(Icons.how_to_reg_outlined),
          selectedIcon: Icon(Icons.how_to_reg_rounded),
          label: 'الحضور',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: pending > 0,
            label: Text(
              pending > 99 ? '99+' : '$pending',
              textDirection: TextDirection.ltr,
            ),
            child: const Icon(Icons.approval_outlined),
          ),
          selectedIcon: Badge(
            isLabelVisible: pending > 0,
            label: Text(
              pending > 99 ? '99+' : '$pending',
              textDirection: TextDirection.ltr,
            ),
            child: const Icon(Icons.approval_rounded),
          ),
          label: 'الاعتمادات',
        ),
        const NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups_rounded),
          label: 'الموظفون',
        ),
        const NavigationDestination(
          icon: Icon(Icons.widgets_outlined),
          selectedIcon: Icon(Icons.widgets_rounded),
          label: 'المزيد',
        ),
      ],
      body: IndexedStack(index: _index, children: pages),
    );
  }
}
