import 'package:ahla_shabab_management_os/features/workspaces/executive_workspace_v2.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// نقطة الدخول المبسطة للمدير التنفيذي — تنقل للمساحة التنفيذية الموحدة
class ExecutiveHomePage extends ConsumerWidget {
  const ExecutiveHomePage({required this.access, super.key});

  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExecutiveWorkspace(access: access);
  }
}