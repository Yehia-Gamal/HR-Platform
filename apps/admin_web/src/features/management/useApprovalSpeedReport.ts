import { z } from 'zod';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export const approvalSpeedSummarySchema = z.object({
  total_decisions: z.number(),
  total_approved: z.number(),
  total_rejected: z.number(),
  avg_turnaround_hours: z.number(),
  median_turnaround_hours: z.number(),
  total_pending: z.number(),
  total_escalated: z.number(),
});

export const approverSpeedItemSchema = z.object({
  approver_id: z.string().nullable().optional(),
  name: z.string(),
  code: z.string().optional().default(''),
  total_decisions: z.number(),
  approved_count: z.number(),
  rejected_count: z.number(),
  avg_hours: z.number(),
  median_hours: z.number(),
  escalated_count: z.number(),
  pending_count: z.number(),
  oldest_pending_hours: z.number(),
});

export const byRequestTypeSpeedItemSchema = z.object({
  request_type: z.string(),
  decisions_count: z.number(),
  avg_hours: z.number(),
  median_hours: z.number(),
});

export const approvalSpeedReportSchema = z.object({
  summary: approvalSpeedSummarySchema,
  approvers: z.array(approverSpeedItemSchema),
  byRequestType: z.array(byRequestTypeSpeedItemSchema),
  period: z.object({
    from: z.string().nullable().optional(),
    to: z.string().nullable().optional(),
  }),
});

export type ApprovalSpeedReport = z.infer<typeof approvalSpeedReportSchema>;
export type ApprovalSpeedSummary = z.infer<typeof approvalSpeedSummarySchema>;
export type ApproverSpeedItem = z.infer<typeof approverSpeedItemSchema>;
export type ByRequestTypeSpeedItem = z.infer<typeof byRequestTypeSpeedItemSchema>;

export const MOCK_APPROVAL_SPEED_REPORT: ApprovalSpeedReport = {
  summary: {
    total_decisions: 278,
    total_approved: 263,
    total_rejected: 15,
    avg_turnaround_hours: 36.0,
    median_turnaround_hours: 3.1,
    total_pending: 14,
    total_escalated: 210,
  },
  approvers: [
    {
      approver_id: '767eae8e-e7be-458e-a6ca-879414e46b08',
      name: 'محمد عبدالباسط ( ابو عمار )',
      code: '+201226905602',
      total_decisions: 1380,
      approved_count: 1320,
      rejected_count: 60,
      avg_hours: 53.4,
      median_hours: 4.5,
      escalated_count: 13,
      pending_count: 10,
      oldest_pending_hours: 72.3,
    },
    {
      approver_id: '6ad20b22-51d7-4ddc-a127-62a54a45c8e6',
      name: 'مصطفي محمد فايد',
      code: '+201009052140',
      total_decisions: 46,
      approved_count: 41,
      rejected_count: 5,
      avg_hours: 19.8,
      median_hours: 6.4,
      escalated_count: 63,
      pending_count: 0,
      oldest_pending_hours: 0,
    },
    {
      approver_id: '954e2d35-6025-4f3b-8189-69ca6aa3cd97',
      name: 'احمد محمد عبدالفتاح محجوب',
      code: '+201033447012',
      total_decisions: 39,
      approved_count: 39,
      rejected_count: 0,
      avg_hours: 9.9,
      median_hours: 0.2,
      escalated_count: 15,
      pending_count: 0,
      oldest_pending_hours: 0,
    },
  ],
  byRequestType: [
    { request_type: 'mission', decisions_count: 177, avg_hours: 36.7, median_hours: 2.9 },
    { request_type: 'leave', decisions_count: 54, avg_hours: 29.1, median_hours: 4.1 },
    { request_type: 'convoy', decisions_count: 26, avg_hours: 33.6, median_hours: 3.3 },
    { request_type: 'late_permit', decisions_count: 14, avg_hours: 45.5, median_hours: 19.5 },
    { request_type: 'fundraising', decisions_count: 6, avg_hours: 68.5, median_hours: 38.2 },
    { request_type: 'early_permit', decisions_count: 1, avg_hours: 0.7, median_hours: 0.7 },
  ],
  period: { from: null, to: null },
};

export function useApprovalSpeedReport(fromDate?: string, toDate?: string) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['management', 'approval_speed_report', fromDate ?? null, toDate ?? null],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<ApprovalSpeedReport> => {
      if (auth.isMock) {
        return MOCK_APPROVAL_SPEED_REPORT;
      }
      return rpc<ApprovalSpeedReport>(
        'get_approval_speed_report',
        {
          p_from: fromDate || null,
          p_to: toDate || null,
        },
        approvalSpeedReportSchema,
      );
    },
  });
}
