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
  scheduled: 'المجدولون',
  present: 'حاضرون',
  late: 'متأخرون',
  absent: 'غائبون',
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
  return new Intl.DateTimeFormat('ar-EG', { timeStyle: 'short' }).format(new Date(iso));
}

function _buildPrintHtml(items: AttendanceRosterItem[], category: string, dateIso: string): string {
  const categoryLabel = CATEGORY_LABELS[category] ?? category;
  const dateObj = new Date(`${dateIso}T00:00:00`);
  const dateLabel = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(Number.isNaN(dateObj.getTime()) ? new Date() : dateObj);
  const title = `قائمة الحضور — ${categoryLabel} — ${dateLabel}`;
  const rows = items
    .map(
      (item, i) => `
    <tr>
      <td style="text-align:center;font-variant-numeric:tabular-nums">${i + 1}</td>
      <td style="font-weight:700">${item.employeeName}</td>
      <td style="text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${item.employeeCode ?? '—'}</td>
      <td style="text-align:center">${item.departmentName ?? '—'}</td>
      <td style="text-align:center">${STATUS_LABELS_PDF[item.status ?? ''] ?? item.status ?? '—'}</td>
      <td style="text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${_fmt(item.firstCheckIn)}</td>
      <td style="text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${_fmt(item.lastCheckOut)}</td>
      <td style="text-align:center;font-variant-numeric:tabular-nums">${item.lateMinutes ? `${item.lateMinutes} د` : '—'}</td>
    </tr>`,
    )
    .join('');
  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<title>${title}</title>
<style>
  @page { size: A4 landscape; margin: 10mm 8mm; }
  * { box-sizing: border-box; }
  body {
    font-family: 'Cairo', 'Segoe UI', Tahoma, Arial, sans-serif;
    font-size: 11px;
    color: #111827;
    margin: 16px;
    line-height: 1.5;
    background: #f8fafc;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }
  .page { max-width: 1100px; margin: 0 auto; background: #fff; padding: 24px; border-radius: 8px; border: 1px solid #e5e7eb; }
  .header { border-bottom: 3px solid #1a56db; padding-bottom: 12px; margin-bottom: 16px; display: flex; justify-content: space-between; align-items: center; }
  .header h1 { font-size: 18px; font-weight: 900; color: #1a56db; margin: 0; }
  .meta { color: #4b5563; font-size: 11px; font-weight: 600; margin-top: 4px; }
  table { width: 100%; border-collapse: collapse; margin-top: 12px; font-size: 10px; }
  th { background: #1e3a5f; color: #fff; padding: 7px 8px; text-align: center; font-weight: 800; font-size: 9px; }
  td { padding: 6px 8px; border-bottom: 1px solid #e5e7eb; }
  tr:nth-child(even) td { background: #fafafa; }
  .footer { margin-top: 16px; padding-top: 10px; border-top: 2px solid #e2e8f0; display: flex; justify-content: space-between; font-size: 9px; color: #9ca3af; }

  /* ─── شريط الإجراءات العلوي التفاعلي ─── */
  .action-bar {
    max-width: 1100px;
    margin: 0 auto 16px;
    background: #0f172a;
    color: #f8fafc;
    border-radius: 10px;
    padding: 12px 18px;
    box-shadow: 0 4px 14px rgba(15, 23, 42, 0.25);
    border: 1px solid #334155;
  }
  .action-bar-content {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    flex-wrap: wrap;
  }
  .action-title { font-size: 13px; font-weight: 800; color: #ffffff; }
  .action-buttons { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  .btn-act {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 7px 14px; font-size: 11px; font-weight: 700;
    font-family: inherit; border-radius: 6px; cursor: pointer; border: none;
    transition: all 0.2s;
  }
  .btn-act-pdf { background: #10b981; color: white; }
  .btn-act-pdf:hover { background: #059669; }
  .btn-act-print { background: #2563eb; color: white; }
  .btn-act-print:hover { background: #1d4ed8; }
  .btn-act-html { background: #334155; color: #f1f5f9; border: 1px solid #475569; }
  .btn-act-html:hover { background: #475569; color: white; }
  .btn-act-close { background: transparent; color: #94a3b8; border: 1px solid #334155; }
  .btn-act-close:hover { color: #f87171; border-color: #ef4444; }
  .action-tip {
    margin-top: 8px; padding-top: 6px; border-top: 1px solid #1e293b;
    font-size: 10px; color: #cbd5e1;
  }

  @media print {
    body { margin: 0; background: #fff; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
    .no-print, .action-bar { display: none !important; }
    .page { border: none; padding: 0; }
  }
</style>
</head>
<body>
<div class="action-bar no-print">
  <div class="action-bar-content">
    <div class="action-title">📄 قائمة «${categoryLabel}» — ${dateLabel}</div>
    <div class="action-buttons">
      <button type="button" class="btn-act btn-act-pdf" onclick="saveAsPdf()" title="حفظ كملف PDF على جهازك">
        📥 تحميل وحفظ كملف PDF
      </button>
      <button type="button" class="btn-act btn-act-print" onclick="saveAsPdf()" title="طباعة فورية">
        🖨️ طباعة
      </button>
      <button type="button" class="btn-act btn-act-html" onclick="downloadHtml()" title="تنزيل نسخة مستقلة">
        💾 تنزيل ملف (HTML)
      </button>
      <button type="button" class="btn-act btn-act-close" onclick="window.close()" title="إغلاق النافذة">
        إغلاق
      </button>
    </div>
  </div>
  <div class="action-tip">
    💡 لحفظ المستند بصيغة PDF: اضغط على زر «تحميل وحفظ كملف PDF» واختر الوجهة (Save as PDF) ثم اضغط حفظ.
  </div>
</div>

<div class="page">
  <div class="header">
    <div>
      <h1>قائمة الحضور — ${categoryLabel}</h1>
      <div class="meta">${dateLabel} &nbsp;·&nbsp; إجمالي الموظفين: ${items.length}</div>
    </div>
    <div style="text-align:left;font-size:12px;font-weight:900;color:#1a56db">منظومة أحلى شباب الإدارية</div>
  </div>

  <table>
    <thead>
      <tr>
        <th style="width:40px">#</th>
        <th style="width:160px">اسم الموظف</th>
        <th style="width:80px">الكود</th>
        <th style="width:120px">القسم</th>
        <th style="width:90px">الحالة</th>
        <th style="width:80px">أول بصمة</th>
        <th style="width:80px">آخر بصمة</th>
        <th style="width:70px">التأخير</th>
      </tr>
    </thead>
    <tbody>${rows}</tbody>
  </table>

  <div class="footer">
    <span>نظام أحلى شباب الإداري — تقرير فئة «${categoryLabel}»</span>
    <span>تاريخ الطباعة: ${new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full', timeStyle: 'short' }).format(new Date())}</span>
  </div>
</div>

<script>
  function saveAsPdf() {
    window.focus();
    try { window.print(); } catch(e) { console.error(e); }
  }
  function downloadHtml() {
    try {
      var clone = document.documentElement.cloneNode(true);
      var noPrintEls = clone.querySelectorAll('.no-print');
      noPrintEls.forEach(function(el) { el.remove(); });
      var htmlContent = "<!DOCTYPE html>\\n" + clone.outerHTML;
      var blob = new Blob(["\\uFEFF" + htmlContent], { type: "text/html;charset=utf-8;" });
      var url = URL.createObjectURL(blob);
      var a = document.createElement("a");
      a.href = url;
      a.download = "قائمة_${category}_${dateIso}.html";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch(e) { console.error(e); }
  }
  setTimeout(function() {
    saveAsPdf();
  }, 400);
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
  const win = window.open('', '_blank', 'width=900,height=700');
  if (!win) {
    const blob = new Blob(['\uFEFF' + html], { type: 'text/html;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `قائمة_الحضور_${cat}_${filters.dateIso}.html`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    return;
  }
  win.document.write(html);
  win.document.close();
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
        const mock = (await loadDomainMocks()).mockAttendanceDashboard;
        // تحويل AttendanceDashboard إلى ExecutiveDailyReport للمعاينة
        return {
          date: targetDate,
          employees: { active: mock.scheduled ?? 0, requiredToday: mock.scheduled ?? 0 },
          attendance: {
            present: mock.present ?? 0,
            late: mock.late ?? 0,
            absent: mock.absent ?? 0,
            notYet: mock.missingCheckout ?? 0,
            checkedOut: mock.present ?? 0,
            missingCheckout: mock.missingCheckout ?? 0,
          },
          workStatus: {
            approvedLeave: mock.onLeave ?? 0,
            missions: mock.onMission ?? 0,
            convoys: 0,
            fundraising: 0,
          },
          requests: { pendingLeave: 0, pendingMission: 0 },
          kpi: { atEmployee: 0, atManager: 0, atHr: 0, ready: 0, overdue: 0 },
          cases: { new: 0, open: 0 },
          followUp: { decisions: 0, missingReports: 0, activeLocationRequests: 0, unansweredLocationRequests: 0 },
          sources: {},
          generatedAt: new Date().toISOString(),
        } as ExecutiveDailyReport;
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
        const summary = executiveDailyReportSchema.parse(mocks.mockAttendanceDashboard);
        return {
          dateIso: targetDate,
          summary,
          employees: [],
          missions: [],
          convoys: [],
          leaves: [],
          locationRequests: [],
          disputes: [],
          reports: [],
        };
      }
      // ملاحظة: يحتاج RPC جديد get_executive_daily_report_detail مع التفاصيل
      // حالياً يعيد الملخص الأساسي كبديل
      const data = await rpc('get_v10_executive_daily_report', { p_date: targetDate });
      const summary = executiveDailyReportSchema.parse(data);
      return {
        dateIso: targetDate,
        summary,
        employees: [],
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

export async function exportExecutiveDailyReportPdf(dateIso?: string): Promise<void> {
  const targetDate = dateIso ?? cairoTodayIso();
  const { exportExecutiveDailyReport } = await import('./exportExecutiveDailyReport');
  const data = await rpc('get_v10_executive_daily_report', { p_date: targetDate });
  const summary = executiveDailyReportSchema.parse(data);
  const detail: ExecutiveDailyReportDetail = {
    dateIso: targetDate,
    summary,
    employees: [],
    missions: [],
    convoys: [],
    leaves: [],
    locationRequests: [],
    disputes: [],
    reports: [],
  };
  exportExecutiveDailyReport(detail);
}
