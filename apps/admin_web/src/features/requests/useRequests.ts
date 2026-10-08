import {
  leaveBalanceSchema,
  requestDetailSchema,
  requestSummarySchema,
  workAssignmentSchema,
  type RequestDetail,
  type RequestSummary,
  type WorkAssignment,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

/** قرار المعتمِد — «إعادة للتعديل» ترجع الطلب لصاحبه ليعدّله ويعيد تقديمه (0646). */
export type Decision = 'approve' | 'reject' | 'return';

export function useRequests() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['requests', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<RequestSummary[]> => {
      if (auth.isMock) return (await loadDomainMocks()).mockRequests;
      const data = await rpc('get_request_inbox', { p_limit: 100 });
      if (!Array.isArray(data)) return [];
      const parsed: RequestSummary[] = [];
      for (const item of data) {
        const result = requestSummarySchema.safeParse(item);
        if (result.success) {
          parsed.push(result.data);
        } else {
          console.warn('[useRequests] Failed to parse request item:', (item as Record<string, unknown>)?.id, result.error);
        }
      }
      return parsed;
    },
  });
}

export function useRequestDecision() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ requestId, decision, comment }: { requestId: string; decision: Decision; comment: string }) => {
      if (auth.isMock) return { id: requestId, decision };
      return rpc('decide_request', { p_request_id: requestId, p_decision: decision, p_comment: comment || null });
    },
    meta: { successMessage: 'تم البتّ في الطلب بنجاح' },
    onSuccess: () =>
      Promise.all([
        client.invalidateQueries({ queryKey: ['requests'] }),
        client.invalidateQueries({ queryKey: ['request-detail'] }),
        client.invalidateQueries({ queryKey: ['action-center'] }),
      ]),
  });
}

/** تفاصيل طلب واحد: مسار الطلب وسياق القرار للمعتمِد (get_mobile_request_detail — 0646/0651). */
export function useRequestDetail(requestId: string | null) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['request-detail', requestId, auth.isMock],
    enabled: auth.status === 'authenticated' && Boolean(requestId) && !auth.isMock,
    queryFn: async (): Promise<RequestDetail> => requestDetailSchema.parse(await rpc('get_mobile_request_detail', { p_request_id: requestId })),
  });
}

/**
 * اعتماد جماعي: قرار مستقل لكل طلب بالتتابع (الخادم يتحقق من صلاحية كل طلب على حدة)،
 * ويُعاد عدد الناجح والفاشل بدل إيقاف الكل عند أول خطأ.
 */
export function useBulkApprove() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ requestIds, comment }: { requestIds: string[]; comment: string }) => {
      let approved = 0;
      const failed: string[] = [];
      for (const id of requestIds) {
        try {
          if (!auth.isMock) await rpc('decide_request', { p_request_id: id, p_decision: 'approve', p_comment: comment || null });
          approved += 1;
        } catch {
          failed.push(id);
        }
      }
      return { approved, failed };
    },
    onSettled: () =>
      Promise.all([
        client.invalidateQueries({ queryKey: ['requests'] }),
        client.invalidateQueries({ queryKey: ['request-detail'] }),
        client.invalidateQueries({ queryKey: ['action-center'] }),
      ]),
  });
}

export function useMyLeaveBalances(year = new Date().getFullYear()) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['leave-balances', year, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () => {
      if (auth.isMock) return (await loadDomainMocks()).mockLeaveBalances;
      const data = await rpc<Record<string, unknown>[]>('get_my_leave_balances', { p_year: year });
      return leaveBalanceSchema.array().parse(
        (data ?? []).map((row: Record<string, unknown>) => ({
          leaveTypeId: row.leave_type_id,
          code: row.code,
          nameAr: row.name_ar,
          availableUnits: Number(row.available_units ?? 0),
          reservedUnits: Number(row.reserved_units ?? 0),
          consumedUnits: Number(row.consumed_units ?? 0),
          expiresAt: row.expires_at ?? null,
        })),
      );
    },
  });
}

// تكليفات العمل (مأمورية/قافلة/فاندي) — وحدة work_assignments.
export function useWorkAssignments(scope: 'mine' | 'team' = 'team') {
  const auth = useAuth();
  return useQuery({
    queryKey: ['work-assignments', scope, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<WorkAssignment[]> => {
      if (auth.isMock) return [];
      const data = await rpc<Record<string, unknown>[]>('get_work_assignments_inbox', { p_scope: scope, p_limit: 100 });
      return workAssignmentSchema.array().parse(
        (data ?? []).map((row: Record<string, unknown>) => ({
          id: row.id,
          assignmentNumber: Number(row.assignment_number ?? 0),
          assignmentType: row.assignment_type,
          title: row.title,
          description: row.description ?? null,
          status: row.status,
          createdByEmployeeId: row.created_by_employee_id ?? null,
          responsibleEmployeeId: row.responsible_employee_id ?? null,
          startAt: row.start_at,
          endAt: row.end_at,
          isFullDay: Boolean(row.is_full_day),
          location: row.location ?? null,
          countsAsWorkDay: Boolean(row.counts_as_work_day),
          needsReport: Boolean(row.needs_report),
          reportDueAt: row.report_due_at ?? null,
          targetAmount: row.target_amount != null ? Number(row.target_amount) : null,
          achievedAmount: row.achieved_amount != null ? Number(row.achieved_amount) : null,
          createdAt: row.created_at,
        })),
      );
    },
  });
}
