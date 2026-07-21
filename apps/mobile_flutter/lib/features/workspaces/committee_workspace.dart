import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_disputes_page.dart';
import 'package:ahla_shabab_management_os/features/workspaces/workspace_scaffold.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';

class CommitteeWorkspace extends StatelessWidget {
  const CommitteeWorkspace({required this.access, super.key});
  final AccessContext access;

  @override
  Widget build(BuildContext context) {
    return WorkspaceScaffold(
      title: 'لجنة حل المشكلات',
      workspace: WorkspaceId.committee,
      contextData: access,
      currentIndex: 0,
      onDestinationSelected: (_) {},
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.gavel_outlined),
          selectedIcon: Icon(Icons.gavel),
          label: 'القضايا',
        ),
      ],
      body: const MobileDisputesPage(),
    );
  }
}
