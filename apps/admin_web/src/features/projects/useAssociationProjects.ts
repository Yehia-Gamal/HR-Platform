import {
  associationProjectsCatalogSchema,
  associationProjectDetailSchema,
  type AssociationProjectsCatalog,
  type AssociationProjectDetail,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const KEY = 'association-projects';

export function useAssociationProjects() {
  const a = useAuth();
  return useQuery({
    queryKey: [KEY, a.isMock],
    enabled: a.status === 'authenticated',
    queryFn: async (): Promise<AssociationProjectsCatalog> => {
      if (a.isMock) {
        return {
          projects: [],
          lastUpdatedAt: new Date().toISOString(),
        };
      }
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
      if (a.isMock) {
        throw new Error('بيانات تفصيلية غير متوفرة في وضع العرض التجريبي.');
      }
      return associationProjectDetailSchema.parse(
        await rpc('get_association_project_detail', { p_project_id: projectId }),
      );
    },
  });
}

export function useCreateAssociationProject() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      code: string;
      name: string;
      description: string;
      departmentId: string;
      ownerEmployeeId: string;
      priority: string;
      startDate: string;
      targetEndDate: string;
    }) => {
      if (a.isMock) return;
      await rpc('create_association_project_admin', {
        p_code: input.code,
        p_name: input.name,
        p_description: input.description,
        p_department_id: input.departmentId,
        p_owner_employee_id: input.ownerEmployeeId,
        p_priority: input.priority,
        p_start_date: input.startDate || null,
        p_target_end_date: input.targetEndDate || null,
      });
    },
    meta: { successMessage: 'تم إنشاء المشروع بنجاح' },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}

export function useUpdateAssociationProject() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      projectId: string;
      name: string;
      description: string;
      departmentId: string;
      ownerEmployeeId: string;
      status: string;
      priority: string;
      progress: number;
      startDate: string;
      targetEndDate: string;
    }) => {
      if (a.isMock) return;
      await rpc('update_association_project_admin', {
        p_project_id: input.projectId,
        p_name: input.name,
        p_description: input.description,
        p_department_id: input.departmentId,
        p_owner_employee_id: input.ownerEmployeeId,
        p_status: input.status,
        p_priority: input.priority,
        p_progress: input.progress,
        p_start_date: input.startDate || null,
        p_target_end_date: input.targetEndDate || null,
      });
    },
    meta: { successMessage: 'تم تحديث المشروع' },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}

export function useAddProjectUpdate() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { projectId: string; note: string; progress: number; statusChange?: string }) => {
      if (a.isMock) return;
      await rpc('add_project_update_admin', {
        p_project_id: input.projectId,
        p_note: input.note,
        p_progress: input.progress,
        p_status_change: input.statusChange || null,
      });
    },
    meta: { successMessage: 'تم إضافة التحديث' },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}

export function useUpsertProjectStep() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      projectId: string;
      stepId?: string;
      title: string;
      description: string;
      sortOrder: number;
      status: string;
      dueDate: string;
      assigneeId?: string;
    }) => {
      if (a.isMock) return;
      await rpc('upsert_project_step_admin', {
        p_project_id: input.projectId,
        p_step_id: input.stepId || null,
        p_title: input.title,
        p_description: input.description,
        p_sort_order: input.sortOrder,
        p_status: input.status,
        p_due_date: input.dueDate || null,
        p_assignee_employee_id: input.assigneeId || null,
      });
    },
    meta: { successMessage: 'تم حفظ الخطوة' },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}

export function useDeleteProjectStep() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (stepId: string) => {
      if (a.isMock) return;
      await rpc('delete_project_step_admin', { p_step_id: stepId });
    },
    meta: { successMessage: 'تم حذف الخطوة' },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}
