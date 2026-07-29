import type { AttendanceStatement } from '@ahla/shared-contracts';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

// حالات اليوم التي تُعرض بلون تحذيري
const WARN_STATUSES = new Set(['غائب دون إذن', 'يحتاج مراجعة']);

function fmtTime(t: string | null) {
  return t ? t.slice(0, 5) : '—';
}

function pctColor(pct: number) {
  return pct >= 90 ? '#059669' : pct >= 75 ? '#f59e0b' : '#dc2626';
}

/** يمنع حقن HTML عند بناء المستند بالـ template literals */
function esc(value: unknown): string {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/**
 * يُنشئ مستند HTML منسّق لكشف الحضور ويفتحه في نافذة جديدة مع تشغيل طباعة تلقائي.
 * المستخدم يمكنه حفظه كـ PDF مباشرة من حوار الطباعة.
 */
export function exportAttendancePDF(data: AttendanceStatement) {
  const { employee: emp, period, days, summary: s } = data;
  const attendancePct = s.attendanceRate ?? (s.scheduledDays > 0 ? (s.presentDays / s.scheduledDays * 100) : 0);
  const compliancePct = s.hoursComplianceRate ?? 0;
  const monthName = MONTHS[period.month - 1] ?? '';

  const dayRows = days.map((d) => {
    const tags: string[] = [];
    if (d.isAbsent) tags.push('غائب');
    if (d.isOfficialHoliday) tags.push('عطلة رسمية');
    if (d.hasLeave) tags.push('إجازة');
    if (d.hasMission) tags.push('مأمورية');
    if (d.hasLatePermit) tags.push('إذن تأخير');
    if (d.hasEarlyPermit) tags.push('إذن انصراف');
    if (!d.hasLatePermit && !d.hasEarlyPermit && d.hasPermit) tags.push('إذن');
    if (d.hasConvoyFundi) tags.push('قافلة/فاندي');
    if (d.missingCheckIn) tags.push('نقص حضور');
    if (d.missingCheckOut) tags.push('نقص انصراف');
    if (d.hasCorrection) tags.push('تصحيح');
    if (d.penalties > 0) tags.push(`جزاء: ${d.penalties}`);

    const isRest = d.status === 'راحة أسبوعية' || d.status === 'عطلة رسمية';
    const isWarn = WARN_STATUSES.has(d.status);
    const rowBg = isRest ? '#f0f9ff' : isWarn ? '#fef2f2' : '';
    const statusColor = isWarn ? '#dc2626' : isRest ? '#0369a1' : '#111827';

    return `<tr style="border-bottom:1px solid #e5e7eb;${rowBg ? `background:${rowBg};` : ''}">
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${esc(d.date)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(d.dayNameAr)}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${esc(fmtTime(d.checkIn))}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${esc(fmtTime(d.checkOut))}</td>
      <td style="padding:6px 8px;text-align:center">${esc(d.shiftName) || '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums">${d.workHours ? d.workHours.toFixed(1) : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;${d.lateMinutes > 0 ? 'color:#d97706;font-weight:700;' : ''}">${d.lateMinutes ? `${d.lateMinutes} د` : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;${d.earlyLeaveMinutes > 0 ? 'color:#d97706;font-weight:700;' : ''}">${d.earlyLeaveMinutes ? `${d.earlyLeaveMinutes} د` : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;${d.overtimeMinutes > 0 ? 'color:#059669;font-weight:700;' : ''}">${d.overtimeMinutes ? `${d.overtimeMinutes} د` : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-weight:700;color:${statusColor}">${esc(d.status)}</td>
      <td style="padding:6px 8px;text-align:center;font-size:9px">${tags.join('، ') || esc(d.correctionNote ?? '')}</td>
    </tr>`;
  }).join('\n');

  const html = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>كشف حضور — ${esc(emp.fullNameAr)} — ${monthName} ${period.year}</title>
  <style>
    @page {
      size: A4 landscape;
      margin: 12mm 10mm;
    }
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

    /* ─── الرأس ─── */
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

    /* ─── بيانات الموظف ─── */
    .emp-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 8px;
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      padding: 12px;
      margin-bottom: 14px;
    }
    .emp-field label { display: block; font-size: 9px; color: #6b7280; font-weight: 700; }
    .emp-field span { display: block; font-size: 12px; font-weight: 800; margin-top: 1px; }

    /* ─── الملخص ─── */
    .summary-grid {
      display: grid;
      grid-template-columns: repeat(8, 1fr);
      gap: 6px;
      margin-bottom: 10px;
    }
    .metric {
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 6px;
      padding: 8px;
      text-align: center;
    }
    .metric .label { font-size: 8px; color: #6b7280; font-weight: 700; }
    .metric .value { font-size: 18px; font-weight: 900; color: #111827; margin-top: 2px; }
    .metric .hint { font-size: 8px; color: #9ca3af; margin-top: 1px; }
    .metric.warn .value { color: #dc2626; }
    .metric.good .value { color: #059669; }

    /* ─── نسب الحضور/الالتزام ─── */
    .rates-bar {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: center;
      background: #f0f9ff;
      border: 1px solid #bfdbfe;
      border-radius: 8px;
      padding: 8px 16px;
      margin-bottom: 10px;
    }
    .rate-item { text-align: center; }
    .rate-item .pct { font-size: 22px; font-weight: 900; }
    .rate-item .lbl { font-size: 9px; color: #6b7280; }

    /* ─── شريط الإحصائيات السريعة ─── */
    .stats-bar {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      background: #fefce8;
      border: 1px solid #fde68a;
      border-radius: 6px;
      padding: 6px 12px;
      margin-bottom: 10px;
      font-size: 10px;
    }
    .stat-item { display: flex; gap: 4px; align-items: center; }
    .stat-item .s-label { color: #6b7280; }
    .stat-item .s-value { font-weight: 800; }

    /* ─── الجدول ─── */
    table { width: 100%; border-collapse: collapse; font-size: 10px; }
    thead th {
      background: #1e3a5f;
      color: white;
      padding: 7px 8px;
      text-align: center;
      font-weight: 800;
      font-size: 9px;
    }
    tbody td { border-bottom: 1px solid #e5e7eb; }
    tbody tr:nth-child(even) { background: #fafafa; }

    /* ─── التذييل ─── */
    .footer {
      margin-top: 16px;
      padding-top: 10px;
      border-top: 2px solid #e2e8f0;
      display: flex;
      justify-content: space-between;
      font-size: 9px;
      color: #9ca3af;
    }
    .signatures {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 20px;
      margin-top: 30px;
    }
    .sig-box {
      text-align: center;
      padding-top: 40px;
      border-top: 1px solid #d1d5db;
      font-size: 10px;
      color: #6b7280;
    }

    @media print {
      body { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
    }
  </style>
</head>
<body>
<div class="page">
  <!-- الرأس -->
  <div class="header">
    <div class="header-right">
      <h1>📋 كشف الحضور والانصراف الشهري</h1>
      <p>${monthName} ${period.year} — من ${esc(period.startDate)} إلى ${esc(period.endDate)}</p>
    </div>
    <div class="header-left">
      <div class="org">جمعية خواطر أحلى شباب</div>
      <div class="sub">منظومة الإدارة المؤسسية</div>
    </div>
  </div>

  <!-- بيانات الموظف -->
  <div class="emp-grid">
    <div class="emp-field"><label>الاسم</label><span>${esc(emp.fullNameAr)}</span></div>
    <div class="emp-field"><label>الكود</label><span>${esc(emp.employeeCode ?? '—')}</span></div>
    <div class="emp-field"><label>الإدارة</label><span>${esc(emp.department)}</span></div>
    <div class="emp-field"><label>المسمى الوظيفي</label><span>${esc(emp.jobTitle)}</span></div>
    <div class="emp-field"><label>الفرع</label><span>${esc(emp.branch)}</span></div>
    <div class="emp-field"><label>المدير المباشر</label><span>${esc(emp.manager)}</span></div>
    <div class="emp-field"><label>تاريخ التعيين</label><span style="direction:ltr;text-align:right">${esc(emp.hireDate ?? '—')}</span></div>
    <div class="emp-field"><label>الفترة</label><span>${monthName} ${period.year}</span></div>
  </div>

  <!-- نسب الحضور والالتزام -->
  <div class="rates-bar">
    <div class="rate-item">
      <div class="pct" style="color:${pctColor(attendancePct)}">${attendancePct.toFixed(0)}%</div>
      <div class="lbl">نسبة الحضور</div>
    </div>
    <div style="width:1px;height:40px;background:#bfdbfe"></div>
    <div class="rate-item">
      <div class="pct" style="color:${pctColor(compliancePct)}">${compliancePct.toFixed(0)}%</div>
      <div class="lbl">التزام الساعات</div>
    </div>
  </div>

  <!-- ملخص الأرقام -->
  <div class="summary-grid">
    <div class="metric"><div class="label">أيام الحضور</div><div class="value">${s.presentDays}</div><div class="hint">من ${s.scheduledDays} مجدولة</div></div>
    <div class="metric${s.absentDays > 0 ? ' warn' : ''}"><div class="label">أيام الغياب</div><div class="value">${s.absentDays}</div></div>
    <div class="metric"><div class="label">أيام الإجازات</div><div class="value">${s.leaveDays}</div></div>
    <div class="metric"><div class="label">أيام المأموريات</div><div class="value">${s.missionDays}</div></div>
    <div class="metric"><div class="label">إذنات</div><div class="value">${s.permitCount}</div></div>
    <div class="metric"><div class="label">قوافل/فاندي</div><div class="value">${s.convoyFundiDays}</div></div>
    <div class="metric"><div class="label">ساعات العمل</div><div class="value">${s.totalWorkHours.toFixed(1)}</div><div class="hint">مطلوب ${(s.totalRequiredHours ?? 0).toFixed(1)}</div></div>
    <div class="metric good"><div class="label">ساعات إضافية</div><div class="value">${s.totalOvertimeMinutes} د</div></div>
  </div>

  <!-- شريط الإحصائيات السريعة -->
  <div class="stats-bar">
    <div class="stat-item"><span class="s-label">تأخير كلي:</span><span class="s-value">${s.totalLateMinutes} د</span></div>
    <div class="stat-item"><span class="s-label">خروج مبكر:</span><span class="s-value">${s.totalEarlyLeaveMinutes} د</span></div>
    <div class="stat-item"><span class="s-label">نسيان حضور:</span><span class="s-value">${s.missingCheckInCount}</span></div>
    <div class="stat-item"><span class="s-label">نسيان انصراف:</span><span class="s-value">${s.missingCheckOutCount}</span></div>
    <div class="stat-item"><span class="s-label">عطل رسمية:</span><span class="s-value">${s.holidayDays}</span></div>
    <div class="stat-item"><span class="s-label">أيام راحة:</span><span class="s-value">${s.restDays}</span></div>
    <div class="stat-item"><span class="s-label">تصحيحات:</span><span class="s-value">${s.correctionCount}</span></div>
  </div>

  <!-- الجدول اليومي -->
  <table>
    <thead>
      <tr>
        <th>التاريخ</th><th>اليوم</th><th>الحضور</th><th>الانصراف</th>
        <th>الوردية</th><th>ساعات فعلية</th><th>التأخير</th>
        <th>خروج مبكر</th><th>إضافي</th><th>الحالة</th><th>ملاحظات</th>
      </tr>
    </thead>
    <tbody>
      ${dayRows}
    </tbody>
  </table>

  <!-- التذييل -->
  <div class="footer">
    <span>تم الإنشاء بواسطة منظومة أحلى شباب الإدارية</span>
    <span>تاريخ الطباعة: ${new Date().toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' })}</span>
  </div>

  <!-- التوقيعات -->
  <div class="signatures">
    <div class="sig-box">الموظف</div>
    <div class="sig-box">المدير المباشر</div>
    <div class="sig-box">الموارد البشرية</div>
  </div>
</div>

<script>
  window.onload = function() {
    setTimeout(function() { window.print(); }, 400);
  };
</script>
</body>
</html>`;

  const win = window.open('', '_blank');
  if (!win) return;
  win.document.write(html);
  win.document.close();
}
