import {
  associationProjectsCatalogSchema,
  associationProjectDetailSchema,
  associationProjectPickersSchema,
  type AssociationProjectsCatalog,
  type AssociationProjectDetail,
  type AssociationProjectPickers,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { mockCatalog, mockDetail, mockPickers } from './projectMocks';

const KEY = 'association-projects';

/** كل الطفرات تُبطل القائمة والتفاصيل معاً (نفس البادئة). */
function useProjectMutation<TInput>(rpcCall: (input: TInput) => Promise<unknown>, successMessage: string) {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: TInput) => {
      if (a.isMock) return;
      await rpcCall(input);
    },
    meta: { successMessage },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}

/** [refetchMs]: وضع العرض على الشاشة الكبيرة يحدّث كل دقيقة. */
export function useAssociationProjects(refetchMs = 5 * 60_000) {
  const a = useAuth();
  return useQuery({
    queryKey: [KEY, a.isMock],
    enabled: a.status === 'authenticated',
    // اللمبة تعتمد على الزمن — نُحدّث اللوحة دورياً ما دامت مفتوحة.
    refetchInterval: refetchMs,
    refetchIntervalInBackground: true,
    queryFn: async (): Promise<AssociationProjectsCatalog> => {
      if (a.isMock) return mockCatalog();
      return associationProjectsCatalogSchema.parse(await rpc('get_association_projects'));
    },
  });
}

export function useAssociationProjectDetail(projectId: string | null) {
  const a = useAuth();
  return useQuery({
    queryKey: [KEY, 'detail', projectId, a.isMock],
    enabled: a.status === 'authenticated' && !!projectId,
    queryFn: async (): Promise<AssociationProjectDetail> => {
      if (a.isMock) return mockDetail(projectId ?? '');
      return associationProjectDetailSchema.parse(await rpc('get_association_project_detail', { p_project_id: projectId }));
    },
  });
}

/** الموظفون والإدارات لاختيار فريق المشروع (متاحة لكل موظف). */
export function useProjectPickers(enabled = true) {
  const a = useAuth();
  return useQuery({
    queryKey: [KEY, 'pickers', a.isMock],
    enabled: enabled && a.status === 'authenticated',
    staleTime: 10 * 60_000,
    queryFn: async (): Promise<AssociationProjectPickers> => {
      if (a.isMock) return mockPickers();
      return associationProjectPickersSchema.parse(await rpc('get_association_project_pickers'));
    },
  });
}

export interface ProjectFormInput {
  /** غيابه = إنشاء مشروع جديد. */
  projectId?: string;
  code: string;
  name: string;
  description: string;
  priority: string;
  startDate: string;
  targetEndDate: string;
  /** قائد المشروع — فارغ عند الإنشاء = المستخدم الحالي. */
  leaderId: string | null;
  memberIds: string[];
  departmentIds: string[];
}

/** إنشاء/تعديل كامل بالفريق والإدارات (0645 — save_association_project). */
export function useSaveAssociationProject() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    // يُرجع معرّف المشروع حتى يمكن إرساله للاعتماد مباشرة بعد الإنشاء.
    mutationFn: async (input: ProjectFormInput & { submit?: boolean }): Promise<string | null> => {
      if (a.isMock) return null;
      const projectId = await rpc<string>('save_association_project', {
        p_project_id: input.projectId ?? null,
        p_name: input.name,
        p_description: input.description || null,
        p_priority: input.priority,
        p_start_date: input.startDate || null,
        p_target_end_date: input.targetEndDate || null,
        p_leader_id: input.leaderId || null,
        p_member_ids: input.memberIds,
        p_department_ids: input.departmentIds,
        p_code: input.projectId ? null : input.code || null,
      });
      if (input.submit && projectId) {
        await rpc('submit_project_for_approval', { p_project_id: projectId });
      }
      return projectId;
    },
    meta: { successMessage: 'تم حفظ المشروع' },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}

export function useAddProjectUpdate() {
  return useProjectMutation(
    (input: { projectId: string; note: string; progress: number | null; statusChange?: string | null }) =>
      rpc('add_project_update_admin', {
        p_project_id: input.projectId,
        p_note: input.note,
        p_progress: input.progress,
        p_status_change: input.statusChange || null,
      }),
    'تم تسجيل التحديث',
  );
}

export function useUpsertProjectStep() {
  return useProjectMutation(
    (input: {
      projectId: string;
      stepId?: string;
      title: string;
      description: string;
      sortOrder: number | null;
      status: string;
      dueDate: string;
      assigneeId?: string | null;
    }) =>
      rpc('upsert_project_step_admin', {
        p_project_id: input.projectId,
        p_step_id: input.stepId || null,
        p_title: input.title,
        p_description: input.description || null,
        p_sort_order: input.sortOrder,
        p_status: input.status,
        p_due_date: input.dueDate || null,
        p_assignee_employee_id: input.assigneeId || null,
      }),
    'تم حفظ الخطوة',
  );
}

export function useSetProjectStepStatus() {
  return useProjectMutation(
    (input: { stepId: string; status: string }) => rpc('set_project_step_status', { p_step_id: input.stepId, p_status: input.status }),
    'تم تحديث حالة الخطوة',
  );
}

export function useDeleteProjectStep() {
  return useProjectMutation((stepId: string) => rpc('delete_project_step_admin', { p_step_id: stepId }), 'تم حذف الخطوة');
}

export function useSubmitProjectForApproval() {
  return useProjectMutation((projectId: string) => rpc('submit_project_for_approval', { p_project_id: projectId }), 'تم إرسال المشروع للاعتماد');
}

export function useApproveProject() {
  return useProjectMutation((projectId: string) => rpc('approve_project', { p_project_id: projectId }), 'تم اعتماد المشروع');
}

export function useRejectProject() {
  return useProjectMutation(
    (input: { projectId: string; reason?: string }) => rpc('reject_project', { p_project_id: input.projectId, p_reason: input.reason || null }),
    'تمت إعادة المشروع للإدارة',
  );
}

export function useDeleteAssociationProject() {
  return useProjectMutation((projectId: string) => rpc('delete_association_project', { p_project_id: projectId }), 'تم حذف المشروع');
}

export function useSetProjectSettings() {
  return useProjectMutation(
    (input: { warningDays: number; criticalDays: number }) =>
      rpc('set_association_project_settings', { p_warning_days: input.warningDays, p_critical_days: input.criticalDays }),
    'تم حفظ إعدادات التنبيه',
  );
}
