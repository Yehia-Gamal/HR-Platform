import { attendanceDashboardSchema, type AttendanceDashboard } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { cairoTodayIso } from '../../core/cairoTime';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export function useAttendanceDashboard() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['attendance-dashboard', auth.isMock],
    enabled: auth.status === 'authenticated',
    refetchInterval: auth.isMock ? false : 60_000,
    queryFn: async (): Promise<AttendanceDashboard> => {
      if (auth.isMock) return (await loadDomainMocks()).mockAttendanceDashboard;
      const data = await rpc('get_attendance_dashboard', { p_date: cairoTodayIso() });
      return attendanceDashboardSchema.parse(data);
    },
  });
}
