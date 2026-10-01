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
/**
 * بناء محتوى جسم كشف الحضور لموظف واحد (داخل <body>) — يُعاد استخدامه لبناء
 * كشف منفصل لكل موظف أو كشف شامل يضم الجميع.
 * مصمَّم بنظام الحاويات المتناسقة (.pdf-page) بقياس A4 عرضي بدقة هندسية:
 *  • الأيام <= 15: صفحة واحدة متكاملة ومنسقة تضم البيانات والجدول والتوقيعات.
 *  • الأيام > 15: صفحتان متوازنتان (الصفحة 1: الأيام 1-15 والنسب والملخص؛ الصفحة 2: بقية الأيام مع الإجمالي العام والتوقيعات والاعتماد الرسمي).
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

  const renderRow = (d: (typeof days)[0]) => {
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
  };

  const extras = [
    s.upcomingDays > 0 ? `<div class="stat-item"><span class="s-label">أيام قادمة:</span><span class="s-value">${s.upcomingDays}</span></div>` : '',
    s.openShiftDays > 0 ? `<div class="stat-item"><span class="s-label">وردية مفتوحة اليوم:</span><span class="s-value">${s.openShiftDays}</span></div>` : '',
  ].join('');

  const tableHead = `<thead>
    <tr>
      <th style="width:75px">التاريخ</th>
      <th style="width:65px">اليوم</th>
      <th style="width:70px">الحضور</th>
      <th style="width:70px">الانصراف</th>
      ${uniformShift === null ? '<th style="width:110px">الوردية</th>' : ''}
      <th style="width:65px">ساعات فعلية</th>
      <th style="width:60px">التأخير</th>
      <th style="width:60px">خروج مبكر</th>
      <th style="width:55px">إضافي</th>
      <th style="width:125px">الحالة</th>
      <th>ملاحظات</th>
    </tr>
  </thead>`;

  const totalCols = uniformShift === null ? 5 : 4;
  const tableTotalRow = `<tr class="total-row">
    <td colspan="${totalCols}" class="total-label">الإجمالي العام للشهر الكامل (${s.totalDays} يومًا):</td>
    <td class="num total-val">${s.totalWorkHours.toFixed(1)} س</td>
    <td class="num total-val${s.totalLateMinutes > 0 ? ' late' : ''}">${s.totalLateMinutes > 0 ? fmtMinutesCompact(s.totalLateMinutes) : '—'}</td>
    <td class="num total-val${s.totalEarlyLeaveMinutes > 0 ? ' late' : ''}">${s.totalEarlyLeaveMinutes > 0 ? fmtMinutesCompact(s.totalEarlyLeaveMinutes) : '—'}</td>
    <td class="num total-val${s.totalOvertimeMinutes > 0 ? ' good' : ''}">${s.totalOvertimeMinutes > 0 ? fmtMinutesCompact(s.totalOvertimeMinutes) : '—'}</td>
    <td colspan="2" class="total-summary">
      نسبة الحضور: <b>${rateText(rates.attendance, rates.exempt)}</b> | التزام الساعات: <b>${rateText(rates.hours, rates.exempt)}</b>
    </td>
  </tr>`;

  const signaturesHtml = `<div class="closing">
    <div class="signatures">
      <div class="sig-box">
        <div class="sig-title">إقرار الموظف</div>
        <div class="sig-desc">أقر بصحة بيانات الحضور والانصراف المسجلة</div>
        <div class="sig-line">التوقيع: ............................</div>
        <div class="sig-date">التاريخ: ..... / ..... / 202... م</div>
      </div>
      <div class="sig-box">
        <div class="sig-title">الموارد البشرية</div>
        <div class="sig-desc">تمت المراجعة والتدقيق والمطابقة مع السجلات</div>
        <div class="sig-line">التوقيع: ............................</div>
        <div class="sig-date">التاريخ: ..... / ..... / 202... م</div>
      </div>
      <div class="sig-box">
        <div class="sig-title">المدير المباشر</div>
        <div class="sig-desc">تم الاطلاع والاعتماد الفني وفق المهام وساعات العمل</div>
        <div class="sig-line">التوقيع: ............................</div>
        <div class="sig-date">التاريخ: ..... / ..... / 202... م</div>
      </div>
      <div class="sig-box">
        <div class="sig-title">الاعتماد والختم الرسمي</div>
        <div class="seal-box">خاتم الجمعية الرسمي</div>
        <div class="sig-line">الاعتماد: ............................</div>
      </div>
    </div>
  </div>`;

  const printDateStr = new Date().toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' });

  // إذا كانت الأيام قليلة (15 يوماً أو أقل)، تُعرض كاملة في صفحة واحدة متناسقة
  if (days.length <= 15) {
    const dayRows = days.map(renderRow).join('\n');
    return `<div class="pdf-page page-single">
  <div>
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
      ${tableHead}
      <tbody>
        ${dayRows}
      </tbody>
      <tfoot>
        ${tableTotalRow}
      </tfoot>
    </table>
  </div>

  <div>
    ${signaturesHtml}
    <div class="footer">
      <span>تم الإنشاء بواسطة ${esc(systemName)}</span>
      <span class="page-indicator">صفحة 1 من 1</span>
      <span>تاريخ الطباعة: ${printDateStr}</span>
    </div>
  </div>
</div>`;
  }

  // الشهر الكامل (أكثر من 15 يومًا): يُقسّم هندسيًا إلى صفحتين A4 متناسقتين
  const daysP1 = days.slice(0, 15);
  const daysP2 = days.slice(15);
  const rowsP1 = daysP1.map(renderRow).join('\n');
  const rowsP2 = daysP2.map(renderRow).join('\n');

  return `<div class="pdf-page page-1">
  <div>
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
      ${tableHead}
      <tbody>
        ${rowsP1}
      </tbody>
    </table>
  </div>

  <div class="footer">
    <span>📌 النصف الأول من الشهر (الأيام 1 – 15) — يتبع النصف الثاني والاعتمادات في الصفحة التالية</span>
    <span class="page-indicator">صفحة 1 من 2</span>
    <span>تاريخ الطباعة: ${printDateStr}</span>
  </div>
</div>

<div class="pdf-page page-2">
  <div>
    <div class="header">
      <div class="header-right">
        <h1>تابع كشف الحضور والانصراف — النصف الثاني (الأيام 16 إلى نهاية الشهر)</h1>
        <p>الموظف: <b>${field(emp.fullNameAr)}</b> (${field(emp.employeeCode)}) — ${field(emp.department)} — ${monthName} ${period.year}</p>
      </div>
      <div class="header-left">
        <div class="org">${esc(orgName)}</div>
        <div class="sub">منظومة الإدارة المؤسسية</div>
      </div>
    </div>

    <table>
      ${tableHead}
      <tbody>
        ${rowsP2}
      </tbody>
      <tfoot>
        ${tableTotalRow}
      </tfoot>
    </table>
  </div>

  <div>
    ${signaturesHtml}
    <div class="footer">
      <span>تم الإنشاء بواسطة ${esc(systemName)}</span>
      <span class="page-indicator">صفحة 2 من 2</span>
      <span>تاريخ الطباعة: ${printDateStr}</span>
    </div>
  </div>
</div>`;
}

/** أنماط مستند الكشف — مشتركة بين ملف الطباعة وتوليد ملفات PDF (statementPdf). */
export const STATEMENT_DOCUMENT_CSS = `
    @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;500;600;700;800;900&display=swap');

    @page {
      size: A4 landscape;
      margin: 8mm 8mm;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Cairo', 'Segoe UI', Tahoma, Arial, sans-serif;
      direction: rtl;
      color: #0f172a;
      font-size: 10px;
      line-height: 1.4;
      -webkit-print-color-adjust: exact !important;
      print-color-adjust: exact !important;
      margin: 0;
      padding: 12px 0;
      background: #f1f5f9;
    }

    /* ─── حاويات الصفحات المنفصلة الثابتة A4 Landscape ─── */
    .pdf-page {
      width: 1062px;
      height: 733px;
      max-height: 733px;
      box-sizing: border-box;
      overflow: hidden;
      background: #ffffff;
      padding: 12px 16px;
      margin: 0 auto 16px auto;
      border: 1px solid #e2e8f0;
      border-radius: 4px;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      page-break-after: always;
      break-after: page;
    }
    .page-break { page-break-after: always; break-after: page; }

    /* ─── شريط الإجراءات العلوي التفاعلي (مخفي عند الطباعة وحفظ PDF) ─── */
    .action-bar {
      max-width: 1062px;
      margin: 0 auto 14px;
      background: #0f172a;
      color: #f8fafc;
      border-radius: 8px;
      padding: 10px 16px;
      box-shadow: 0 4px 12px rgba(15, 23, 42, 0.25);
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
      padding: 6px 12px; font-size: 11px; font-weight: 700;
      font-family: inherit; border-radius: 6px; cursor: pointer; border: none;
      transition: all 0.2s;
    }
    .btn-act-pdf { background: #10b981; color: white; }
    .btn-act-pdf:hover { background: #059669; }
    .btn-act-print { background: #2563eb; color: white; }
    .btn-act-print:hover { background: #1d4ed8; }
    .btn-act-close { background: transparent; color: #94a3b8; border: 1px solid #334155; }
    .btn-act-close:hover { color: #f87171; border-color: #ef4444; }
    .action-tip {
      margin-top: 6px; padding-top: 6px; border-top: 1px solid #1e293b;
      font-size: 9.5px; color: #cbd5e1;
    }

    /* ─── الرأس ─── */
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      border-bottom: 2px solid #1e3a8a;
      padding-bottom: 4px;
      margin-bottom: 6px;
    }
    .header-right h1 { font-size: 14.5px; font-weight: 900; color: #1e3a8a; margin-bottom: 1px; }
    .header-right p { font-size: 9px; color: #475569; font-weight: 600; }
    .header-left { text-align: left; }
    .header-left .org { font-size: 12px; font-weight: 900; color: #1e3a8a; }
    .header-left .sub { font-size: 8px; color: #64748b; }
    .ltr-inline { direction: ltr; unicode-bidi: isolate; display: inline-block; }

    /* ─── بيانات الموظف ─── */
    .emp-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 3px 8px;
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 6px;
      padding: 5px 10px;
      margin-bottom: 6px;
    }
    .emp-field label { display: block; font-size: 8px; color: #64748b; font-weight: 700; }
    .emp-field span { font-size: 10px; font-weight: 800; color: #0f172a; }
    .emp-field > span:not(.ltr-inline) { display: block; }

    /* ─── النسب ─── */
    .rates { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 6px; }
    .rate-card {
      display: flex;
      align-items: center;
      gap: 10px;
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 6px;
      padding: 4px 10px;
    }
    .rate-card .pct { font-size: 18px; font-weight: 900; min-width: 65px; text-align: center; }
    .rate-card .rate-lbl { font-size: 9.5px; font-weight: 800; color: #1e3a5f; }
    .rate-card .rate-basis { font-size: 8px; color: #64748b; }

    /* ─── الملخص ─── */
    .summary-grid {
      display: grid;
      grid-template-columns: repeat(6, 1fr);
      gap: 4px;
      margin-bottom: 6px;
    }
    .metric {
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 5px;
      padding: 3px 4px;
      text-align: center;
    }
    .metric .label { font-size: 7.5px; color: #64748b; font-weight: 700; }
    .metric .value { font-size: 13px; font-weight: 900; color: #0f172a; line-height: 1.25; }
    .metric .hint { font-size: 7px; color: #94a3b8; }
    .metric.warn .value { color: #dc2626; }
    .metric.good .value { color: #059669; }

    /* ─── شريط الإحصائيات السريعة ─── */
    .stats-bar {
      display: flex;
      flex-wrap: wrap;
      gap: 2px 10px;
      background: #fefce8;
      border: 1px solid #fef08a;
      border-radius: 5px;
      padding: 3px 8px;
      margin-bottom: 6px;
      font-size: 8.5px;
    }
    .stat-item { display: flex; gap: 4px; align-items: center; }
    .stat-item .s-label { color: #64748b; }
    .stat-item .s-value { font-weight: 800; color: #0f172a; }

    /* ─── الجدول ─── */
    table { width: 100%; border-collapse: collapse; font-size: 8.5px; }
    thead th {
      background: #1e3a8a;
      color: white;
      padding: 3px 4px;
      text-align: center;
      font-weight: 800;
      font-size: 8.5px;
      border: 1px solid #1e3a8a;
    }
    tbody td { border: 1px solid #e2e8f0; padding: 2px 4px; text-align: center; }
    tbody tr:nth-child(even) { background: #f8fafc; }
    tbody tr.rest { background: #f0f9ff; }
    tbody tr.open { background: #f0f9ff; }
    tbody tr.warn { background: #fef2f2; }
    tbody tr.future { background: #f8fafc; color: #94a3b8; }
    td.num { font-variant-numeric: tabular-nums; }
    td.ltr { direction: ltr; }
    td.late { color: #d97706; font-weight: 700; }
    td.good { color: #059669; font-weight: 700; }
    td.shift { font-size: 7.5px; color: #4b5563; }
    td.status { font-weight: 700; }
    tr.rest td.status { color: #0369a1; }
    tr.warn td.status { color: #dc2626; }
    td.note { font-size: 7.5px; color: #4b5563; }

    tfoot tr.total-row {
      background: #eff6ff;
      border-top: 2px solid #1e3a8a;
      font-weight: 800;
    }
    tfoot tr.total-row td {
      padding: 3px 4px;
      border: 1px solid #bfdbfe;
    }
    .total-label { text-align: right; color: #1e3a8a; font-size: 8.5px; }
    .total-val { font-size: 9px; color: #1e3a8a; font-weight: 900; }
    .total-summary { font-size: 8px; color: #1e40af; text-align: center; }

    /* ─── التوقيعات والاعتماد الرسمي ─── */
    .signatures {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 8px;
      margin-top: 4px;
    }
    .sig-box {
      border: 1px solid #cbd5e1;
      background: #f8fafc;
      border-radius: 5px;
      padding: 4px 6px;
      text-align: center;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      min-height: 58px;
    }
    .sig-title { font-size: 8.5px; font-weight: 800; color: #1e3a8a; margin-bottom: 1px; }
    .sig-desc { font-size: 7px; color: #64748b; margin-bottom: 4px; }
    .sig-line { font-size: 7.5px; color: #94a3b8; border-bottom: 1px dashed #cbd5e1; padding-bottom: 2px; margin-top: auto; }
    .sig-date { font-size: 7px; color: #94a3b8; margin-top: 1px; }
    .seal-box {
      border: 1px dashed #94a3b8;
      border-radius: 4px;
      padding: 2px;
      font-size: 7.5px;
      color: #94a3b8;
      margin: 1px auto;
      width: 75%;
    }

    .footer {
      border-top: 1px solid #e2e8f0;
      padding-top: 3px;
      margin-top: 3px;
      display: flex;
      justify-content: space-between;
      font-size: 7.5px;
      color: #9ca3af;
    }
    .page-indicator { font-weight: 700; color: #475569; }

    @media print {
      body { margin: 0; padding: 0; background: #fff; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
      .no-print, .action-bar { display: none !important; }
      .pdf-page {
        border: none !important;
        box-shadow: none !important;
        margin: 0 !important;
        width: 100% !important;
        height: auto !important;
        max-height: none !important;
        padding: 0 !important;
        page-break-after: always !important;
        break-after: page !important;
      }
      .pdf-page:last-child { page-break-after: auto !important; break-after: auto !important; }
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
