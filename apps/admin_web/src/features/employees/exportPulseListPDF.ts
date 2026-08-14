import { cairoTodayIso } from '../../core/cairoTime';
import { formatClock } from '../../core/formatTime';
import { esc } from '../attendance/exportAttendancePDF';
import { ATTENDANCE_STATUS_LABELS } from '../management/statusLabels';
import type { EmployeeOverviewRow } from '../management/controlCenterTypes';
import type { PulseDialogKind } from './TodayPulseSection';

// تصدير قائمة نبض اليوم (الحضور/الغياب/التأخر/طلبات الموقع) إلى PDF
// عبر بناء مستند HTML وفتحه ثم تشغيل طباعة المتصفح — نفس نهج exportAttendancePDF.

const PULSE_TITLES: Record<PulseDialogKind, string> = {
  present: 'حضروا اليوم',
  absent: 'تغيّبوا اليوم',
  late: 'تأخّروا اليوم',
  location: 'طلبات الموقع المرسلة',
};

/** ينسّق تاريخًا YYYY-MM-DD كنص عربي كامل (اليوم/الشهر/السنة). */
function fmtFullDate(iso: string): string {
  return new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date(`${iso}T00:00:00`));
}

export function exportPulseListPDF(employees: EmployeeOverviewRow[], kind: PulseDialogKind): void {
  const title = PULSE_TITLES[kind];
  const date = cairoTodayIso();
  const dateLabel = fmtFullDate(date);
  const total = employees.length;

  const rows = employees
    .map((e, i) => {
      const statusLabel = ATTENDANCE_STATUS_LABELS[e.status] ?? e.status;
      return `<tr>
        <td style="text-align:center;font-variant-numeric:tabular-nums">${i + 1}</td>
        <td style="font-weight:700">${esc(e.name)}</td>
        <td style="text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${esc(e.employeeCode ?? '—')}</td>
        <td>${esc(e.department ?? '—')}</td>
        <td style="text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${e.checkInAt ? esc(formatClock(e.checkInAt)) : '—'}</td>
        <td style="text-align:center">${esc(statusLabel)}</td>
      </tr>`;
    })
    .join('');

  const html = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>${esc(title)} — ${esc(date)}</title>
  <style>
    @page { size: A4; margin: 12mm 10mm; }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Cairo', 'Segoe UI', 'Tahoma', 'Arial', sans-serif;
      direction: rtl;
      color: #111827;
      font-size: 11px;
      line-height: 1.5;
      -webkit-print-color-adjust: exact !important;
      print-color-adjust: exact !important;
    }
    .page { max-width: 1100px; margin: 0 auto; }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      border-bottom: 3px solid #1e40af;
      padding-bottom: 12px;
      margin-bottom: 16px;
    }
    .header-right h1 { font-size: 18px; font-weight: 900; color: #1e40af; }
    .header-right p { font-size: 10px; color: #6b7280; margin-top: 2px; }
    .header-left { text-align: left; direction: ltr; }
    .header-left .org { font-size: 13px; font-weight: 900; color: #1e40af; }
    .header-left .sub { font-size: 9px; color: #6b7280; }
    table { width: 100%; border-collapse: collapse; font-size: 10px; }
    thead th {
      background: #1e3a5f;
      color: white;
      padding: 7px 8px;
      text-align: center;
      font-weight: 800;
      font-size: 9px;
    }
    tbody td { padding: 6px 8px; border-bottom: 1px solid #e5e7eb; }
    tbody tr:nth-child(even) { background: #fafafa; }
    .footer {
      margin-top: 16px;
      padding-top: 10px;
      border-top: 2px solid #e2e8f0;
      display: flex;
      justify-content: space-between;
      font-size: 9px;
      color: #9ca3af;
    }
    @media print { body { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; } }
  </style>
</head>
<body>
<div class="page">
  <div class="header">
    <div class="header-right">
      <h1>📋 ${esc(title)}</h1>
      <p>${esc(dateLabel)} · إجمالي: ${total} موظفًا</p>
    </div>
    <div class="header-left">
      <div class="org">${esc(date)}</div>
      <div class="sub">منظومة أحلى شباب الإدارية</div>
    </div>
  </div>

  <table>
    <thead>
      <tr>
        <th>#</th><th>الاسم</th><th>كود الموظف</th><th>الإدارة</th><th>وقت الحضور</th><th>الحالة</th>
      </tr>
    </thead>
    <tbody>
      ${rows}
    </tbody>
  </table>

  <div class="footer">
    <span>تم الإنشاء بواسطة منظومة أحلى شباب الإدارية</span>
    <span>تاريخ الطباعة: ${new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full', timeStyle: 'short' }).format(new Date())}</span>
  </div>
</div>

<script>
  window.onload = function() { setTimeout(function() { window.print(); }, 400); };
</script>
</body>
</html>`;

  const win = window.open('', '_blank', 'width=900,height=700');
  if (!win) return;
  win.document.write(html);
  win.document.close();
}
