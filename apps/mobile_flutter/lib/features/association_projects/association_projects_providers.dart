import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_models.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// قائمة المشاريع المرئية للمستخدم — الخادم يحصرها (المدير التنفيذي = الكل،
/// غيره = مشاريع إدارته).
final associationProjectsProvider = FutureProvider.autoDispose<AssociationProjectsCatalog>((ref) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>('get_association_projects'),
  );
  return AssociationProjectsCatalog.fromJson(data);
});

final associationProjectDetailProvider =
    FutureProvider.autoDispose.family<AssociationProjectDetail, String>((ref, projectId) async {
  final data = await rpcWithTimeout(
    ref.watch(supabaseProvider).rpc<dynamic>(
      'get_association_project_detail',
      params: {'p_project_id': projectId},
    ),
  );
  // isFullAccess يُستخدم فقط لاشتقاق الصلاحيات إن لم يُرجعها الخادم.
  final catalog = ref.read(associationProjectsProvider).value;
  return AssociationProjectDetail.fromJson(
    Map<String, dynamic>.from(data as Map),
    isFullAccess: catalog?.isFullAccess ?? false,
  );
});

final associationProjectCommandsProvider = Provider<AssociationProjectCommands>(
  (ref) => AssociationProjectCommands(ref),
);

/// كل عمليات المشاريع تمر عبر RPCs المحصّنة، ثم تُحدّث القائمة والتفاصيل.
class AssociationProjectCommands {
  AssociationProjectCommands(this.ref);
  final Ref ref;

  Future<dynamic> _call(String fn, Map<String, dynamic> params, {String? projectId}) async {
    final result = await rpcWithTimeout(ref.read(supabaseProvider).rpc<dynamic>(fn, params: params));
    ref.invalidate(associationProjectsProvider);
    if (projectId != null) ref.invalidate(associationProjectDetailProvider(projectId));
    return result;
  }

  Future<String?> create({
    required String name,
    required String description,
    required String departmentId,
    required String priority,
    DateTime? targetEndDate,
    bool submit = true,
  }) async {
    final id = await _call('create_association_project_admin', {
      'p_code': null,
      'p_name': name,
      'p_description': description.isEmpty ? null : description,
      'p_department_id': departmentId,
      'p_owner_employee_id': null,
      'p_priority': priority,
      'p_start_date': null,
      'p_target_end_date': targetEndDate == null ? null : _isoDate(targetEndDate),
    });
    final projectId = id?.toString();
    if (submit && projectId != null) {
      await _call('submit_project_for_approval', {'p_project_id': projectId});
    }
    return projectId;
  }

  Future<void> submit(String projectId) =>
      _call('submit_project_for_approval', {'p_project_id': projectId}, projectId: projectId);

  Future<void> approve(String projectId) =>
      _call('approve_project', {'p_project_id': projectId}, projectId: projectId);

  Future<void> reject(String projectId, String reason) =>
      _call('reject_project', {'p_project_id': projectId, 'p_reason': reason}, projectId: projectId);

  Future<void> addUpdate(String projectId, {required String note, String? statusChange, double? progress}) =>
      _call('add_project_update_admin', {
        'p_project_id': projectId,
        'p_note': note,
        'p_progress': progress,
        'p_status_change': statusChange,
      }, projectId: projectId);

  Future<void> setStepStatus(String projectId, String stepId, String status) =>
      _call('set_project_step_status', {'p_step_id': stepId, 'p_status': status}, projectId: projectId);

  Future<void> upsertStep(
    String projectId, {
    String? stepId,
    required String title,
    String? description,
    int? sortOrder,
    String status = 'pending',
    DateTime? dueDate,
  }) =>
      _call('upsert_project_step_admin', {
        'p_project_id': projectId,
        'p_step_id': stepId,
        'p_title': title,
        'p_description': description,
        'p_sort_order': sortOrder,
        'p_status': status,
        'p_due_date': dueDate == null ? null : _isoDate(dueDate),
        'p_assignee_employee_id': null,
      }, projectId: projectId);

  Future<void> deleteStep(String projectId, String stepId) =>
      _call('delete_project_step_admin', {'p_step_id': stepId}, projectId: projectId);

  Future<void> deleteProject(String projectId) =>
      _call('delete_association_project', {'p_project_id': projectId});

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
