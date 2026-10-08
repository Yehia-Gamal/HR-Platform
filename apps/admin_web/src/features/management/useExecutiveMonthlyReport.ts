import { z } from 'zod';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export const executiveMonthlyReportPeriodSchema = z.object({
  year: z.number(),
  month: z.number(),
  startDate: z.string(),
  endDate: z.string(),
  effectiveEndDate: z.string(),
  isFinal: z.boolean(),
});

export const executiveMonthlyReportAttendanceSchema = z.object({
  active_employees_count: z.number(),
  total_calendar_days: z.number(),
  required_days: z.number(),
  attended_days: z.number(),
  absent_days: z.number(),
  late_days: z.number(),
  leave_days: z.number(),
  offsite_days: z.number(),
  total_late_minutes: z.number(),
  attendance_rate: z.number(),
});

export const executiveMonthlyReportDepartmentSchema = z.object({
  department_name: z.string(),
  employees_count: z.number(),
  required_days: z.number(),
  attended_days: z.number(),
  absent_days: z.number(),
  late_days: z.number(),
  total_late_minutes: z.number(),
  attendance_rate: z.number(),
});

export const executiveMonthlyReportRequestsSchema = z.object({
  total_requests: z.number(),
  approved_count: z.number(),
  rejected_count: z.number(),
  pending_count: z.number(),
  cancelled_count: z.number(),
  leave_requests: z.number(),
  mission_requests: z.number(),
  convoy_requests: z.number(),
  permit_requests: z.number(),
  fundraising_requests: z.number(),
});

export const executiveMonthlyReportMissionsSchema = z.object({
  total_executions: z.number(),
  completed_count: z.number(),
  auto_closed_count: z.number(),
  reported_count: z.number(),
});

export const executiveMonthlyReportPenaltiesSchema = z.object({
  total_penalties: z.number(),
  paid_count: z.number(),
  unpaid_count: z.number(),
  total_amount: z.number(),
  paid_amount: z.number(),
});

export const executiveMonthlyReportSlaSchema = z.object({
  total_decisions: z.number(),
  avg_turnaround_hours: z.number(),
  median_turnaround_hours: z.number(),
  escalated_count: z.number(),
});

export const executiveMonthlyReportSchema = z.object({
  period: executiveMonthlyReportPeriodSchema,
  attendance: executiveMonthlyReportAttendanceSchema,
  departments: z.array(executiveMonthlyReportDepartmentSchema),
  requests: executiveMonthlyReportRequestsSchema,
  missions: executiveMonthlyReportMissionsSchema,
  penalties: executiveMonthlyReportPenaltiesSchema,
  sla: executiveMonthlyReportSlaSchema,
  generatedAt: z.string().optional(),
});

export type ExecutiveMonthlyReport = z.infer<typeof executiveMonthlyReportSchema>;
export type ExecutiveMonthlyReportPeriod = z.infer<typeof executiveMonthlyReportPeriodSchema>;
export type ExecutiveMonthlyReportAttendance = z.infer<typeof executiveMonthlyReportAttendanceSchema>;
export type ExecutiveMonthlyReportDepartment = z.infer<typeof executiveMonthlyReportDepartmentSchema>;
export type ExecutiveMonthlyReportRequests = z.infer<typeof executiveMonthlyReportRequestsSchema>;
export type ExecutiveMonthlyReportMissions = z.infer<typeof executiveMonthlyReportMissionsSchema>;
export type ExecutiveMonthlyReportPenalties = z.infer<typeof executiveMonthlyReportPenaltiesSchema>;
export type ExecutiveMonthlyReportSla = z.infer<typeof executiveMonthlyReportSlaSchema>;

export const MOCK_EXECUTIVE_MONTHLY_REPORT: ExecutiveMonthlyReport = {
  period: {
    year: 2026,
    month: 10,
    startDate: '2026-10-01',
    endDate: '2026-10-31',
    effectiveEndDate: '2026-10-08',
    isFinal: false,
  },
  attendance: {
    active_employees_count: 52,
    total_calendar_days: 416,
    required_days: 364,
    attended_days: 342,
    absent_days: 12,
    late_days: 28,
    leave_days: 10,
    offsite_days: 14,
    total_late_minutes: 620,
    attendance_rate: 94.0,
  },
  departments: [
    {
      department_name: 'الإدارة العامة والموارد البشرية',
      employees_count: 8,
      required_days: 56,
      attended_days: 54,
      absent_days: 1,
      late_days: 3,
      total_late_minutes: 45,
      attendance_rate: 96.4,
    },
    {
      department_name: 'إدارة العمليات الميدانية والقوافل',
      employees_count: 18,
      required_days: 126,
      attended_days: 119,
      absent_days: 4,
      late_days: 12,
      total_late_minutes: 280,
      attendance_rate: 94.4,
    },
    {
      department_name: 'إدارة العيادات والمراكز الطبية',
      employees_count: 14,
      required_days: 98,
      attended_days: 92,
      absent_days: 3,
      late_days: 8,
      total_late_minutes: 165,
      attendance_rate: 93.9,
    },
    {
      department_name: 'إدارة تنمية الموارد والتمويل',
      employees_count: 12,
      required_days: 84,
      attended_days: 77,
      absent_days: 4,
      late_days: 5,
      total_late_minutes: 130,
      attendance_rate: 91.7,
    },
  ],
  requests: {
    total_requests: 114,
    approved_count: 98,
    rejected_count: 7,
    pending_count: 6,
    cancelled_count: 3,
    leave_requests: 38,
    mission_requests: 29,
    convoy_requests: 12,
    permit_requests: 26,
    fundraising_requests: 9,
  },
  missions: {
    total_executions: 41,
    completed_count: 38,
    auto_closed_count: 3,
    reported_count: 39,
  },
  penalties: {
    total_penalties: 12,
    paid_count: 9,
    unpaid_count: 3,
    total_amount: 1850,
    paid_amount: 1450,
  },
  sla: {
    total_decisions: 105,
    avg_turnaround_hours: 14.8,
    median_turnaround_hours: 2.8,
    escalated_count: 5,
  },
  generatedAt: new Date().toISOString(),
};

export function useExecutiveMonthlyReport(year: number, month: number) {
  const { isMock } = useAuth();
  const qc = useQueryClient();

  const query = useQuery<ExecutiveMonthlyReport>({
    queryKey: ['executive-monthly-report', year, month, isMock],
    queryFn: async () => {
      if (isMock) {
        return {
          ...MOCK_EXECUTIVE_MONTHLY_REPORT,
          period: {
            ...MOCK_EXECUTIVE_MONTHLY_REPORT.period,
            year,
            month,
          },
        };
      }
      const raw = await rpc<unknown>('get_executive_monthly_report', {
        p_year: year,
        p_month: month,
      });
      return executiveMonthlyReportSchema.parse(raw);
    },
    staleTime: 5 * 60 * 1000,
  });

  const regenerateMutation = useMutation({
    mutationFn: async () => {
      if (isMock) {
        return {
          ...MOCK_EXECUTIVE_MONTHLY_REPORT,
          period: {
            ...MOCK_EXECUTIVE_MONTHLY_REPORT.period,
            year,
            month,
          },
        };
      }
      const raw = await rpc<unknown>('generate_executive_monthly_report', {
        p_year: year,
        p_month: month,
        p_save: true,
      });
      return executiveMonthlyReportSchema.parse(raw);
    },
    onSuccess: (data) => {
      qc.setQueryData(['executive-monthly-report', year, month, isMock], data);
    },
  });

  return {
    ...query,
    regenerate: regenerateMutation.mutateAsync,
    isRegenerating: regenerateMutation.isPending,
  };
}
