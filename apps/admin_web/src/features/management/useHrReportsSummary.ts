import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

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
      if (auth.isMock) return (await loadDomainMocks()).mockHrReportsSummary;
      return await rpc<HrReportsSummary>('get_hr_reports_summary', {});
    },
  });
}
