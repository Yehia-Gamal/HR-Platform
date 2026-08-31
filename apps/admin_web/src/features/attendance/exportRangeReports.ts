import { attendanceRosterPageSchema, type AttendanceRosterItem } from '@ahla/shared-contracts';
import { rpc } from '../../core/rpc';

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
  const d = new Date(`${dateIso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return dateIso;
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${WEEKDAYS[d.getDay()]}`;
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

function openPrintWindow(title: string, html: string): void {
  const win = window.open('', '_blank', 'width=1000,height=800');
  if (!win) {
    const blob = new Blob([html], { type: 'text/html;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${title}.html`;
    a.click();
    URL.revokeObjectURL(url);
    return;
  }
  win.document.open();
  win.document.write(html);
  win.document.close();
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
      const key = Date.parse(item.firstCheckIn ?? '') ? item.employeeId : item.employeeId;
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
          const lateHint = late ? `<div style="font-size:6px;color:#dc2626">تأخير ${Math.round(late)}د</div>` : '';
          return `<td style="padding:4px 6px;text-align:center">${escapeHtml(label)}${lateHint}</td>`;
        })
        .join('');
      return `<tr>
        <td style="padding:4px 6px;text-align:center">${escapeHtml(e.employeeCode ?? '—')}</td>
        <td style="padding:4px 6px">${escapeHtml(e.employeeName)}</td>
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
  @page { size: A4 landscape; margin: 10mm 8mm; }
  * { box-sizing: border-box; }
  body { font-family: 'Cairo', 'Segoe UI', sans-serif; direction: rtl; color: #111827; font-size: 9px; line-height: 1.4; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .page { max-width: 1120px; margin: 0 auto; }
  .header { border-bottom: 3px solid #1e40af; padding-bottom: 10px; margin-bottom: 14px; }
  .header h1 { font-size: 16px; font-weight: 900; color: #1e40af; margin: 0; }
  .header p { margin: 4px 0 0; font-size: 11px; color: #6b7280; }
  table { width: 100%; border-collapse: collapse; ${cssTable} }
  thead th { background: #1e3a5f; color: white; padding: 4px 4px; text-align: center; font-weight: 800; font-size: 6px; }
  tbody td { border-bottom: 1px solid #e5e7eb; }
  tbody tr:nth-child(even) { background: #fafafa; }
  .sign { margin-top: 30px; display: flex; justify-content: space-between; }
  .sign div { width: 30%; }
  .sign .line { border-bottom: 1px solid #111827; height: 20px; }
</style>
</head>
<body>
<div class="page">
  <div class="header">
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(subtitle)} — عدد الموظفين: ${employeeCount}</p>
  </div>
  <table>
    <thead><tr><th>الكود</th><th>الاسم</th><th>الإدارة</th>${cols}</tr></thead>
    <tbody>${rows}</tbody>
  </table>
  <div class="sign">
    <div><div class="line"></div>إعداد: قسم الموارد البشرية</div>
    <div><div class="line"></div>اعتماد المدير التنفيذي</div>
    <div><div class="line"></div>التاريخ</div>
  </div>
</div>
</body>
</html>`;
}

function dateRange(start: string, end: string): string[] {
  const dates: string[] = [];
  const cursor = new Date(`${start}T00:00:00`);
  const last = new Date(`${end}T00:00:00`);
  while (cursor <= last) {
    dates.push(cursor.toISOString().slice(0, 10));
    cursor.setDate(cursor.getDate() + 1);
  }
  return dates;
}

function monthDates(month: string): string[] {
  const [y, m] = month.split('-').map(Number);
  if (!y || !m) return [];
  const daysInMonth = new Date(y, m, 0).getDate();
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
  const weekLabel = `${fmtDay(start)} — ${fmtDay(end)}`;
  const title = employeeIdOrScope === 'all' ? 'كشف حضور الشركة الأسبوعي' : 'كشف حضور الموظف الأسبوعي';
  openPrintWindow('كشف-أسبوعي', shell(title, weekLabel, gate.employees.length, rows, cols, 'font-size:7px;'));
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
  const label = `${MONTHS[Number(m) - 1] ?? m} ${y}`;
  const title = `كشف حضور الموظفين الشهري — ${label}`;
  openPrintWindow('كشف-شهري', shell(title, label, gate.employees.length, rows, cols, 'font-size:6px;'));
}
