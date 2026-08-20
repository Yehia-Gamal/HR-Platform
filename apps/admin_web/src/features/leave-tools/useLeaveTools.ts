import { z } from 'zod';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

// ─── أنواع الإجازات (get_leave_types_admin) ─────────────────────────────────

export const leaveTypeOptionSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  nameAr: z.string(),
  isPaid: z.boolean(),
  requiresAttachment: z.boolean(),
  maxDaysPerYear: z.number().nullable(),
  affectsBalance: z.boolean(),
  color: z.string().nullable(),
});
export type LeaveTypeOption = z.infer<typeof leaveTypeOptionSchema>;

const MOCK_LEAVE_TYPES: LeaveTypeOption[] = [
  { id: 'lt-annual', code: 'annual', nameAr: 'إجازة سنوية', isPaid: true, requiresAttachment: false, maxDaysPerYear: 24, affectsBalance: true, color: null },
  { id: 'lt-casual', code: 'casual', nameAr: 'إجازة عارضة', isPaid: true, requiresAttachment: false, maxDaysPerYear: 5, affectsBalance: true, color: null },
  { id: 'lt-sick', code: 'sick', nameAr: 'إجازة مرضية', isPaid: true, requiresAttachment: false, maxDaysPerYear: null, affectsBalance: false, color: null },
  {
    id: 'lt-unpaid',
    code: 'unpaid',
    nameAr: 'إجازة بدون أجر',
    isPaid: false,
    requiresAttachment: false,
    maxDaysPerYear: null,
    affectsBalance: true,
    color: null,
  },
];

export function useLeaveTypes() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['leave-types', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<LeaveTypeOption[]> => {
      if (auth.isMock) return MOCK_LEAVE_TYPES;
      const data = await rpc<Record<string, unknown>[]>('get_leave_types_admin');
      return (data ?? []).map((row) =>
        leaveTypeOptionSchema.parse({
          id: row.id,
          code: row.code,
          nameAr: row.name_ar,
          isPaid: Boolean(row.is_paid),
          requiresAttachment: Boolean(row.requires_attachment),
          maxDaysPerYear: row.max_days_per_year != null ? Number(row.max_days_per_year) : null,
          affectsBalance: Boolean(row.affects_balance),
          color: row.color ?? null,
        }),
      );
    },
  });
}

// ─── إنشاء إجازة بدل الموظف ─────────────────────────────────────────────────

export interface CreateLeaveForEmployeeInput {
  employeeId: string;
  leaveType: string;
  startDate: string;
  endDate: string;
  reason: string;
  title?: string;
  handoverNotes?: string;
  substituteEmployeeId?: string | null;
}

export function useCreateLeaveForEmployee() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: CreateLeaveForEmployeeInput): Promise<string> => {
      if (auth.isMock) return 'mock-request-id';
      const data = await rpc<{ id?: string }>('admin_create_leave_request', {
        p_employee_id: input.employeeId,
        p_leave_type: input.leaveType,
        p_start_date: input.startDate,
        p_end_date: input.endDate,
        p_reason: input.reason,
        p_title: input.title ?? null,
        p_handover_notes: input.handoverNotes ?? null,
        p_substitute_employee_id: input.substituteEmployeeId ?? null,
      });
      return data?.id ?? 'unknown';
    },
    meta: { successMessage: 'تم إنشاء طلب الإجازة بدل الموظف بنجاح' },
    onSuccess: async () => {
      await Promise.all([
        client.invalidateQueries({ queryKey: ['admin-leaves'] }),
        client.invalidateQueries({ queryKey: ['requests'] }),
        client.invalidateQueries({ queryKey: ['employee-360'] }),
      ]);
    },
  });
}

// ─── تعديل رصيد إجازة (adjust_leave_balance) ────────────────────────────────

export interface AdjustLeaveBalanceInput {
  employeeId: string;
  leaveTypeId: string;
  year: number;
  units: number;
  reason: string;
}

export function useAdjustLeaveBalance() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: AdjustLeaveBalanceInput): Promise<string> => {
      if (auth.isMock) return 'mock-entry-id';
      const data = await rpc<{ id?: string }>('adjust_leave_balance', {
        p_employee_id: input.employeeId,
        p_leave_type_id: input.leaveTypeId,
        p_year: input.year,
        p_units: input.units,
        p_reason: input.reason,
      });
      return data?.id ?? 'unknown';
    },
    meta: { successMessage: 'تم تعديل رصيد الإجازة بنجاح' },
    onSuccess: async () => {
      await Promise.all([client.invalidateQueries({ queryKey: ['leave-balances'] }), client.invalidateQueries({ queryKey: ['employee-360'] })]);
    },
  });
}

// ─── منح بدل راحة جماعي (grant_weekly_rest_credit_bulk) ─────────────────────

export interface GrantRestCreditBulkInput {
  employeeIds: string[];
  workDate: string;
  days: number;
}

export function useGrantRestCreditBulk() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: GrantRestCreditBulkInput): Promise<number> => {
      if (auth.isMock) return input.employeeIds.length;
      const data = await rpc<number>('grant_weekly_rest_credit_bulk', {
        p_employee_ids: input.employeeIds,
        p_work_date: input.workDate,
        p_days: input.days,
      });
      return Number(data) || input.employeeIds.length;
    },
    meta: { successMessage: 'تم منح رصيد بدل الراحة بنجاح' },
    onSuccess: async () => {
      await Promise.all([
        client.invalidateQueries({ queryKey: ['employees'] }),
        client.invalidateQueries({ queryKey: ['employee-360'] }),
        client.invalidateQueries({ queryKey: ['leave-balances'] }),
      ]);
    },
  });
}

// ─── قافلة / فاندي جماعية (create_work_assignment) ──────────────────────────

export interface CreateBulkAssignmentInput {
  assignmentType: 'CONVOY' | 'FUNDRAISING';
  title: string;
  startAt: string;
  endAt: string;
  participantIds: string[];
  location?: string;
  description?: string;
  targetAmount?: number | null;
  campaignName?: string;
}

export function useCreateBulkAssignment() {
  const auth = useAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: CreateBulkAssignmentInput): Promise<string> => {
      if (auth.isMock) return 'mock-assignment-id';
      const data = await rpc<{ id?: string }>('create_work_assignment', {
        p_assignment_type: input.assignmentType,
        p_title: input.title,
        p_start_at: input.startAt,
        p_end_at: input.endAt,
        p_participant_ids: input.participantIds,
        p_description: input.description ?? null,
        p_location: input.location ?? null,
        p_payload: {
          isFullDay: true,
          campaignName: input.campaignName ?? null,
          targetAmount: input.targetAmount ?? null,
        },
      });
      return data?.id ?? 'unknown';
    },
    meta: { successMessage: 'تم إنشاء التكليف الجماعي بنجاح' },
    onSuccess: async () => {
      await Promise.all([client.invalidateQueries({ queryKey: ['work-assignments'] }), client.invalidateQueries({ queryKey: ['requests'] })]);
    },
  });
}
