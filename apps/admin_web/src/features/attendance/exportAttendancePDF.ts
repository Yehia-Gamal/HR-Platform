import type { AttendanceStatement } from '@ahla/shared-contracts';
import { attendanceRateParts, fmtMinutesCompact, fmtMinutesLong } from './attendanceShared';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

// حالات اليوم التي تُعرض بلون تحذيري
const WARN_STATUSES = new Set(['غائب دون إذن', 'يحتاج مراجعة']);

export function fmtTime(t: string | null) {
  if (!t) return '—';
  const m = /^(\d{1,2}):(\d{2})/.exec(t);
  if (!m) return t;
  let h = parseInt(m[1], 10);
  const min = m[2];
  if (Number.isNaN(h)) return t;
  // 0449: عرض بنظام 12 ساعة مع ص/م
  const period = h < 12 ? 'ص' : 'م';
  h = h % 12 === 0 ? 12 : h % 12;
  return `${String(h).padStart(2, '0')}:${min} ${period}`;
}

export function pctColor(pct: number) {
  return pct >= 90 ? '#059669' : pct >= 75 ? '#f59e0b' : '#dc2626';
}

/** يمنع حقن HTML عند بناء المستند بالـ template literals */
export function esc(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * بناء محتوى جسم كشف الحضور لموظف واحد (داخل <body>) — يُعاد استخدامه لبناء
 * كشف منفصل لكل موظف أو كشف شامل يضم الجميع.
 */
export function buildStatementBodyHtml(data: AttendanceStatement, orgName = 'جمعية خواطر أحلى شباب', systemName = 'منظومة أحلى شباب الإدارية'): string {
  const { employee: emp, period, days, summary: s } = data;
  const { dueDays, presentInDue } = attendanceRateParts(s);
  const attendancePct = s.attendanceRate ?? (dueDays > 0 ? (presentInDue / dueDays) * 100 : 0);
  const compliancePct = s.hoursComplianceRate ?? 0;
  const complianceAvailable = s.hoursComplianceAvailable || s.totalRequiredHours > 0;
  const monthName = MONTHS[period.month - 1] ?? '';
  const convoyDays = days.filter((d) => (d.status?.includes('قافلة') || d.hasConvoyFundi) && !d.status?.includes('فاندي')).length;
  const fundiDays = days.filter((d) => d.status?.includes('فاندي')).length;
  const cDays = days.length > 0 ? convoyDays : s.convoyFundiDays;
  const fDays = days.length > 0 ? fundiDays : 0;

  const dayRows = days
    .map((d) => {
      const tags: string[] = [];
      if (d.isAbsent) tags.push('غائب');
      if (d.isOfficialHoliday) tags.push('عطلة رسمية');
      if (d.hasLeave) tags.push('إجازة');
      if (d.hasMission) tags.push('مأمورية');
      if (d.hasLatePermit) tags.push('إذن حضور');
      if (d.hasEarlyPermit) tags.push('إذن انصراف');
      if (!d.hasLatePermit && !d.hasEarlyPermit && d.hasPermit) tags.push('إذن');
      if (d.hasConvoyFundi) tags.push(d.status.includes('فاندي') ? 'فاندي (ترفيهي)' : 'قافلة مساعدات');
      if (d.missingCheckIn) tags.push('نقص حضور');
      if (d.missingCheckOut) tags.push('نقص انصراف');
      if (d.isOpenShift) tags.push('بانتظار الانصراف');
      if (d.isFuture) tags.push('قادم');
      if (d.hasCorrection) tags.push('تصحيح');
      if (d.adminOverride) tags.push('تعديل إداري');
      if (d.penalties > 0) tags.push(`جزاء: ${d.penalties}`);

      const isRest = d.status === 'راحة أسبوعية' || d.status === 'عطلة رسمية';
      const isWarn = WARN_STATUSES.has(d.status);
      const rowBg = d.isFuture ? '#f8fafc' : d.isOpenShift ? '#f0f9ff' : isRest ? '#f0f9ff' : isWarn ? '#fef2f2' : '';
      const statusColor = isWarn ? '#dc2626' : isRest ? '#0369a1' : '#111827';

      return `<tr style="border-bottom:1px solid #e5e7eb;${rowBg ? `background:${rowBg};` : ''}">
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${esc(d.date)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(d.dayNameAr)}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${esc(fmtTime(d.checkIn))}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${esc(fmtTime(d.checkOut))}</td>
      <td style="padding:6px 8px;text-align:center">${esc(d.shiftName) || '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums">${d.workHours ? d.workHours.toFixed(1) : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;${d.lateMinutes > 0 ? 'color:#d97706;font-weight:700;' : ''}">${d.lateMinutes ? fmtMinutesCompact(d.lateMinutes) : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;${d.earlyLeaveMinutes > 0 ? 'color:#d97706;font-weight:700;' : ''}">${d.earlyLeaveMinutes ? fmtMinutesCompact(d.earlyLeaveMinutes) : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;${d.overtimeMinutes > 0 ? 'color:#059669;font-weight:700;' : ''}">${d.overtimeMinutes ? fmtMinutesCompact(d.overtimeMinutes) : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-weight:700;color:${statusColor}">${esc(d.status)}</td>
      <td style="padding:6px 8px;text-align:center;font-size:9px">${tags.join('، ') || esc(d.correctionNote ?? '')}</td>
    </tr>`;
    })
    .join('\n');

  return `<div class="page">
  <!-- الرأس -->
  <div class="header">
    <div class="header-right">
      <h1>📋 كشف الحضور والانصراف الشهري</h1>
      <p>${monthName} ${period.year} — من ${esc(period.startDate)} إلى ${esc(period.endDate)} (${s.totalDays} يومًا)</p>
    </div>
    <div class="header-left">
      <div class="org">${esc(orgName)}</div>
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
    <div class="emp-field"><label>الفترة</label><span>${monthName} ${period.year} (${s.totalDays} يومًا)</span></div>
  </div>

  <!-- نسب الحضور والالتزام -->
  <div class="rates-bar">
    <div class="rate-item">
      <div class="pct" style="color:${pctColor(attendancePct)}">${attendancePct.toFixed(0)}%</div>
      <div class="lbl">نسبة الحضور</div>
    </div>
    <div style="width:1px;height:40px;background:#bfdbfe"></div>
    <div class="rate-item">
      <div class="pct" style="color:${complianceAvailable ? pctColor(compliancePct) : '#64748b'}">${complianceAvailable ? `${compliancePct.toFixed(0)}%` : 'غير متاح'}</div>
      <div class="lbl">التزام الساعات</div>
    </div>
  </div>

  <!-- ملخص الأرقام -->
  <div class="summary-grid">
    <div class="metric"><div class="label">الحضور المحتسب</div><div class="value">${presentInDue}</div><div class="hint">من ${dueDays} أيام مستحقة ومقفلة</div></div>
    <div class="metric${s.absentDays > 0 ? ' warn' : ''}"><div class="label">أيام الغياب</div><div class="value">${s.absentDays}</div></div>
    <div class="metric"><div class="label">وردية مفتوحة</div><div class="value">${s.openShiftDays}</div><div class="hint">بانتظار الانصراف</div></div>
    <div class="metric"><div class="label">أيام قادمة</div><div class="value">${s.upcomingDays}</div><div class="hint">لا تُحسب غيابًا</div></div>
    <div class="metric"><div class="label">أيام الإجازات</div><div class="value">${s.leaveDays}</div></div>
    <div class="metric"><div class="label">أيام المأموريات</div><div class="value">${s.missionDays}</div></div>
    <div class="metric"><div class="label">أذونات</div><div class="value">${s.permitCount}</div></div>
    <div class="metric"><div class="label">أيام القوافل</div><div class="value">${cDays}</div></div>
    <div class="metric"><div class="label">أيام الفاندي</div><div class="value">${fDays}</div></div>
    <div class="metric"><div class="label">ساعات العمل</div><div class="value">${s.totalWorkHours.toFixed(1)}</div><div class="hint">${complianceAvailable ? `مطلوب ${(s.totalRequiredHours ?? 0).toFixed(1)}` : 'الساعات المطلوبة غير متاحة'}</div></div>
    <div class="metric good"><div class="label">ساعات إضافية</div><div class="value">${fmtMinutesLong(s.totalOvertimeMinutes)}</div></div>
  </div>

  <!-- شريط الإحصائيات السريعة -->
  <div class="stats-bar">
    <div class="stat-item"><span class="s-label">تأخير كلي:</span><span class="s-value">${fmtMinutesLong(s.totalLateMinutes)}</span></div>
    <div class="stat-item"><span class="s-label">خروج مبكر:</span><span class="s-value">${fmtMinutesLong(s.totalEarlyLeaveMinutes)}</span></div>
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
    <span>تم الإنشاء بواسطة ${esc(systemName)}</span>
    <span>تاريخ الطباعة: ${new Date().toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' })}</span>
  </div>

  <!-- التوقيعات -->
  <div class="signatures">
    <div class="sig-box">الموظف</div>
    <div class="sig-box">المدير المباشر</div>
    <div class="sig-box">الموارد البشرية</div>
  </div>
</div>`;
}

/**
 * هيكل مستند HTML كامل يُغلّف واحدًا أو أكثر من «أجسام الكشوف».
 * عند تمرير autoPrint: يضيف سكربت يفتح نافذة الطباعة تلقائيًا بعد التحميل.
 */
export function attendanceDocumentShell(title: string, bodyHtml: string, autoPrint = false): string {
  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>${esc(title)}</title>
  <style>
    @page {
      size: A4 landscape;
      margin: 10mm 8mm;
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
      margin: 16px;
      background: #f8fafc;
    }
    .page { max-width: 1100px; margin: 0 auto; background: #fff; padding: 24px; border-radius: 8px; border: 1px solid #e5e7eb; }
    .page-break { page-break-after: always; break-after: page; }

    /* ─── شريط الإجراءات العلوي التفاعلي (مخفي عند الطباعة وحفظ PDF) ─── */
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
    .header-right p { font-size: 11px; color: #4b5563; font-weight: 600; margin-top: 3px; }
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
      body { margin: 0; background: #fff; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
      .no-print, .action-bar { display: none !important; }
      .page { border: none; padding: 0; }
    }
  </style>
</head>
<body>
<div class="action-bar no-print">
  <div class="action-bar-content">
    <div class="action-title">📋 ${esc(title)}</div>
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
    💡 لحفظ كشف الحضور بصيغة PDF: اضغط على زر «تحميل وحفظ كملف PDF» واختر الوجهة (Save as PDF) ثم اضغط حفظ.
  </div>
</div>

${bodyHtml}

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
      var blob = new Blob(["\\uFEFF" + htmlContent], { type: "text/html;charset=utf-8" });
      var url = URL.createObjectURL(blob);
      var a = document.createElement("a");
      a.href = url;
      a.download = "${esc(title)}.html";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch(e) { console.error(e); }
  }
  ${autoPrint ? `setTimeout(function() { saveAsPdf(); }, 400);` : ''}
</script>
</body>
</html>`;
}

/**
 * تنزيل كشف الحضور كملف HTML مستقل قابل للفتح والمطالعة أو الحفظ كـ PDF مباشرة.
 */
export function downloadAttendanceStatement(data: AttendanceStatement, orgName = 'جمعية خواطر أحلى شباب', systemName = 'منظومة أحلى شباب الإدارية'): void {
  const { employee: emp, period } = data;
  const monthName = MONTHS[period.month - 1] ?? '';
  const body = buildStatementBodyHtml(data, orgName, systemName);
  const title = `كشف حضور — ${emp.fullNameAr} — ${monthName} ${period.year}`;
  const html = attendanceDocumentShell(title, body, false);
  const safeName = (emp.employeeCode ? `${emp.employeeCode}-${emp.fullNameAr}` : emp.fullNameAr).replace(/[\\/:*?"<>|]/g, '').trim();
  const filename = `كشف-حضور-${safeName}-${monthName}-${period.year}.html`;

  const blob = new Blob(['\uFEFF' + html], { type: 'text/html;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/**
 * يُنشئ مستند HTML منسّق لكشف الحضور ويفتحه في نافذة جديدة مع تشغيل طباعة تلقائي.
 * مع بديل تنزيل فوري في حال حظر النوافذ المنبثقة من قبل المتصفح.
 */
export function exportAttendancePDF(data: AttendanceStatement, orgName = 'جمعية خواطر أحلى شباب', systemName = 'منظومة أحلى شباب الإدارية') {
  const { employee: emp, period } = data;
  const monthName = MONTHS[period.month - 1] ?? '';
  const body = buildStatementBodyHtml(data, orgName, systemName);
  const title = `كشف حضور — ${emp.fullNameAr} — ${monthName} ${period.year}`;
  const html = attendanceDocumentShell(title, body, true);

  const win = window.open('', '_blank');
  if (!win) {
    downloadAttendanceStatement(data, orgName, systemName);
    return;
  }
  win.document.write(html);
  win.document.close();
}
