import { attendanceRosterPageSchema, type AttendanceRosterItem } from '@ahla/shared-contracts';
import { rpc } from '../../core/rpc';
import { fmtMinutesCompact } from './attendanceShared';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

const WEEKDAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

const STATUS_LABELS: Record<string, string> = {
  present: 'حاضر',
  late: 'متأخر',
  absent: 'غائب',
  on_leave: 'إجازة',
  on_mission: 'مأمورية',
  holiday: 'عطلة',
  weekend: 'عطلة أسبوعية',
  pending_review: 'تحتاج مراجعة',
  missing_checkout: 'بصمة بلا انصراف',
};

interface RangeFilters {
  dept?: string;
  branch?: string;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] ?? c);
}

function fmtDay(dateIso: string): string {
  const [y, m, d] = dateIso.split('-').map(Number);
  if (!y || !m || !d) return dateIso;
  const dt = new Date(Date.UTC(y, m - 1, d));
  const weekday = WEEKDAYS[dt.getUTCDay()] ?? '';
  return `${d} ${MONTHS[m - 1]} (${weekday})`;
}

async function fetchRosterDay(dateIso: string, filters?: RangeFilters): Promise<AttendanceRosterItem[]> {
  try {
    const data = await rpc('get_attendance_day_roster', {
      p_date: dateIso,
      p_category: 'scheduled',
      p_search: null,
      p_department_id: filters?.dept || null,
      p_branch_id: filters?.branch || null,
      p_manager_id: null,
      p_sort: 'name',
      p_direction: 'asc',
      p_limit: 1000,
      p_offset: 0,
    });
    const page = attendanceRosterPageSchema.parse(data);
    return page.items;
  } catch {
    return [];
  }
}

/** تنزيل التقرير كملف PDF (كان ملف HTML). */
export function downloadRangeReportHtml(title: string, html: string): void {
  openPrintWindow(title.replace(/\.html$/i, ''), html);
}

/** تصدير التقرير كملف PDF حقيقي؛ نافذة الطباعة بديل فقط عند تعذّر التوليد. */
function openPrintWindow(title: string, html: string): void {
  void import('../../core/pdfExport')
    .then(({ downloadHtmlAsPdf }) => downloadHtmlAsPdf(html, title))
    .catch(() => {
      const win = window.open('', '_blank', 'width=1120,height=800');
      if (!win) return;
      win.document.open();
      win.document.write(html);
      win.document.close();
    });
}
interface RosterGate {
  employees: AttendanceRosterItem[];
  // مفتاح: `${employeeId}|${date}`
  dayStatus: Map<string, string | null>;
  dayLateMinutes: Map<string, number | null>;
}

async function buildRosterGate(dates: string[], filters?: RangeFilters): Promise<RosterGate> {
  const employeeMap = new Map<string, AttendanceRosterItem>();
  const dayStatus = new Map<string, string | null>();
  const dayLateMinutes = new Map<string, number | null>();

  const perDay = await Promise.all(dates.map((d) => fetchRosterDay(d, filters)));
  perDay.forEach((dayItems, idx) => {
    const date = dates[idx];
    for (const item of dayItems) {
      const key = item.employeeId;
      if (!employeeMap.has(key)) employeeMap.set(key, item);
      dayStatus.set(`${key}|${date}`, item.status);
      dayLateMinutes.set(`${key}|${date}`, item.lateMinutes);
    }
  });

  return {
    employees: Array.from(employeeMap.values()),
    dayStatus,
    dayLateMinutes,
  };
}

function renderTable(gate: RosterGate, dates: string[]): { rows: string; cols: string } {
  const cols = dates.map((d) => `<th>${escapeHtml(fmtDay(d))}</th>`).join('');
  const rows = gate.employees
    .map((e) => {
      const cells = dates
        .map((d) => {
          const key = `${e.employeeId}|${d}`;
          const status = gate.dayStatus.get(key);
          if (!status) return '<td style="padding:4px 6px;text-align:center;background:#f9fafb">—</td>';
          const label = STATUS_LABELS[status] ?? status;
          const late = gate.dayLateMinutes.get(key);
          const lateHint = late ? `<div style="font-size:6px;color:#dc2626">تأخير ${fmtMinutesCompact(late)}</div>` : '';
          return `<td style="padding:4px 6px;text-align:center">${escapeHtml(label)}${lateHint}</td>`;
        })
        .join('');
      return `<tr>
        <td style="padding:4px 6px;text-align:center">${escapeHtml(e.employeeCode ?? '—')}</td>
        <td style="padding:4px 6px;font-weight:700">${escapeHtml(e.employeeName)}</td>
        <td style="padding:4px 6px;text-align:center">${escapeHtml(e.departmentName ?? '—')}</td>
        ${cells}
      </tr>`;
    })
    .join('');
  return { rows, cols };
}

function shell(title: string, subtitle: string, employeeCount: number, rows: string, cols: string, cssTable: string): string {
  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<title>${escapeHtml(title)}</title>
<style>
  @page { size: A4 landscape; margin: 8mm 6mm; }
  * { box-sizing: border-box; }
  body { font-family: 'Cairo', 'Segoe UI', Tahoma, Arial, sans-serif; direction: rtl; color: #111827; font-size: 9px; line-height: 1.4; -webkit-print-color-adjust: exact; print-color-adjust: exact; margin: 16px; background: #f8fafc; }
  .page { max-width: 1120px; margin: 0 auto; background: #fff; padding: 24px; border-radius: 8px; border: 1px solid #e5e7eb; }
  .header { border-bottom: 3px solid #1e40af; padding-bottom: 10px; margin-bottom: 14px; }
  .header h1 { font-size: 16px; font-weight: 900; color: #1e40af; margin: 0; }
  .header p { margin: 4px 0 0; font-size: 11px; color: #4b5563; font-weight: 600; }
  table { width: 100%; border-collapse: collapse; ${cssTable} }
  thead th { background: #1e3a5f; color: white; padding: 6px 4px; text-align: center; font-weight: 800; font-size: 8px; border: 1px solid #1e3a5f; }
  tbody td { border: 1px solid #e5e7eb; }
  tbody tr:nth-child(even) { background: #fafafa; }
  .sign { margin-top: 30px; display: flex; justify-content: space-between; }
  .sign div { width: 30%; text-align: center; font-size: 10px; font-weight: 700; color: #374151; }
  .sign .line { border-bottom: 1px solid #111827; height: 24px; margin-bottom: 6px; }

  /* ─── شريط الإجراءات العلوي التفاعلي (مخفي عند الطباعة وحفظ PDF) ─── */
  .action-bar {
    max-width: 1120px;
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
    <div class="action-title">📄 ${escapeHtml(title)}</div>
    <div class="action-buttons">
      <button type="button" class="btn-act btn-act-pdf" onclick="saveAsPdf()" title="حفظ كملف PDF على جهازك">
        📥 تحميل وحفظ كملف PDF
      </button>
      <button type="button" class="btn-act btn-act-print" onclick="saveAsPdf()" title="طباعة فورية">
        🖨️ طباعة
      </button>
      <button type="button" class="btn-act btn-act-close" onclick="window.close()" title="إغلاق النافذة">
        إغلاق
      </button>
    </div>
  </div>
  <div class="action-tip">
    💡 لحفظ المستند كملف PDF: اضغط على زر «تحميل وحفظ كملف PDF» واختر الوجهة (Save as PDF) ثم اضغط حفظ.
  </div>
</div>

<div class="page">
  <div class="header">
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(subtitle)} — عدد الموظفين: ${employeeCount}</p>
  </div>
  <table>
    <thead><tr><th style="width:70px">الكود</th><th style="width:160px">الاسم</th><th style="width:110px">الإدارة</th>${cols}</tr></thead>
    <tbody>${rows}</tbody>
  </table>
  <div class="sign">
    <div><div class="line"></div>إعداد: قسم الموارد البشرية</div>
    <div><div class="line"></div>اعتماد المدير التنفيذي</div>
    <div><div class="line"></div>التاريخ والختم</div>
  </div>
</div>

<script>
  function saveAsPdf() {
    window.focus();
    try { window.print(); } catch(e) { console.error(e); }
  }
  setTimeout(function() {
    saveAsPdf();
  }, 400);
</script>
</body>
</html>`;
}

export function dateRange(start: string, end: string): string[] {
  const [sy, sm, sd] = start.split('-').map(Number);
  const [ey, em, ed] = end.split('-').map(Number);
  if (!sy || !sm || !sd || !ey || !em || !ed) return [];

  const cursor = new Date(Date.UTC(sy, sm - 1, sd));
  const last = new Date(Date.UTC(ey, em - 1, ed));
  const dates: string[] = [];

  while (cursor <= last) {
    const y = cursor.getUTCFullYear();
    const m = cursor.getUTCMonth() + 1;
    const d = cursor.getUTCDate();
    dates.push(`${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`);
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return dates;
}

export function monthDates(month: string): string[] {
  const [y, m] = month.split('-').map(Number);
  if (!y || !m) return [];
  const daysInMonth = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const dates: string[] = [];
  for (let d = 1; d <= daysInMonth; d += 1) {
    dates.push(`${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`);
  }
  return dates;
}

/**
 * تصدير كشف أسبوعي (PDF/طباعة): employeeIdOrScope === 'all' يعني كل الشركة.
 */
export async function exportWeeklyAttendancePdf(employeeIdOrScope: string, start: string, end: string, filters?: RangeFilters): Promise<void> {
  const dates = dateRange(start, end);
  if (dates.length === 0) throw new Error('نطاق تاريخ غير صالح');
  const gate = await buildRosterGate(dates, filters);
  if (employeeIdOrScope !== 'all') {
    gate.employees = gate.employees.filter((e) => e.employeeId === employeeIdOrScope);
  }
  const { rows, cols } = renderTable(gate, dates);
  const weekLabel = `الفترة من ${fmtDay(start)} إلى ${fmtDay(end)}`;
  const title = employeeIdOrScope === 'all' ? 'كشف حضور الشركة الأسبوعي' : 'كشف حضور الموظف الأسبوعي';
  openPrintWindow('كشف-حضور-أسبوعي', shell(title, weekLabel, gate.employees.length, rows, cols, 'font-size:7px;'));
}

/**
 * تصدير كشف شهري (PDF/طباعة) لكل أيام الشهر.
 */
export async function exportMonthlyAttendancePdf(month: string, filters?: RangeFilters): Promise<void> {
  const dates = monthDates(month);
  if (dates.length === 0) throw new Error('شهر غير صالح');
  const gate = await buildRosterGate(dates, filters);
  const { rows, cols } = renderTable(gate, dates);
  const [y, m] = month.split('-').map(Number);
  const monthName = MONTHS[Number(m) - 1] ?? m;
  const label = `شهر ${monthName} ${y} (من 1 إلى ${dates.length} ${monthName})`;
  const title = `كشف حضور الموظفين الشهري — ${monthName} ${y}`;
  openPrintWindow('كشف-حضور-شهري', shell(title, label, gate.employees.length, rows, cols, 'font-size:6px;'));
}
