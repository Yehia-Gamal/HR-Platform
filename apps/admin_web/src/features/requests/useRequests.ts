import {
  leaveBalanceSchema,
  requestSummarySchema,
  workAssignmentSchema,
  type RequestSummary,
  type WorkAssignment,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

type Decision = 'approve' | 'reject';

export function useRequests() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['requests', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<RequestSummary[]> => {
      if (auth.isMock) return (await loadDomainMocks()).mockRequests;
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_request_inbox', { p_limit: 100 });
      if (error) throw error;
      return requestSummarySchema.array().parse(data ?? []);
    },
  });
}

export function useRequestDecision() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ requestId, decision, comment }: { requestId: string; decision: Decision; comment: string }) => {
      if (auth.isMock) return { id: requestId, decision };
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('decide_request', { p_request_id: requestId, p_decision: decision, p_comment: comment || null });
      if (error) throw error;
      return data;
    },
    onSuccess: () => Promise.all([
      client.invalidateQueries({ queryKey: ['requests'] }),
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
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_my_leave_balances', { p_year: year });
      if (error) throw error;
      return leaveBalanceSchema.array().parse((data ?? []).map((row: Record<string, unknown>) => ({
        leaveTypeId: row.leave_type_id,
        code: row.code,
        nameAr: row.name_ar,
        availableUnits: Number(row.available_units ?? 0),
        reservedUnits: Number(row.reserved_units ?? 0),
        consumedUnits: Number(row.consumed_units ?? 0),
        expiresAt: row.expires_at ?? null,
      })));
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
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_work_assignments_inbox', { p_scope: scope, p_limit: 100 });
      if (error) throw error;
      return workAssignmentSchema.array().parse((data ?? []).map((row: Record<string, unknown>) => ({
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
      })));
    },
  });
}

// صلاحيات السكرتير التنفيذي على الطلبات (نقل/تمديد/سحب تصعيد).
export function useSecretaryRequestActions() {
  const auth = useAuth();
  const client = useQueryClient();
  const invalidate = () => Promise.all([
    client.invalidateQueries({ queryKey: ['requests'] }),
    client.invalidateQueries({ queryKey: ['action-center'] }),
  ]);
  const reassign = useMutation({
    mutationFn: async ({ requestId, newManagerId, reason }: { requestId: string; newManagerId: string; reason: string }) => {
      if (auth.isMock) return { id: requestId };
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('reassign_request', { p_request_id: requestId, p_new_manager_id: newManagerId, p_reason: reason });
      if (error) throw error;
      return data;
    },
    onSuccess: invalidate,
  });
  const extendDeadline = useMutation({
    mutationFn: async ({ requestId, hours, reason }: { requestId: string; hours: number; reason: string }) => {
      if (auth.isMock) return { id: requestId };
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('extend_request_deadline', { p_request_id: requestId, p_hours: hours, p_reason: reason });
      if (error) throw error;
      return data;
    },
    onSuccess: invalidate,
  });
  const withdrawEscalation = useMutation({
    mutationFn: async ({ requestId, reason }: { requestId: string; reason: string }) => {
      if (auth.isMock) return { id: requestId };
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('withdraw_escalation', { p_request_id: requestId, p_reason: reason });
      if (error) throw error;
      return data;
    },
    onSuccess: invalidate,
  });
  return { reassign, extendDeadline, withdrawEscalation };
}
