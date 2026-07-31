import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

interface AttendanceTodayOverview {
  date: string;
  totalActive: number;
  expected: number;
  present: number;
  late: number;
  notCheckedIn: number;
  onLeave: number;
  onAssignment: number;
  absent: number;
  lastUpdatedAt: string;
}

export function useAttendanceTodayOverview() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['attendance-today-overview', auth.isMock],
    enabled: auth.status === 'authenticated',
    refetchInterval: 60_000,
    retry: 1,
    queryFn: async (): Promise<AttendanceTodayOverview> => {
      if (auth.isMock) {
        return {
          date: new Date().toISOString().slice(0, 10),
          totalActive: 42, expected: 38, present: 30, late: 4,
          notCheckedIn: 4, onLeave: 3, onAssignment: 1, absent: 4,
          lastUpdatedAt: new Date().toISOString(),
        };
      }
      return await rpc<AttendanceTodayOverview>('get_attendance_today_overview', {});
    },
  });
}
