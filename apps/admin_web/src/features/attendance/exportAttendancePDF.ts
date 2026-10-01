import type { AttendanceStatement } from '@ahla/shared-contracts';
import { arDays, fmtMinutesCompact, fmtMinutesLong, getDisplayNote, hoursRateParts, rateText, statementRates } from './attendanceShared';

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
 * كشف منفصل لكل موظف أو كشف شامل يضم الجميع. مصمَّم ليُطبع في صفحتين A4
 * بالعرض: الرأس والنسب والملخص وأول الجدول، ثم بقية الأيام مع التوقيعات.
 */
export function buildStatementBodyHtml(data: AttendanceStatement, orgName = 'جمعية خواطر أحلى شباب', systemName = 'منظومة أحلى شباب الإدارية'): string {
  const { employee: emp, period, days, summary: s } = data;
  const rates = statementRates(s);
  const { workedHours, requiredHours } = hoursRateParts(s);
  const monthName = MONTHS[period.month - 1] ?? '';
  const convoyDays = days.filter((d) => (d.status?.includes('قافلة') || d.hasConvoyFundi) && !d.status?.includes('فاندي')).length;
  const fundiDays = days.filter((d) => d.status?.includes('فاندي')).length;
  const cDays = days.length > 0 ? convoyDays : s.convoyFundiDays;
  const fDays = days.length > 0 ? fundiDays : 0;

  const attColor = rates.attendance.available ? pctColor(rates.attendance.pct) : '#64748b';
  const hrsColor = rates.hours.available ? pctColor(rates.hours.pct) : '#64748b';
  // أيام الإجازة (المعتمدة وقيد الاعتماد) والطلبات المعلّقة لا تدخل المقام
  const excludedParts = [
    rates.attendance.excludedLeave > 0 ? `${arDays(rates.attendance.excludedLeave)} إجازة` : '',
    rates.attendance.excludedPending > 0 ? `${arDays(rates.attendance.excludedPending)} بطلبات قيد الاعتماد` : '',
  ].filter(Boolean);
  const leaveNote = excludedParts.length > 0 ? ` (بعد استبعاد ${excludedParts.join(' و')})` : '';
  // وردية واحدة طوال الشهر (الحالة المعتادة) تُعرض مرة في بيانات الموظف بدل تكرارها في كل صف
  const shiftNames = [...new Set(days.map((d) => d.shiftName).filter(Boolean))];
  const uniformShift = shiftNames.length <= 1 ? (shiftNames[0] ?? '—') : null;
  const field = (v: string | null | undefined) => esc(v?.trim() ? v : '—');
  const attBasis = rates.exempt
    ? 'معفى من البصمة — لا تُحتسب له نسبة'
    : rates.attendance.available
      ? `${rates.attendance.present} من ${rates.attendance.due} يوم عمل مستحق${leaveNote}`
      : 'لا توجد أيام عمل مستحقة بعد';
  const hrsBasis = rates.exempt
    ? 'معفى من البصمة'
    : rates.hours.available
      ? `${workedHours.toFixed(1)} من ${requiredHours.toFixed(1)} ساعة مطلوبة في أيام الدوام`
      : 'لا توجد ساعات مطلوبة بعد';

  const metric = (label: string, value: string | number, hint = '', tone: '' | 'warn' | 'good' = '') =>
    `<div class="metric${tone ? ` ${tone}` : ''}"><div class="label">${label}</div><div class="value">${value}</div>${hint ? `<div class="hint">${hint}</div>` : ''}</div>`;

  const dayRows = days
    .map((d) => {
      // ما تقوله خانة الحالة لا يُكرَّر في الملاحظات («غائب دون إذن» ثم «غائب»…)
      const status = d.status ?? '';
      const missingOutStatus = status.includes('لم يسجل الانصراف');
      const tags: string[] = [];
      const tag = (label: string, shownBy = label) => {
        if (!status.includes(shownBy)) tags.push(label);
      };
      if (d.isAbsent) tag('غائب');
      if (d.isOfficialHoliday) tag('عطلة رسمية');
      if (d.hasLeave) tag('إجازة');
      if (d.hasMission) tag('مأمورية');
      if (d.hasLatePermit) tags.push('إذن حضور');
      if (d.hasEarlyPermit) tags.push('إذن انصراف');
      if (!d.hasLatePermit && !d.hasEarlyPermit && d.hasPermit) tags.push('إذن');
      if (d.hasConvoyFundi) {
        if (status.includes('فاندي')) tag('فاندي (ترفيهي)', 'فاندي');
        else tag('قافلة مساعدات', 'قافلة');
      }
      if (d.missingCheckIn) tags.push('نقص حضور');
      if (d.missingCheckOut && !missingOutStatus) tags.push('نقص انصراف');
      if (d.isOpenShift) tags.push('بانتظار الانصراف');
      if (d.isFuture) tags.push('قادم');
      if (d.penalties > 0) tags.push(`جزاء: ${d.penalties}`);

      const isRest = d.status === 'راحة أسبوعية' || d.status === 'عطلة رسمية';
      const isWarn = WARN_STATUSES.has(d.status) || missingOutStatus;
      const rowClass = d.isFuture ? 'future' : isRest ? 'rest' : isWarn ? 'warn' : d.isOpenShift ? 'open' : '';

      const displayNote = getDisplayNote(d.correctionNote);
      const noteParts = [...tags];
      if (displayNote) noteParts.push(displayNote);

      return `<tr${rowClass ? ` class="${rowClass}"` : ''}>
      <td class="num ltr">${esc(d.date)}</td>
      <td>${esc(d.dayNameAr)}</td>
      <td class="num ltr">${esc(fmtTime(d.checkIn))}</td>
      <td class="num ltr">${esc(fmtTime(d.checkOut))}</td>
      ${uniformShift === null ? `<td class="shift">${esc(d.shiftName) || '—'}</td>` : ''}
      <td class="num">${d.workHours ? d.workHours.toFixed(1) : '—'}</td>
      <td class="num${d.lateMinutes > 0 ? ' late' : ''}">${d.lateMinutes ? fmtMinutesCompact(d.lateMinutes) : '—'}</td>
      <td class="num${d.earlyLeaveMinutes > 0 ? ' late' : ''}">${d.earlyLeaveMinutes ? fmtMinutesCompact(d.earlyLeaveMinutes) : '—'}</td>
      <td class="num${d.overtimeMinutes > 0 ? ' good' : ''}">${d.overtimeMinutes ? fmtMinutesCompact(d.overtimeMinutes) : '—'}</td>
      <td class="status">${esc(d.status)}</td>
      <td class="note">${noteParts.length > 0 ? esc(noteParts.join('، ')) : '—'}</td>
    </tr>`;
    })
    .join('\n');

  const extras = [
    s.upcomingDays > 0 ? `<div class="stat-item"><span class="s-label">أيام قادمة:</span><span class="s-value">${s.upcomingDays}</span></div>` : '',
    s.openShiftDays > 0 ? `<div class="stat-item"><span class="s-label">وردية مفتوحة اليوم:</span><span class="s-value">${s.openShiftDays}</span></div>` : '',
  ].join('');

  return `<div class="page">
  <div class="header">
    <div class="header-right">
      <h1>كشف الحضور والانصراف الشهري</h1>
      <p>${monthName} ${period.year} — من <span class="ltr-inline">${esc(period.startDate)}</span> إلى <span class="ltr-inline">${esc(period.endDate)}</span> (${s.totalDays} يومًا)</p>
    </div>
    <div class="header-left">
      <div class="org">${esc(orgName)}</div>
      <div class="sub">منظومة الإدارة المؤسسية</div>
    </div>
  </div>

  <div class="emp-grid">
    <div class="emp-field"><label>الاسم</label><span>${field(emp.fullNameAr)}</span></div>
    <div class="emp-field"><label>الكود</label><span class="ltr-inline">${field(emp.employeeCode)}</span></div>
    <div class="emp-field"><label>الإدارة</label><span>${field(emp.department)}</span></div>
    <div class="emp-field"><label>المسمى الوظيفي</label><span>${field(emp.jobTitle)}</span></div>
    <div class="emp-field"><label>الفرع</label><span>${field(emp.branch)}</span></div>
    <div class="emp-field"><label>المدير المباشر</label><span>${field(emp.manager)}</span></div>
    <div class="emp-field"><label>تاريخ التعيين</label><span class="ltr-inline">${field(emp.hireDate)}</span></div>
    ${
      uniformShift !== null
        ? `<div class="emp-field"><label>الوردية</label><span>${field(uniformShift)}</span></div>`
        : `<div class="emp-field"><label>الفترة</label><span>${monthName} ${period.year}</span></div>`
    }
  </div>

  <div class="rates">
    <div class="rate-card">
      <div class="pct" style="color:${attColor}">${rateText(rates.attendance, rates.exempt)}</div>
      <div><div class="rate-lbl">نسبة الحضور</div><div class="rate-basis">${attBasis}</div></div>
    </div>
    <div class="rate-card">
      <div class="pct" style="color:${hrsColor}">${rateText(rates.hours, rates.exempt)}</div>
      <div><div class="rate-lbl">التزام الساعات</div><div class="rate-basis">${hrsBasis}</div></div>
    </div>
  </div>

  <div class="summary-grid">
    ${metric('أيام محتسبة حضورًا', rates.attendance.present, rates.exempt ? 'معفى من البصمة' : `من ${rates.attendance.due} يوم مستحق`)}
    ${metric('أيام الغياب', s.absentDays, 'دون إذن أو عذر', s.absentDays > 0 ? 'warn' : '')}
    ${metric('أيام التأخير', s.lateDays, s.lateDays > 0 ? fmtMinutesLong(s.totalLateMinutes) : 'بعد فترة السماح 15 د', s.lateDays > 0 ? 'warn' : '')}
    ${metric('خروج مبكر', s.earlyLeaveDays, s.earlyLeaveDays > 0 ? fmtMinutesLong(s.totalEarlyLeaveMinutes) : 'دون إذن انصراف', s.earlyLeaveDays > 0 ? 'warn' : '')}
    ${metric('نسيان انصراف', s.missingCheckOutCount, 'أيام بلا بصمة انصراف', s.missingCheckOutCount > 0 ? 'warn' : '')}
    ${metric('نسيان حضور', s.missingCheckInCount, 'أيام بلا بصمة حضور', s.missingCheckInCount > 0 ? 'warn' : '')}
    ${metric('الإجازات', s.leaveDays)}
    ${metric('المأموريات', s.missionDays)}
    ${metric('القوافل', cDays)}
    ${metric('الفاندي', fDays)}
    ${metric('الأذونات', s.permitCount)}
    ${metric('ساعات إضافية', s.totalOvertimeMinutes > 0 ? fmtMinutesCompact(s.totalOvertimeMinutes) : '0', '', s.totalOvertimeMinutes > 0 ? 'good' : '')}
  </div>

  <div class="stats-bar">
    <div class="stat-item"><span class="s-label">ساعات العمل الفعلية:</span><span class="s-value">${s.totalWorkHours.toFixed(1)} ساعة</span></div>
    <div class="stat-item"><span class="s-label">عطل رسمية:</span><span class="s-value">${s.holidayDays}</span></div>
    <div class="stat-item"><span class="s-label">أيام راحة:</span><span class="s-value">${s.restDays}</span></div>
    ${extras}
  </div>

  <table>
    <thead>
      <tr>
        <th>التاريخ</th><th>اليوم</th><th>الحضور</th><th>الانصراف</th>
        ${uniformShift === null ? '<th>الوردية</th>' : ''}<th>ساعات فعلية</th><th>التأخير</th>
        <th>خروج مبكر</th><th>إضافي</th><th>الحالة</th><th>ملاحظات</th>
      </tr>
    </thead>
    <tbody>
      ${dayRows}
    </tbody>
  </table>

  <div class="closing">
    <div class="footer">
      <span>تم الإنشاء بواسطة ${esc(systemName)}</span>
      <span>تاريخ الطباعة: ${new Date().toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' })}</span>
    </div>
    <div class="signatures">
      <div class="sig-box">الموظف</div>
      <div class="sig-box">المدير المباشر</div>
      <div class="sig-box">الموارد البشرية</div>
    </div>
  </div>
</div>`;
}

/** أنماط مستند الكشف — مشتركة بين ملف الطباعة وتوليد ملفات PDF (statementPdf). */
export const STATEMENT_DOCUMENT_CSS = `
    @page {
      size: A4 landscape;
      margin: 8mm 8mm;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Cairo', 'Segoe UI', 'Tahoma', 'Arial', sans-serif;
      direction: rtl;
      color: #111827;
      font-size: 10.5px;
      line-height: 1.45;
      -webkit-print-color-adjust: exact !important;
      print-color-adjust: exact !important;
      margin: 16px;
      background: #f8fafc;
    }
    .page { max-width: 1100px; margin: 0 auto; background: #fff; padding: 20px; border-radius: 8px; border: 1px solid #e5e7eb; }
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
      padding-bottom: 8px;
      margin-bottom: 10px;
    }
    .header-right h1 { font-size: 17px; font-weight: 900; color: #1e40af; }
    .header-right p { font-size: 10.5px; color: #4b5563; font-weight: 600; margin-top: 2px; }
    .header-left { text-align: left; }
    .header-left .org { font-size: 13px; font-weight: 900; color: #1e40af; }
    .header-left .sub { font-size: 9px; color: #6b7280; }
    .ltr-inline { direction: ltr; unicode-bidi: isolate; display: inline-block; }

    /* ─── بيانات الموظف ─── */
    .emp-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 4px 10px;
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      padding: 7px 12px;
      margin-bottom: 8px;
    }
    .emp-field label { display: block; font-size: 8.5px; color: #6b7280; font-weight: 700; }
    .emp-field span { font-size: 11.5px; font-weight: 800; }
    .emp-field > span:not(.ltr-inline) { display: block; }

    /* ─── النسب ─── */
    .rates { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 8px; }
    .rate-card {
      display: flex;
      align-items: center;
      gap: 12px;
      background: #f0f9ff;
      border: 1px solid #bfdbfe;
      border-radius: 8px;
      padding: 6px 14px;
    }
    .rate-card .pct { font-size: 22px; font-weight: 900; min-width: 70px; text-align: center; }
    .rate-card .rate-lbl { font-size: 11px; font-weight: 800; color: #1e3a5f; }
    .rate-card .rate-basis { font-size: 9px; color: #6b7280; }

    /* ─── الملخص ─── */
    .summary-grid {
      display: grid;
      grid-template-columns: repeat(6, 1fr);
      gap: 5px;
      margin-bottom: 8px;
    }
    .metric {
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 6px;
      padding: 4px 6px;
      text-align: center;
    }
    .metric .label { font-size: 8.5px; color: #6b7280; font-weight: 700; }
    .metric .value { font-size: 15px; font-weight: 900; color: #111827; line-height: 1.35; }
    .metric .hint { font-size: 8px; color: #9ca3af; }
    .metric.warn .value { color: #dc2626; }
    .metric.good .value { color: #059669; }

    /* ─── شريط الإحصائيات السريعة ─── */
    .stats-bar {
      display: flex;
      flex-wrap: wrap;
      gap: 4px 14px;
      background: #fefce8;
      border: 1px solid #fde68a;
      border-radius: 6px;
      padding: 4px 12px;
      margin-bottom: 8px;
      font-size: 9.5px;
    }
    .stat-item { display: flex; gap: 4px; align-items: center; }
    .stat-item .s-label { color: #6b7280; }
    .stat-item .s-value { font-weight: 800; }

    /* ─── الجدول ─── */
    table { width: 100%; border-collapse: collapse; font-size: 9.5px; }
    thead { display: table-header-group; }
    thead th {
      background: #1e3a5f;
      color: white;
      padding: 5px 6px;
      text-align: center;
      font-weight: 800;
      font-size: 9px;
    }
    tbody td { border-bottom: 1px solid #e5e7eb; padding: 3.5px 6px; text-align: center; }
    tbody tr { break-inside: avoid; page-break-inside: avoid; }
    tbody tr:nth-child(even) { background: #fafafa; }
    tbody tr.rest { background: #f0f9ff; }
    tbody tr.open { background: #f0f9ff; }
    tbody tr.warn { background: #fef2f2; }
    tbody tr.future { background: #f8fafc; color: #94a3b8; }
    td.num { font-variant-numeric: tabular-nums; }
    td.ltr { direction: ltr; }
    td.late { color: #d97706; font-weight: 700; }
    td.good { color: #059669; font-weight: 700; }
    td.shift { font-size: 8.5px; color: #4b5563; }
    td.status { font-weight: 700; }
    tr.rest td.status { color: #0369a1; }
    tr.warn td.status { color: #dc2626; }
    td.note { font-size: 8.5px; color: #4b5563; }

    /* ─── التذييل والتوقيعات: كتلة واحدة لا تنقسم بين صفحتين ─── */
    .closing { break-inside: avoid; page-break-inside: avoid; }
    .footer {
      margin-top: 10px;
      padding-top: 6px;
      border-top: 2px solid #e2e8f0;
      display: flex;
      justify-content: space-between;
      font-size: 8.5px;
      color: #9ca3af;
    }
    .signatures {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 20px;
      margin-top: 12px;
    }
    .sig-box {
      text-align: center;
      padding-top: 26px;
      border-top: 1px solid #d1d5db;
      font-size: 10px;
      color: #6b7280;
    }

    @media print {
      body { margin: 0; background: #fff; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
      .no-print, .action-bar { display: none !important; }
      .page { border: none; padding: 0; border-radius: 0; max-width: none; }
      .page-break:last-child { page-break-after: auto; break-after: auto; }
    }
`;

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
${STATEMENT_DOCUMENT_CSS}
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
  ${autoPrint ? `setTimeout(function() { saveAsPdf(); }, 400);` : ''}
</script>
</body>
</html>`;
}

/**
 * تصدير كشف الحضور كملف PDF حقيقي مباشرة.
 */
export function downloadAttendanceStatement(data: AttendanceStatement, orgName = 'جمعية خواطر أحلى شباب', systemName = 'منظومة أحلى شباب الإدارية'): void {
  void exportAttendancePDF(data, orgName, systemName);
}

/** اسم ملف PDF لكشف موظف (عربي آمن لأنظمة الملفات). */
export function statementPdfFileName(data: AttendanceStatement): string {
  const { employee: emp, period } = data;
  const monthName = MONTHS[period.month - 1] ?? '';
  const safeName = (emp.employeeCode ? `${emp.employeeCode}-${emp.fullNameAr}` : emp.fullNameAr).replace(/[\\/:*?"<>|]/g, '').trim();
  return `كشف-حضور-${safeName}-${monthName}-${period.year}.pdf`;
}

/**
 * تصدير كشف موظف كملف PDF حقيقي مباشرة (ملف .pdf دون فتح نافذة HTML أو تنزيل ملفات HTML).
 */
export async function exportAttendancePDF(data: AttendanceStatement, orgName = 'جمعية خواطر أحلى شباب', systemName = 'منظومة أحلى شباب الإدارية'): Promise<void> {
  const { employee: emp, period } = data;
  const monthName = MONTHS[period.month - 1] ?? '';
  const title = `كشف حضور — ${emp.fullNameAr} — ${monthName} ${period.year}`;
  const { statementsToPdfs, downloadBlob } = await import('./statementPdf');
  const { files } = await statementsToPdfs([{ statement: data, title }], title, orgName, systemName);
  if (files.length > 0) {
    downloadBlob(files[0].blob, statementPdfFileName(data));
  }
}
