import { attendanceDashboardSchema, type AttendanceDashboard } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
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
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_attendance_dashboard', { p_date: new Date().toISOString().slice(0, 10) });
      if (error) throw error;
      return attendanceDashboardSchema.parse(data);
    },
  });
}
