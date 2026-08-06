import { attendanceDashboardSchema, attendanceRosterCategorySchema, attendanceRosterItemSchema, type AttendanceDashboard, type AttendanceRosterCategory, type AttendanceRosterItem } from '@ahla/shared-contracts';
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

/** يجلب قائمة الموظفين لفئة محددة من لوحة الحضور (المجدولون / الحاضرون / المتأخرون / الغائبون / غير المبرر / البصمات غير المكتملة / المراجعة / طلبات الموقع). */
export function useAttendanceRoster(category: AttendanceRosterCategory | null, enabled = true) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['attendance-roster', auth.isMock, category, cairoTodayIso()],
    enabled: enabled && category !== null && auth.status === 'authenticated',
    staleTime: 30_000, // 30 ثانية تكفي لقائمة اليوم؛ التحديث اليدوي متاح عبر زر التحديث
    queryFn: async (): Promise<AttendanceRosterItem[]> => {
      const cat = attendanceRosterCategorySchema.parse(category);
      if (auth.isMock) {
        return (await loadDomainMocks()).mockAttendanceRoster[cat];
      }
      const data = await rpc('get_attendance_day_roster', { p_date: cairoTodayIso(), p_category: cat });
      return attendanceRosterItemSchema.array().parse(data);
    },
  });
}
