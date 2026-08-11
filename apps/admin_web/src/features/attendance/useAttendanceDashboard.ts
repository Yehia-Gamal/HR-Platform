import {
  attendanceDashboardSchema,
  attendanceRosterCategorySchema,
  attendanceRosterItemSchema,
  attendanceRosterPageSchema,
  type AttendanceDashboard,
  type AttendanceRosterCategory,
  type AttendanceRosterItem,
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

const CATEGORY_LABELS: Record<string, string> = {
  scheduled: 'المجدولون', present: 'حاضرون', late: 'متأخرون', absent: 'غائبون',
  unexcused_absent: 'غياب بدون إذن', incomplete: 'بصمات غير مكتملة',
  pending_review: 'تحتاج مراجعة', location_requests: 'طلبات الموقع',
  location_responded: 'استجابات الموقع', on_leave: 'في إجازة',
  on_mission: 'في مأمورية', missing_checkout: 'بصمة بلا انصراف',
};

const STATUS_LABELS_PDF: Record<string, string> = {
  present: 'حاضر', late: 'متأخر', absent: 'غائب', on_leave: 'إجازة',
  holiday: 'عطلة', weekend: 'عطلة أسبوعية', partial: 'جزئي',
  pending: 'قيد الانتظار', on_mission: 'مأمورية', missing_checkout: 'بصمة بلا انصراف',
};

function _fmt(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('ar-EG', { timeStyle: 'short' }).format(new Date(iso));
}

function _buildPrintHtml(
  items: AttendanceRosterItem[],
  category: string,
  dateIso: string,
): string {
  const categoryLabel = CATEGORY_LABELS[category] ?? category;
  const dateLabel = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date(dateIso));
  const rows = items.map((item, i) => `
    <tr>
      <td>${i + 1}</td>
      <td>${item.employeeName}</td>
      <td>${item.employeeCode ?? '—'}</td>
      <td>${item.departmentName ?? '—'}</td>
      <td>${STATUS_LABELS_PDF[item.status ?? ''] ?? item.status ?? '—'}</td>
      <td>${_fmt(item.firstCheckIn)}</td>
      <td>${_fmt(item.lastCheckOut)}</td>
      <td>${item.lateMinutes ? `${item.lateMinutes} د` : '—'}</td>
    </tr>`).join('');
  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<title>قائمة الحضور — ${categoryLabel} — ${dateLabel}</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; font-size: 12px; color: #1a1a1a; margin: 20px; }
  h1 { font-size: 16px; margin: 0 0 4px; }
  .meta { color: #666; font-size: 11px; margin-bottom: 16px; }
  table { width: 100%; border-collapse: collapse; }
  th { background: #1a56db; color: #fff; padding: 6px 8px; text-align: right; font-weight: 700; }
  td { padding: 5px 8px; border-bottom: 1px solid #e5e7eb; }
  tr:nth-child(even) td { background: #f9fafb; }
  .footer { margin-top: 12px; font-size: 10px; color: #aaa; text-align: left; }
  @media print { body { margin: 10px; } button { display: none; } }
</style>
</head>
<body>
<h1>قائمة الحضور — ${categoryLabel}</h1>
<div class="meta">${dateLabel} &nbsp;·&nbsp; إجمالي: ${items.length} موظف</div>
<table>
<thead>
<tr>
  <th>#</th><th>اسم الموظف</th><th>كود</th><th>القسم</th>
  <th>الحالة</th><th>أول بصمة</th><th>آخر بصمة</th><th>التأخير</th>
</tr>
</thead>
<tbody>${rows}</tbody>
</table>
<div class="footer">طُبع في ${new Date().toLocaleString('ar-EG')} — نظام أحلى شباب الإداري</div>
<script>window.onload = () => window.print();</script>
</body>
</html>`;
}

export async function exportAttendancePdf(
  filters: Omit<AttendanceRosterFilters, 'limit' | 'offset'>,
): Promise<void> {
  const cat = attendanceRosterCategorySchema.parse(filters.category);
  const data = await rpc('get_attendance_day_roster', {
    p_date: filters.dateIso,
    p_category: cat,
    p_search: filters.search?.trim() || null,
    p_department_id: filters.departmentId || null,
    p_branch_id: filters.branchId || null,
    p_manager_id: filters.managerId || null,
    p_sort: filters.sort ?? 'name',
    p_direction: filters.direction ?? 'asc',
    p_limit: 1000,
    p_offset: 0,
  });
  const parsed = attendanceRosterPageSchema.parse(data);
  const items = parsed.items.map((i) => attendanceRosterItemSchema.parse(i));
  const html = _buildPrintHtml(items, cat, filters.dateIso);
  const win = window.open('', '_blank', 'width=900,height=700');
  if (win) {
    win.document.write(html);
    win.document.close();
  }
}
