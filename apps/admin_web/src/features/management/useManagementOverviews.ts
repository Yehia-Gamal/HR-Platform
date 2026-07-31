import {
  dashboardOverviewSchema,
  recruitmentOverviewSchema,
  systemOverviewSchema,
  type DashboardOverview,
  type RecruitmentOverview,
  type SystemOverview,
} from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useDashboardOverview(workspace: 'hr' | 'main_admin') {
  const auth = useAuth();
  return useQuery({
    queryKey: ['dashboard-overview', workspace, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<DashboardOverview> =>
      auth.isMock
        ? dashboardOverviewSchema.parse((await loadDomainMocks()).mockDashboardOverview)
        : dashboardOverviewSchema.parse(await rpc('get_dashboard_overview', { p_workspace: workspace })),
  });
}

export function useRecruitmentOverview() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['recruitment-overview', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<RecruitmentOverview> =>
      auth.isMock
        ? recruitmentOverviewSchema.parse((await loadDomainMocks()).mockRecruitmentOverview)
        : recruitmentOverviewSchema.parse(await rpc('get_recruitment_overview')),
  });
}
export function useSystemOverview() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['system-overview', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<SystemOverview> =>
      auth.isMock ? systemOverviewSchema.parse((await loadDomainMocks()).mockSystemOverview) : systemOverviewSchema.parse(await rpc('get_system_overview')),
  });
}
