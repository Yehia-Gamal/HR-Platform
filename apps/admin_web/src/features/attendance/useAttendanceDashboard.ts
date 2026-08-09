import {
  attendanceDashboardSchema,
  attendanceRosterCategorySchema,
  attendanceRosterPageSchema,
  type AttendanceDashboard,
  type AttendanceRosterCategory,
  type AttendanceRosterPage,
  type AttendanceRosterSort,
} from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { cairoTodayIso } from '../../core/cairoTime';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

export interface AttendanceDashboardFilters {
  dateIso?: string;
  departmentId?: string | null;
  branchId?: string | null;
  managerId?: string | null;
}

export function useAttendanceDashboard(filters?: AttendanceDashboardFilters) {
  const auth = useAuth();
  const dateIso = filters?.dateIso ?? cairoTodayIso();
  const departmentId = filters?.departmentId || null;
  const branchId = filters?.branchId || null;
  const managerId = filters?.managerId || null;
  return useQuery({
    queryKey: ['attendance-dashboard', auth.isMock, dateIso, departmentId, branchId, managerId],
    enabled: auth.status === 'authenticated',
    refetchInterval: auth.isMock ? false : 60_000,
    queryFn: async (): Promise<AttendanceDashboard> => {
      if (auth.isMock) return (await loadDomainMocks()).mockAttendanceDashboard;
      const data = await rpc('get_attendance_dashboard', {
        p_date: dateIso,
        p_department_id: departmentId,
        p_branch_id: branchId,
        p_manager_id: managerId,
      });
      return attendanceDashboardSchema.parse(data);
    },
  });
}

export interface AttendanceRosterFilters {
  category: AttendanceRosterCategory;
  dateIso: string;
  search?: string;
  departmentId?: string | null;
  branchId?: string | null;
  managerId?: string | null;
  sort?: AttendanceRosterSort;
  direction?: 'asc' | 'desc';
  limit?: number;
  offset?: number;
}

/**
 * يجلب صفحة (ترقيم) من get_attendance_day_roster الموسّع (0294).
 * total محسوب على الخادم بعد الفلاتر وقبل limit/offset — فيطابق الرقم
 * المعروض في بطاقة لوحة الحضور عدد نتائج القائمة دائماً.
 */
export function useAttendanceRosterPage(filters: AttendanceRosterFilters) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['attendance-roster-page', auth.isMock, filters],
    enabled: auth.status === 'authenticated',
    staleTime: 30_000,
    queryFn: async (): Promise<AttendanceRosterPage> => {
      const cat = attendanceRosterCategorySchema.parse(filters.category);
      const limit = filters.limit ?? 25;
      const offset = filters.offset ?? 0;
      if (auth.isMock) {
        const list = (await loadDomainMocks()).mockAttendanceRoster[cat] ?? [];
        const items = list.slice(offset, offset + limit);
        return { items, total: list.length, limit, offset };
      }
      const data = await rpc('get_attendance_day_roster', {
        p_date: filters.dateIso,
        p_category: cat,
        p_search: filters.search?.trim() || null,
        p_department_id: filters.departmentId || null,
        p_branch_id: filters.branchId || null,
        p_manager_id: filters.managerId || null,
        p_sort: filters.sort ?? 'name',
        p_direction: filters.direction ?? 'asc',
        p_limit: limit,
        p_offset: offset,
      });
      return attendanceRosterPageSchema.parse(data);
    },
  });
}
