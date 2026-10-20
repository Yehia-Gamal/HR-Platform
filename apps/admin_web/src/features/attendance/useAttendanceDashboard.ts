import {
  attendanceDashboardSchema,
  attendanceRosterCategorySchema,
  attendanceRosterItemSchema,
  attendanceRosterPageSchema,
  executiveDailyReportSchema,
  type AttendanceDashboard,
  type AttendanceRosterCategory,
  type AttendanceRosterItem,
  type AttendanceRosterPage,
  type AttendanceRosterSort,
  type ExecutiveDailyReport,
  type ExecutiveDailyReportDetail,
} from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { cairoTodayIso } from '../../core/cairoTime';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';
import { ASSOCIATION_LOGO_BLUE_DATA_URL } from './brandAssets';

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
  enabled?: boolean;
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
    enabled: auth.status === 'authenticated' && (filters.enabled ?? true),
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
  scheduled: 'المجدولون',
  present: 'حاضرون',
  late: 'متأخرون',
  absent: 'إجمالي الغياب',
  unexcused_absent: 'غياب بدون إذن',
  incomplete: 'بصمات غير مكتملة',
  pending_review: 'تحتاج مراجعة',
  location_requests: 'طلبات الموقع',
  location_responded: 'استجابات الموقع',
  on_leave: 'في إجازة',
  on_mission: 'في مأمورية',
  missing_checkout: 'بصمة بلا انصراف',
};

const STATUS_LABELS_PDF: Record<string, string> = {
  present: 'حاضر',
  late: 'متأخر',
  absent: 'غائب',
  on_leave: 'إجازة',
  holiday: 'عطلة',
  weekend: 'عطلة أسبوعية',
  partial: 'جزئي',
  pending: 'قيد الانتظار',
  on_mission: 'مأمورية',
  missing_checkout: 'بصمة بلا انصراف',
};

function _fmt(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('ar-EG-u-nu-latn', { timeStyle: 'short' }).format(new Date(iso));
}

function _buildPrintHtml(items: AttendanceRosterItem[], category: string, dateIso: string): string {
  const categoryLabel = CATEGORY_LABELS[category] ?? category;
  const dateObj = new Date(`${dateIso}T00:00:00`);
  const dateLabel = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'full' }).format(Number.isNaN(dateObj.getTime()) ? new Date() : dateObj);
  const title = `كشف الحضور الرسمي — ${categoryLabel} — ${dateLabel}`;

  const isMissionItem = (i: AttendanceRosterItem): boolean =>
    i.status === 'on_mission' ||
    Boolean(i.hasMission) ||
    (Boolean(i.hasPendingRequest) && i.pendingRequestType === 'mission');

  const isLeaveItem = (i: AttendanceRosterItem): boolean =>
    (i.status === 'on_leave' ||
      Boolean(i.hasApprovedLeave) ||
      (Boolean(i.hasPendingRequest) && i.pendingRequestType !== 'mission')) &&
    !isMissionItem(i);

  const presentCount = items.filter((i) => i.status === 'present' || i.status === 'late').length;
  const lateCount = items.filter((i) => i.status === 'late' || (i.lateMinutes != null && i.lateMinutes > 0)).length;
  const absentCount = items.filter((i) => (i.status === 'absent' || i.status === 'unexcused_absent') && !i.hasPendingRequest).length;
  const missionCount = items.filter(isMissionItem).length;
  const leaveCount = items.filter(isLeaveItem).length;

  let displayItems = items;
  if (category === 'present') {
    displayItems = [...items].sort((a, b) => {
      const getPriority = (item: AttendanceRosterItem): number => {
        if ((item.lateMinutes ?? 0) > 0) return 3;
        if (isMissionItem(item)) return 2;
        return 1;
      };
      const pA = getPriority(a);
      const pB = getPriority(b);
      if (pA !== pB) return pA - pB;
      if (pA === 3 && pB === 3) {
        const diff = (b.lateMinutes ?? 0) - (a.lateMinutes ?? 0);
        if (diff !== 0) return diff;
      }
      return (a.employeeName ?? '').localeCompare(b.employeeName ?? '', 'ar');
    });
  }

  let lastPriority = 0;
  const rows = displayItems
    .map((item, i) => {
      let dividerHtml = '';
      if (category === 'present') {
        const priority = (item.lateMinutes ?? 0) > 0 ? 3 : isMissionItem(item) ? 2 : 1;
        if (priority !== lastPriority) {
          if (priority === 2) {
            dividerHtml = `
    <tr class="section-divider-row">
      <td colspan="10" style="background:#f0f9ff;color:#0284c7;font-weight:800;padding:6px 10px;text-align:start;border-top:2px solid #38bdf8;border-bottom:1px solid #bae6fd">
        ✈️ موظفون سجلوا حضوراً ثم خرجوا في مأموريات عمل ميدانية (زيارات ومهمات رسمية)
      </td>
    </tr>`;
          } else if (priority === 3) {
            dividerHtml = `
    <tr class="section-divider-row">
      <td colspan="10" style="background:#fffbeb;color:#b45309;font-weight:800;padding:6px 10px;text-align:start;border-top:2px solid #f59e0b;border-bottom:1px solid #fde68a">
        ⚠️ المتأخرون عن موعد الوردية الرسمي (المسجلون بعد الموعد)
      </td>
    </tr>`;
          }
          lastPriority = priority;
        }
      }

      let statusBadgeClass = 'status-badge-neutral';
      let statusText = STATUS_LABELS_PDF[item.status ?? ''] ?? item.status ?? '—';
      if (item.status === 'present') {
        statusBadgeClass = 'status-badge-present';
        statusText = 'حاضر';
      } else if (item.status === 'late') {
        statusBadgeClass = 'status-badge-late';
        statusText = 'متأخر';
      } else if (item.status === 'missing_checkout') {
        statusBadgeClass = 'status-badge-late';
        statusText = 'بصمة بلا انصراف';
      } else if (item.status === 'absent' || item.status === 'unexcused_absent') {
        if (item.hasPendingRequest) {
          if (item.pendingRequestType === 'mission') {
            statusBadgeClass = 'status-badge-mission';
            statusText = 'مأمورية (قيد المراجعة)';
          } else {
            statusBadgeClass = 'status-badge-leave';
            statusText = 'إجازة (قيد المراجعة)';
          }
        } else {
          statusBadgeClass = 'status-badge-absent';
          statusText = (item.status === 'unexcused_absent' || (!item.hasPendingRequest && !item.hasApprovedLeave && !item.hasMission && item.status === 'absent')) ? 'غياب بدون إذن' : 'غائب';
        }
      } else if (item.status === 'on_leave' || item.hasApprovedLeave) {
        statusBadgeClass = 'status-badge-leave';
        statusText = item.leaveName ?? 'إجازة';
      } else if (item.status === 'on_mission' || item.hasMission) {
        statusBadgeClass = 'status-badge-mission';
        statusText = 'مأمورية';
      }

      let checkOutDisplay = '—';
      if (item.lastCheckOut) {
        checkOutDisplay = _fmt(item.lastCheckOut);
      } else if (item.firstCheckIn) {
        const isMission = item.status === 'on_mission' || Boolean(item.hasMission) || (Boolean(item.hasPendingRequest) && item.pendingRequestType === 'mission');
        if (isMission) {
          const dest = item.leaveTitle ?? item.pendingRequestTitle;
          checkOutDisplay = `<span style="color:#0284c7;font-weight:700">✈️ خرج لمأمورية${dest ? ` (${dest})` : ''}</span>`;
        } else {
          checkOutDisplay = '<span style="color:#059669;font-weight:700">متواجد حالياً في المجمع</span>';
        }
      }

      let excuseDisplay = '—';
      if (item.hasPendingRequest && !item.hasApprovedLeave) {
        const isMission = item.pendingRequestType === 'mission';
        const reqTitle = item.pendingRequestTitle ?? item.leaveTitle ?? (isMission ? 'مأمورية رسمية' : item.leaveName ?? 'إجازة');
        const reqNum = item.pendingRequestNumber ? ` (#${item.pendingRequestNumber})` : '';
        const reasonPart = item.leaveReason ? ` - ${item.leaveReason}` : '';
        excuseDisplay = `⏳ ${isMission ? 'طلب مأمورية' : 'طلب معلّق'}: ${reqTitle}${reqNum}${reasonPart}`;
      } else if (item.leaveName) {
        excuseDisplay = item.leaveName;
      } else if (item.hasMission) {
        excuseDisplay = item.leaveTitle ?? 'مأمورية معتمدة';
      } else if (item.reviewReason) {
        excuseDisplay = item.reviewReason;
      }

      return `${dividerHtml}
    <tr>
      <td style="text-align:center;font-variant-numeric:tabular-nums;color:#6b7280">${i + 1}</td>
      <td style="font-weight:700;color:#111827">${item.employeeName}</td>
      <td style="text-align:center;font-variant-numeric:tabular-nums;direction:ltr;color:#4b5563;font-size:9px">${item.employeeCode ?? '—'}</td>
      <td style="text-align:center;color:#374151">${item.departmentName ?? '—'}</td>
      <td style="text-align:center;color:#4b5563;font-size:9px">${item.branchName ?? '—'}</td>
      <td style="text-align:center"><span class="status-badge ${statusBadgeClass}">${statusText}</span></td>
      <td style="text-align:center;font-variant-numeric:tabular-nums;direction:ltr;font-weight:600">${_fmt(item.firstCheckIn)}</td>
      <td style="text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${checkOutDisplay}</td>
      <td style="text-align:center;font-variant-numeric:tabular-nums">${item.lateMinutes ? `<span style="color:#b45309;font-weight:700">${item.lateMinutes} د</span>` : '—'}</td>
      <td style="text-align:center;font-size:9px;color:#4b5563">${excuseDisplay}</td>
    </tr>`;
    })
    .join('');

  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<title>${title}</title>
<style>
  @page { size: A4 landscape; margin: 8mm 6mm; }
  * { box-sizing: border-box; }
  body {
    font-family: 'Cairo', 'Segoe UI', Tahoma, Arial, sans-serif;
    font-size: 10px;
    color: #111827;
    margin: 12px;
    line-height: 1.4;
    background: #f8fafc;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }
  .page { max-width: 1120px; margin: 0 auto; background: #fff; padding: 20px 24px; border-radius: 8px; border: 1px solid #e2e8f0; }
  .header { border-bottom: 2px solid #2563eb; padding-bottom: 12px; margin-bottom: 12px; display: flex; justify-content: space-between; align-items: flex-start; }
  .org-title { font-size: 15px; font-weight: 900; color: #1e3a8a; margin: 0; }
  .org-sub { font-size: 10px; color: #475569; font-weight: 600; margin-top: 2px; }
  .doc-title-box { text-align: left; }
  .doc-main-title { font-size: 14px; font-weight: 800; color: #2563eb; margin: 0; }
  .doc-meta { font-size: 10px; color: #64748b; font-weight: 600; margin-top: 3px; }

  /* بطاقات الإحصائيات السريعة */
  .stats-bar { display: flex; gap: 8px; margin-bottom: 12px; }
  .stat-card {
    flex: 1; padding: 6px 10px; border-radius: 6px; background: #f8fafc;
    border: 1px solid #e2e8f0; display: flex; justify-content: space-between; align-items: center;
  }
  .stat-card.present { border-color: #a7f3d0; background: #ecfdf5; }
  .stat-card.late { border-color: #fde68a; background: #fffbeb; }
  .stat-card.absent { border-color: #fecaca; background: #fef2f2; }
  .stat-card.mission { border-color: #bae6fd; background: #f0f9ff; }
  .stat-card.leave { border-color: #bfdbfe; background: #eff6ff; }
  .stat-label { font-size: 9px; font-weight: 700; color: #475569; }
  .stat-value { font-size: 12px; font-weight: 900; color: #0f172a; }

  table { width: 100%; border-collapse: collapse; margin-top: 6px; font-size: 9.5px; }
  th { background: #0f172a; color: #ffffff; padding: 6px 6px; text-align: center; font-weight: 800; font-size: 9px; border: 1px solid #1e293b; }
  td { padding: 5px 6px; border: 1px solid #e2e8f0; vertical-align: middle; }
  tr:nth-child(even) td { background: #f8fafc; }
  tr { break-inside: avoid; page-break-inside: avoid; }

  .status-badge {
    display: inline-block; padding: 2px 7px; border-radius: 4px; font-size: 8.5px; font-weight: 800; white-space: nowrap;
  }
  .status-badge-present { background: #dcfce7; color: #166534; border: 1px solid #86efac; }
  .status-badge-late { background: #fef3c7; color: #92400e; border: 1px solid #fcd34d; }
  .status-badge-absent { background: #fee2e2; color: #991b1b; border: 1px solid #fca5a5; }
  .status-badge-leave { background: #dbeafe; color: #1e40af; border: 1px solid #93c5fd; }
  .status-badge-mission { background: #f3e8ff; color: #6b21a8; border: 1px solid #d8b4fe; }
  .status-badge-neutral { background: #f1f5f9; color: #475569; border: 1px solid #cbd5e1; }

  /* التوقيعات والذيل */
  .sign-section {
    margin-top: 18px; padding-top: 14px; border-top: 1px dashed #cbd5e1;
    display: flex; justify-content: space-between; align-items: flex-end;
  }
  .sign-box { text-align: center; width: 220px; }
  .sign-box .role { font-size: 10px; font-weight: 800; color: #1e293b; margin-bottom: 28px; }
  .sign-box .line { border-bottom: 1px solid #94a3b8; width: 100%; margin: 0 auto; }

  .footer { margin-top: 12px; display: flex; justify-content: space-between; font-size: 8.5px; color: #94a3b8; }

  /* شريط الإجراءات للشاشة */
  .action-bar {
    max-width: 1120px; margin: 0 auto 12px; background: #0f172a; color: #f8fafc;
    border-radius: 8px; padding: 10px 16px; display: flex; justify-content: space-between; align-items: center;
  }
  .btn-act {
    padding: 6px 14px; font-size: 11px; font-weight: 700; border-radius: 6px; cursor: pointer; border: none; font-family: inherit;
  }
  .btn-act-pdf { background: #10b981; color: white; }
  .btn-act-print { background: #2563eb; color: white; margin-inline-start: 6px; }
  .btn-act-close { background: transparent; color: #94a3b8; border: 1px solid #334155; margin-inline-start: 6px; }

  @media print {
    body { margin: 0; background: #fff; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
    .no-print, .action-bar { display: none !important; }
    .page { border: none; padding: 0; max-width: 100%; }
  }
</style>
</head>
<body>
<div class="action-bar no-print">
  <div style="font-size:12px;font-weight:800">📄 كشف «${categoryLabel}» — ${dateLabel} (${items.length} سجل)</div>
  <div>
    <button type="button" class="btn-act btn-act-pdf" onclick="saveAsPdf()">📥 حفظ PDF</button>
    <button type="button" class="btn-act btn-act-print" onclick="window.print()">🖨️ طباعة</button>
    <button type="button" class="btn-act btn-act-close" onclick="window.close()">إغلاق</button>
  </div>
</div>

<div class="page">
  <div class="header">
    <div style="display:flex;align-items:center;gap:12px;">
      <img src="${ASSOCIATION_LOGO_BLUE_DATA_URL}" alt="شعار جمعية خواطر أحلى شباب" style="height:54px;width:auto;object-fit:contain;" />
      <div>
        <div class="org-title">جمعية خواطر أحلى شباب (المشهرة برقم 7226)</div>
        <div class="org-sub">منظومة الإدارة المؤسسية — الإدارة العامة للموارد البشرية</div>
      </div>
    </div>
    <div class="doc-title-box">
      <div class="doc-main-title">كشف الحضور اليومي — ${categoryLabel}</div>
      <div class="doc-meta">${dateLabel} &nbsp;|&nbsp; إجمالي الموظفين: ${items.length}</div>
    </div>
  </div>

  <div class="stats-bar">
    <div class="stat-card">
      <span class="stat-label">إجمالي الكشف:</span>
      <span class="stat-value">${items.length}</span>
    </div>
    <div class="stat-card present">
      <span class="stat-label">حاضرون:</span>
      <span class="stat-value" style="color:#059669">${presentCount}</span>
    </div>
    <div class="stat-card late">
      <span class="stat-label">متأخرون:</span>
      <span class="stat-value" style="color:#b45309">${lateCount}</span>
    </div>
    <div class="stat-card absent">
      <span class="stat-label">غياب:</span>
      <span class="stat-value" style="color:#dc2626">${absentCount}</span>
    </div>
    <div class="stat-card mission">
      <span class="stat-label">مأموريات:</span>
      <span class="stat-value" style="color:#0284c7">${missionCount}</span>
    </div>
    <div class="stat-card leave">
      <span class="stat-label">إجازات:</span>
      <span class="stat-value" style="color:#2563eb">${leaveCount}</span>
    </div>
  </div>

  <table>
    <thead>
      <tr>
        <th style="width:30px">#</th>
        <th style="width:160px">اسم الموظف</th>
        <th style="width:80px">الكود</th>
        <th style="width:110px">الإدارة</th>
        <th style="width:100px">الفرع</th>
        <th style="width:100px;white-space:nowrap;">الحالة</th>
        <th style="width:65px">الحضور</th>
        <th style="width:75px">الانصراف</th>
        <th style="width:55px">التأخير</th>
        <th style="width:100px">العذر والبيان</th>
      </tr>
    </thead>
    <tbody>${rows}</tbody>
  </table>

  <div class="sign-section">
    <div class="sign-box">
      <div class="role">مسؤول الموارد البشرية</div>
      <div class="line"></div>
    </div>
    <div class="sign-box">
      <div class="role">المراجع المالي والإداري</div>
      <div class="line"></div>
    </div>
    <div class="sign-box">
      <div class="role">اعتماد المدير التنفيذي</div>
      <div class="line"></div>
    </div>
  </div>

  <div class="footer">
    <span>منظومة أحلى شباب الإدارية — كشف حضور رسمي مُصدّر إلكترونياً</span>
    <span>تاريخ التوليد: ${new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'full', timeStyle: 'short' }).format(new Date())}</span>
  </div>
</div>

<script>
  function saveAsPdf() {
    window.focus();
    try { window.print(); } catch(e) { console.error(e); }
  }
</script>
</body>
</html>`;
}

export async function exportAttendancePdf(filters: Omit<AttendanceRosterFilters, 'limit' | 'offset'>): Promise<void> {
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
  // تصدير PDF حقيقي مباشرة دون فتح نوافذ HTML.
  const { downloadHtmlAsPdf } = await import('../../core/pdfExport');
  await downloadHtmlAsPdf(html, `قائمة الحضور ${filters.dateIso}`, `قائمة_الحضور_${cat}_${filters.dateIso}.pdf`);
}

/**
 * يجلب التقرير التنفيذي اليومي الشامل (get_v10_executive_daily_report).
 * متاح للتنفيذيين والسكرتارية التنفيذية وصلاحية reports.executive.read.
 */
export function useExecutiveDailyReport(dateIso?: string) {
  const auth = useAuth();
  const targetDate = dateIso ?? cairoTodayIso();
  return useQuery({
    queryKey: ['executive-daily-report', auth.isMock, targetDate],
    enabled: auth.status === 'authenticated',
    staleTime: 60_000,
    queryFn: async (): Promise<ExecutiveDailyReport> => {
      if (auth.isMock) {
        const mocks = await loadDomainMocks();
        return executiveDailyReportSchema.parse({
          ...mocks.mockExecutiveDailyReport,
          date: targetDate,
        });
      }
      const data = await rpc('get_v10_executive_daily_report', { p_date: targetDate });
      return executiveDailyReportSchema.parse(data);
    },
  });
}

/**
 * يجلب التقرير التنفيذي التفصيلي مع بيانات الموظفين والمأموريات والقوافل والإجازات.
 * يتطلب بيانات تفصيلية من RPC مخصص أو تجميع من عدة مصادر.
 */
export function useExecutiveDailyReportDetail(dateIso?: string) {
  const auth = useAuth();
  const targetDate = dateIso ?? cairoTodayIso();
  return useQuery({
    queryKey: ['executive-daily-report-detail', auth.isMock, targetDate],
    enabled: auth.status === 'authenticated',
    staleTime: 60_000,
    queryFn: async (): Promise<ExecutiveDailyReportDetail> => {
      if (auth.isMock) {
        const mocks = await loadDomainMocks();
        const summary = executiveDailyReportSchema.parse({
          ...mocks.mockExecutiveDailyReport,
          date: targetDate,
        });
        const mockEmployees = (mocks.mockAttendanceRoster.scheduled ?? []).map((r) => ({
          employeeId: r.employeeId,
          employeeName: r.employeeName,
          employeeCode: r.employeeCode ?? null,
          departmentName: r.departmentName ?? null,
          jobTitle: 'أخصائي عمل ميداني',
          managerName: 'أحمد محمود',
          status: r.status ?? null,
          lateMinutes: r.lateMinutes ?? null,
          firstCheckIn: r.firstCheckIn ?? null,
          lastCheckOut: r.lastCheckOut ?? null,
          hasApprovedLeave: Boolean(r.hasApprovedLeave),
          hasMission: Boolean(r.hasMission),
          locationRequestStatus: r.locationRequestStatus ?? null,
        }));
        return {
          dateIso: targetDate,
          summary,
          employees: mockEmployees,
          missions: [],
          convoys: [],
          leaves: [],
          locationRequests: [],
          disputes: [],
          reports: [],
        };
      }
      const [data, employees] = await Promise.all([rpc('get_v10_executive_daily_report', { p_date: targetDate }), fetchExecutiveEmployees(targetDate)]);
      const summary = executiveDailyReportSchema.parse(data);
      return {
        dateIso: targetDate,
        summary,
        employees,
        missions: [],
        convoys: [],
        leaves: [],
        locationRequests: [],
        disputes: [],
        reports: [],
      };
    },
  });
}

/** صف لوحة المتابعة (get_executive_attendance_overview) — الحقول التي يحتاجها التقرير. */
interface ExecutiveOverviewRow {
  id: string;
  name: string;
  employeeCode: string | null;
  department: string | null;
  jobTitle: string | null;
  managerName: string | null;
  status: string | null;
  lateMinutes: number | null;
  firstCheckIn: string | null;
  lastCheckOut: string | null;
  onLeave?: boolean;
  assignmentType?: string | null;
  activeRequestStatus?: string | null;
}

/**
 * قائمة موظفي التقرير التنفيذي من لوحة المتابعة — نفس مصدر الملخص (0597).
 * كانت القائمة تُرسل فارغة فيُطبع التقرير بحضور 0 ونسبة 0% وجداول فارغة.
 * من لا يملك صلاحية لوحة المتابعة يحصل على الملخص وحده.
 */
async function fetchExecutiveEmployees(dateIso: string): Promise<ExecutiveDailyReportDetail['employees']> {
  try {
    const data = await rpc<{ employees?: ExecutiveOverviewRow[] } | null>('get_executive_attendance_overview', { p_date: dateIso });
    return (data?.employees ?? []).map((r) => ({
      employeeId: r.id,
      employeeName: r.name,
      employeeCode: r.employeeCode ?? null,
      departmentName: r.department ?? null,
      jobTitle: r.jobTitle ?? null,
      managerName: r.managerName ?? null,
      status: r.status ?? null,
      lateMinutes: r.lateMinutes ?? null,
      firstCheckIn: r.firstCheckIn ?? null,
      lastCheckOut: r.lastCheckOut ?? null,
      hasApprovedLeave: Boolean(r.onLeave),
      hasMission: Boolean(r.assignmentType),
      locationRequestStatus: r.activeRequestStatus ?? null,
    }));
  } catch {
    return [];
  }
}

export async function exportExecutiveDailyReportPdf(dateIso?: string): Promise<void> {
  const targetDate = dateIso ?? cairoTodayIso();
  const { exportExecutiveDailyReport } = await import('./exportExecutiveDailyReport');
  const [data, employees] = await Promise.all([rpc('get_v10_executive_daily_report', { p_date: targetDate }), fetchExecutiveEmployees(targetDate)]);
  const summary = executiveDailyReportSchema.parse(data);
  const detail: ExecutiveDailyReportDetail = {
    dateIso: targetDate,
    summary,
    employees,
    missions: [],
    convoys: [],
    leaves: [],
    locationRequests: [],
    disputes: [],
    reports: [],
  };
  exportExecutiveDailyReport(detail);
}
