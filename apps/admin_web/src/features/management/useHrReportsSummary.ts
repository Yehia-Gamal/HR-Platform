import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

interface ReportSection {
  [key: string]: number | string | undefined;
}

export interface HrReportsSummary {
  attendance: ReportSection;
  leaves: ReportSection;
  assignments: ReportSection;
  kpi: ReportSection;
  disputes: ReportSection;
  location: ReportSection;
  generatedAt: string;
}

export function useHrReportsSummary() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['hr-reports-summary', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<HrReportsSummary> => {
      if (auth.isMock) {
        return {
          attendance: { totalEvents: 1200, checkIns: 35, checkOuts: 28, pendingReview: 5, thisMonth: 820 },
          leaves: { totalRequests: 95, approved: 72, pending: 12, rejected: 11, activeNow: 3 },
          assignments: { total: 45, active: 8, completed: 30, pending: 7 },
          kpi: { activeCycles: 1, totalEvaluations: 42, pendingEvaluations: 15, completedEvaluations: 27 },
          disputes: { total: 6, open: 2, resolved: 4, escalated: 1 },
          location: { totalRequests: 18, pending: 3, responded: 15 },
          generatedAt: new Date().toISOString(),
        };
      }
      return await rpc<HrReportsSummary>('get_hr_reports_summary', {});
    },
  });
}
