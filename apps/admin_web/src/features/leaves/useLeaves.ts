import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { leaveAdminResponseSchema, type LeaveAdminResponse } from '@ahla/shared-contracts';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export interface LeaveAdminFilter {
  year?: number;
  status?: string;
  leaveType?: string;
  employeeId?: string;
  limit?: number;
  offset?: number;
}

type LeaveDecision = 'approve' | 'reject';

const EMPTY: LeaveAdminResponse = { total: 0, rows: [] };

export function useAdminLeaves(filter: LeaveAdminFilter = {}) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['admin-leaves', filter, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<LeaveAdminResponse> => {
      if (auth.isMock) return EMPTY;
      const data = await rpc('get_leave_requests_admin', {
        p_year:        filter.year        ?? new Date().getFullYear(),
        p_status:      filter.status      ?? null,
        p_leave_type:  filter.leaveType   ?? null,
        p_employee_id: filter.employeeId  ?? null,
        p_limit:       filter.limit       ?? 100,
        p_offset:      filter.offset      ?? 0,
      });
      return leaveAdminResponseSchema.parse(data ?? EMPTY);
    },
  });
}

export function useAdminLeaveDecision() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async ({ requestId, decision, comment }: { requestId: string; decision: LeaveDecision; comment?: string }) => {
      if (auth.isMock) return null;
      return rpc('decide_request', { p_request_id: requestId, p_decision: decision, p_comment: comment || null });
    },
    meta: { successMessage: 'تم البتّ في طلب الإجازة بنجاح' },
    onSuccess: () => client.invalidateQueries({ queryKey: ['admin-leaves'] }),
  });
}
