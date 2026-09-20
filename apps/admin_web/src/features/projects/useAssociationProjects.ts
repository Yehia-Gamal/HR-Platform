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
        const now = new Date().toISOString();
        const daysAgo = (d: number) => new Date(Date.now() - d * 86400000).toISOString();
        return {
          projects: [
            {
              id: '1',
              code: 'PRJ-001',
              name: 'تطبيق إدارة الحضور',
              description: 'تطبيق موبايل لإدارة حضور الموظفين',
              departmentId: 'd1',
              departmentName: 'تقنية المعلومات',
              ownerId: 'e1',
              ownerName: 'أحمد محمد',
              status: 'active',
              approvalStatus: 'approved',
              priority: 'critical',
              progress: 75,
              startDate: '2026-01-01',
              targetEndDate: '2026-06-30',
              lastUpdateAt: daysAgo(2),
              lastUpdateNote: 'تم تسليم النسخة التجريبية',
              totalSteps: 8,
              completedSteps: 6,
              remainingSteps: 2,
              blockedSteps: 0,
              ledStatus: 'active',
              approvedBy: null,
              approvedAt: now,
              rejectionReason: null,
            },
            {
              id: '2',
              code: 'PRJ-002',
              name: 'نظام الراتب الإلكتروني',
              description: 'نظام إلكتروني لإدارة الرواتب',
              departmentId: 'd2',
              departmentName: 'الموارد البشرية',
              ownerId: 'e2',
              ownerName: 'سارة العلي',
              status: 'active',
              approvalStatus: 'approved',
              priority: 'high',
              progress: 45,
              startDate: '2026-02-01',
              targetEndDate: '2026-08-30',
              lastUpdateAt: daysAgo(5),
              lastUpdateNote: 'إكمال مرحلة التحليل',
              totalSteps: 10,
              completedSteps: 4,
              remainingSteps: 6,
              blockedSteps: 0,
              ledStatus: 'active',
              approvedBy: null,
              approvedAt: now,
              rejectionReason: null,
            },
            {
              id: '3',
              code: 'PRJ-003',
              name: 'Portal الموظفين',
              description: 'Portal موحد لخدمات الموظفين',
              departmentId: 'd1',
              departmentName: 'تقنية المعلومات',
              ownerId: 'e1',
              ownerName: 'أحمد محمد',
              status: 'on_hold',
              approvalStatus: 'approved',
              priority: 'medium',
              progress: 20,
              startDate: '2026-03-01',
              targetEndDate: '2026-09-30',
              lastUpdateAt: daysAgo(20),
              lastUpdateNote: 'انتظار الموافقة على الميزانية',
              totalSteps: 6,
              completedSteps: 1,
              remainingSteps: 5,
              blockedSteps: 1,
              ledStatus: 'halted',
              approvedBy: null,
              approvedAt: now,
              rejectionReason: null,
            },
            {
              id: '4',
              code: 'PRJ-004',
              name: 'تحسين الموقع الإلكتروني',
              description: 'تحسين تجربة المستخدم للموقع',
              departmentId: 'd3',
              departmentName: 'التسويق',
              ownerId: 'e3',
              ownerName: 'خالد الشمري',
              status: 'planned',
              approvalStatus: 'pending_approval',
              priority: 'medium',
              progress: 0,
              startDate: null,
              targetEndDate: null,
              lastUpdateAt: null,
              lastUpdateNote: null,
              totalSteps: 0,
              completedSteps: 0,
              remainingSteps: 0,
              blockedSteps: 0,
              ledStatus: 'pending',
              approvedBy: null,
              approvedAt: null,
              rejectionReason: null,
            },
            {
              id: '5',
              code: 'PRJ-005',
              name: 'تطبيق التدريب',
              description: 'منصة تدريب إلكتروني',
              departmentId: 'd2',
              departmentName: 'الموارد البشرية',
              ownerId: 'e2',
              ownerName: 'سارة العلي',
              status: 'planned',
              approvalStatus: 'draft',
              priority: 'low',
              progress: 0,
              startDate: null,
              targetEndDate: null,
              lastUpdateAt: null,
              lastUpdateNote: null,
              totalSteps: 0,
              completedSteps: 0,
              remainingSteps: 0,
              blockedSteps: 0,
              ledStatus: 'draft',
              approvedBy: null,
              approvedAt: null,
              rejectionReason: null,
            },
            {
              id: '6',
              code: 'PRJ-006',
              name: 'نظام المخازن',
              description: 'إدارة مخازن الجمعية',
              departmentId: 'd4',
              departmentName: 'الخدمات اللوجستية',
              ownerId: 'e4',
              ownerName: 'محمد الحربي',
              status: 'completed',
              approvalStatus: 'approved',
              priority: 'high',
              progress: 100,
              startDate: '2025-06-01',
              targetEndDate: '2025-12-31',
              lastUpdateAt: daysAgo(60),
              lastUpdateNote: 'تم التسليم',
              totalSteps: 5,
              completedSteps: 5,
              remainingSteps: 0,
              blockedSteps: 0,
              ledStatus: 'stale',
              approvedBy: null,
              approvedAt: now,
              rejectionReason: null,
            },
            {
              id: '7',
              code: 'PRJ-007',
              name: 'تطبيق التواصل الداخلي',
              description: 'تطبيق محادثة داخلي للموظفين',
              departmentId: 'd1',
              departmentName: 'تقنية المعلومات',
              ownerId: 'e1',
              ownerName: 'أحمد محمد',
              status: 'planned',
              approvalStatus: 'rejected',
              priority: 'medium',
              progress: 0,
              startDate: null,
              targetEndDate: null,
              lastUpdateAt: null,
              lastUpdateNote: null,
              totalSteps: 0,
              completedSteps: 0,
              remainingSteps: 0,
              blockedSteps: 0,
              ledStatus: 'rejected',
              approvedBy: null,
              approvedAt: null,
              rejectionReason: 'يجب دراسة بدائل متوفرة في السوق أولاً',
            },
          ],
          lastUpdatedAt: now,
          isFullAccess: true,
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
      return associationProjectDetailSchema.parse(await rpc('get_association_project_detail', { p_project_id: projectId }));
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

export function useUpdateProjectStatus() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { projectId: string; status: string }) => {
      if (a.isMock) return;
      await rpc('update_association_project_admin', {
        p_project_id: input.projectId,
        p_status: input.status,
      });
    },
    meta: { successMessage: 'تم تحديث الحالة' },
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

export function useSubmitProjectForApproval() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (projectId: string) => {
      if (a.isMock) return;
      await rpc('submit_project_for_approval', { p_project_id: projectId });
    },
    meta: { successMessage: 'تم إرسال المشروع للموافقة' },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}

export function useApproveProject() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (projectId: string) => {
      if (a.isMock) return;
      await rpc('approve_project', { p_project_id: projectId });
    },
    meta: { successMessage: 'تمت الموافقة على المشروع' },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}

export function useRejectProject() {
  const a = useAuth();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { projectId: string; reason?: string }) => {
      if (a.isMock) return;
      await rpc('reject_project', {
        p_project_id: input.projectId,
        p_reason: input.reason || null,
      });
    },
    meta: { successMessage: 'تم رفض المشروع' },
    onSuccess: () => qc.invalidateQueries({ queryKey: [KEY] }),
  });
}
