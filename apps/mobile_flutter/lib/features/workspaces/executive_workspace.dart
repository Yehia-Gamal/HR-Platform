import 'package:ahla_shabab_management_os/features/mobile_pages/executive_home_page.dart';
import 'package:ahla_shabab_management_os/features/workspaces/workspace_scaffold.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';

/// V23 — المساحة التنفيذية الموحّدة: تبويبات ExecutiveWorkspaceV2 الثلاثة
/// (ملخص/أشخاص/قرارات) هي سطح التنقل الوحيد، بلا شريط سفلي مكرر
/// للخدمات المتشابهة.
class ExecutiveWorkspace extends StatefulWidget {
  const ExecutiveWorkspace({required this.access, super.key});

  final AccessContext access;

  @override
  State<ExecutiveWorkspace> createState() => _ExecutiveWorkspaceState();
}

class _ExecutiveWorkspaceState extends State<ExecutiveWorkspace> {
  @override
  Widget build(BuildContext context) {
    return WorkspaceScaffold(
      title: 'المساحة التنفيذية',
      workspace: WorkspaceId.executive,
      contextData: widget.access,
      currentIndex: 0,
      onDestinationSelected: (_) {},
      destinations: const [],
      body: ExecutiveHomePage(access: widget.access),
    );
  }
}
