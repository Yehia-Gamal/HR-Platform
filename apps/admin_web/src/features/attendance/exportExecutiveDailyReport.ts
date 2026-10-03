import type { ExecutiveDailyReportDetail } from '@ahla/shared-contracts';
import { fmtMinutesCompact } from './attendanceShared';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const WEEKDAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

const CAIRO_HM = new Intl.DateTimeFormat('en-GB', { timeZone: 'Africa/Cairo', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });

/** وقت بصيغة 12 ساعة: يقبل «HH:MM» أو تاريخًا كاملًا (timestamptz) فيعرضه بتوقيت القاهرة. */
export function fmtTime12(value: string | null | undefined): string {
  if (!value) return '—';
  let t = value;
  if (/^\d{4}-\d{2}-\d{2}T/.test(t)) {
    const d = new Date(t);
    if (!Number.isNaN(d.getTime())) t = CAIRO_HM.format(d);
  }
  const m = /^(\d{1,2}):(\d{2})/.exec(t);
  if (!m) return t;
  let h = parseInt(m[1], 10);
  const min = m[2];
  if (Number.isNaN(h)) return t;
  const period = h < 12 ? 'ص' : 'م';
  h = h % 12 === 0 ? 12 : h % 12;
  return `${String(h).padStart(2, '0')}:${min} ${period}`;
}

function pctColor(pct: number): string {
  return pct >= 90 ? '#059669' : pct >= 75 ? '#f59e0b' : '#dc2626';
}

function esc(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function statusLabel(status: string | null): string {
  const map: Record<string, string> = {
    present: 'حاضر',
    late: 'متأخر',
    absent: 'غائب',
    on_leave: 'إجازة',
    holiday: 'عطلة',
    weekend: 'عطلة الأسبوع',
    partial: 'جزئي',
    pending: 'قيد الانتظار',
    on_mission: 'مأمورية',
    missing_checkout: 'بصمة بلا انصراف',
    not_yet: 'لم يحضر بعد',
    assignment: 'مأمورية / قافلة',
    checked_out: 'انصرف',
    left_early: 'انصرف مبكرًا',
    exempt: 'معفى من البصمة',
  };
  if (!status) return '—';
  return map[status] ?? status;
}

function statusClass(status: string | null): string {
  if (status === 'present' || status === 'checked_out') return 'status-present';
  if (status === 'late' || status === 'left_early') return 'status-late';
  if (status === 'absent') return 'status-absent';
  if (status === 'missing_checkout') return 'status-missing';
  if (status === 'on_leave') return 'status-leave';
  if (status === 'on_mission' || status === 'assignment') return 'status-mission';
  return 'status-neutral';
}

export function buildExecutiveDailyReportHtml(
  data: ExecutiveDailyReportDetail,
  orgName = 'جمعية خواطر أحلى شباب',
  systemName = 'منظومة أحلى شباب الإدارية',
): string {
  const { dateIso, summary, employees, missions, convoys, leaves, locationRequests, disputes } = data;
  const missionsArr = missions ?? [];
  const convoysArr = convoys ?? [];
  const [y, m, d] = dateIso.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  const dayName = WEEKDAYS[dt.getUTCDay()] ?? '';
  const monthName = MONTHS[m - 1] ?? '';

  // ========== ملخص تنفيذي ==========
  // من أرقام الخادم (get_v10_executive_daily_report — نفس مصدر لوحة الموارد البشرية)،
  // لا من عدّ قائمة الموظفين: كانت القائمة تصل فارغة فيُطبع الحضور 0 والنسبة 0%.
  const totalEmployees = summary.employees.active;
  const requiredToday = summary.employees.requiredToday;
  const presentCount = summary.attendance.present;
  const lateCount = summary.attendance.late;
  const absentCount = summary.attendance.absent;
  const notYetCount = summary.attendance.notYet;
  const leaveCount = summary.workStatus.approvedLeave;
  const fieldCount = summary.workStatus.missions + summary.workStatus.convoys + summary.workStatus.fundraising;
  const onTimeCount = Math.max(0, presentCount - lateCount);

  const attendancePct = requiredToday > 0 ? Math.min(100, (presentCount / requiredToday) * 100) : null;
  const punctualityPct = presentCount > 0 ? (onTimeCount / presentCount) * 100 : null;
  const pctText = (v: number | null) => (v === null ? '—' : `${v.toFixed(1)}%`);
  const pctTone = (v: number | null) => (v === null ? '#64748b' : pctColor(v));

  // ========== جداول تفصيلية ==========
  // الغياب والتأخير أولًا ليراهم المدير التنفيذي مباشرة، ثم بقية الحالات
  const STATUS_ORDER = [
    'absent',
    'late',
    'left_early',
    'not_yet',
    'present',
    'checked_out',
    'assignment',
    'on_mission',
    'on_leave',
    'weekend',
    'holiday',
    'exempt',
  ];
  const rank = (st: string | null) => {
    const i = STATUS_ORDER.indexOf(st ?? '');
    return i === -1 ? STATUS_ORDER.length : i;
  };
  const employeeRows = [...employees]
    .sort((a, b) => rank(a.status) - rank(b.status) || a.employeeName.localeCompare(b.employeeName, 'ar'))
    .map(
      (emp) => `
    <tr class="${statusClass(emp.status)}">
      <td style="padding:6px 8px;text-align:center;direction:ltr">${esc(emp.employeeCode ?? '—')}</td>
      <td style="padding:6px 8px">${esc(emp.employeeName)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(emp.departmentName ?? '—')}</td>
      <td style="padding:6px 8px;text-align:center"><span class="status-badge ${statusClass(emp.status)}">${esc(statusLabel(emp.status))}</span></td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums">${esc(fmtTime12(emp.firstCheckIn))}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums">${esc(fmtTime12(emp.lastCheckOut))}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums">${emp.lateMinutes ? fmtMinutesCompact(emp.lateMinutes) : '—'}</td>
    </tr>
  `,
    )
    .join('');

  const missionRows = missionsArr.length
    ? missionsArr
        .map(
          (m) => `
    <tr>
      <td style="padding:6px 8px;text-align:center">${esc(m.employeeCode ?? '—')}</td>
      <td style="padding:6px 8px">${esc(m.employeeName)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(m.missionType)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(m.destination)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(fmtTime12(m.startAt))}</td>
      <td style="padding:6px 8px;text-align:center">${esc(fmtTime12(m.endAt))}</td>
      <td style="padding:6px 8px;text-align:center"><span class="status-badge ${statusClass(m.status)}">${esc(statusLabel(m.status))}</span></td>
      <td style="padding:6px 8px">${esc(m.purpose ?? '—')}</td>
    </tr>
  `,
        )
        .join('')
    : '<tr><td colspan="8" style="padding:16px;text-align:center;color:#6b7280">لا توجد مأموريات لهذا اليوم</td></tr>';

  const convoyRows = convoysArr.length
    ? convoysArr
        .map(
          (c) => `
    <tr>
      <td style="padding:6px 8px;text-align:center">${esc(c.code)}</td>
      <td style="padding:6px 8px">${esc(c.title)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(c.type)}</td>
      <td style="padding:6px 8px;text-align:center">${c.participantsCount} مشارك</td>
      <td style="padding:6px 8px;text-align:center">${esc(fmtTime12(c.startAt))}</td>
      <td style="padding:6px 8px;text-align:center">${esc(fmtTime12(c.endAt))}</td>
      <td style="padding:6px 8px;text-align:center"><span class="status-badge ${statusClass(c.status)}">${esc(statusLabel(c.status))}</span></td>
    </tr>
  `,
        )
        .join('')
    : '<tr><td colspan="7" style="padding:16px;text-align:center;color:#6b7280">لا توجد قوافل لهذا اليوم</td></tr>';

  const leaveRows = leaves?.length
    ? leaves
        .map(
          (l) => `
    <tr>
      <td style="padding:6px 8px;text-align:center">${esc(l.employeeCode ?? '—')}</td>
      <td style="padding:6px 8px">${esc(l.employeeName)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(l.leaveType)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(fmtTime12(l.startAt))}</td>
      <td style="padding:6px 8px;text-align:center">${esc(fmtTime12(l.endAt))}</td>
      <td style="padding:6px 8px;text-align:center">${esc(l.daysCount)} يوم</td>
      <td style="padding:6px 8px;text-align:center"><span class="status-badge ${statusClass(l.status)}">${esc(statusLabel(l.status))}</span></td>
    </tr>
  `,
        )
        .join('')
    : '<tr><td colspan="7" style="padding:16px;text-align:center;color:#6b7280">لا توجد إجازات لهذا اليوم</td></tr>';

  const locationRows = locationRequests?.length
    ? locationRequests
        .map(
          (lr) => `
    <tr>
      <td style="padding:6px 8px;text-align:center">${esc(lr.employeeCode ?? '—')}</td>
      <td style="padding:6px 8px">${esc(lr.employeeName)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(lr.requestType)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(lr.locationName)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(fmtTime12(lr.requestedAt))}</td>
      <td style="padding:6px 8px;text-align:center"><span class="status-badge ${statusClass(lr.status)}">${esc(statusLabel(lr.status))}</span></td>
    </tr>
  `,
        )
        .join('')
    : '<tr><td colspan="6" style="padding:16px;text-align:center;color:#6b7280">لا توجد طلبات موقع لهذا اليوم</td></tr>';

  const disputeRows = disputes?.length
    ? disputes
        .map(
          (d) => `
    <tr>
      <td style="padding:6px 8px;text-align:center">${esc(d.caseNumber)}</td>
      <td style="padding:6px 8px">${esc(d.title)}</td>
      <td style="padding:6px 8px;text-align:center">${esc(d.caseType)}</td>
      <td style="padding:6px 8px;text-align:center"><span class="status-badge ${statusClass(d.status)}">${esc(statusLabel(d.status))}</span></td>
      <td style="padding:6px 8px;text-align:center"><span class="priority-badge priority-${d.priority}">${esc(d.priority)}</span></td>
      <td style="padding:6px 8px;text-align:center">${esc(d.actorName ?? '—')}</td>
    </tr>
  `,
        )
        .join('')
    : '<tr><td colspan="6" style="padding:16px;text-align:center;color:#6b7280">لا توجد خلافات لهذا اليوم</td></tr>';

  const html = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>تقرير تنفيذي يومي — ${esc(dateIso)}</title>
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
      font-size: 9px;
      line-height: 1.4;
      -webkit-print-color-adjust: exact !important;
      print-color-adjust: exact !important;
    }
    /* حشوة أمان: محرك PDF يصوّر الصفحة بلا حشوة، فيُقصّ الحرف الملاصق للحافة
       (كانت «السبت» تظهر «لسبت») وذيول حروف التوقيعات في آخر الصفحة */
    .page { max-width: 1120px; margin: 0 auto; padding: 2px 8px 12px; }

    /* ─── الرأس ─── */
    .header {
      display: flex; justify-content: space-between; align-items: center;
      border-bottom: 3px solid #1e40af; padding-bottom: 10px; margin-bottom: 14px;
    }
    .header-right h1 { font-size: 17px; font-weight: 900; color: #1e40af; }
    .header-right p { font-size: 9px; color: #6b7280; margin-top: 2px; }
    .header-left { text-align: left; direction: ltr; }
    .header-left .org { font-size: 12px; font-weight: 900; color: #1e40af; }
    .header-left .sub { font-size: 8px; color: #6b7280; }

    /* ─── بطاقات الملخص ─── */
    .summary-cards {
      display: grid; grid-template-columns: repeat(6, 1fr); gap: 6px; margin-bottom: 12px;
    }
    .card {
      background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 8px; text-align: center;
    }
    .card.primary { background: #eff6ff; border-color: #bfdbfe; }
    .card.warn { background: #fef2f2; border-color: #fecaca; }
    .card.good { background: #f0fdf4; border-color: #bbf7d0; }
    /* بلا letter-spacing: يفصل الحروف العربية عن بعضها في ملفات PDF */
    .card .label { font-size: 8px; color: #6b7280; font-weight: 700; }
    .card .value { font-size: 17px; font-weight: 900; color: #111827; margin-top: 1px; }
    .card .hint { font-size: 7.5px; color: #6b7280; margin-top: 1px; }

    /* ─── معدل الحضور ─── */
    .rates-bar {
      display: flex; gap: 12px; align-items: center; justify-content: center;
      background: #f0f9ff; border: 1px solid #bfdbfe; border-radius: 6px; padding: 6px 12px; margin-bottom: 10px;
    }
    .rate-item { text-align: center; }
    .rate-item .pct { font-size: 18px; font-weight: 900; }
    .rate-item .lbl { font-size: 8px; color: #6b7280; }

    /* ─── الجداول ─── */
    .section { margin-bottom: 14px; page-break-inside: avoid; }
    .section-title {
      font-size: 11px; font-weight: 900; color: #1e40af;
      border-bottom: 2px solid #1e40af; padding-bottom: 4px; margin-bottom: 8px;
    }
    table { width: 100%; border-collapse: collapse; font-size: 8px; }
    thead th {
      background: #1e3a5f; color: white; padding: 5px 6px; text-align: center; font-weight: 800; font-size: 7px;
    }
    tbody td { border-bottom: 1px solid #e5e7eb; }
    tbody tr:nth-child(even) { background: #fafafa; }

    /* ─── شارات الحالة ─── */
    .status-badge {
      display: inline-flex; align-items: center; gap: 2px;
      padding: 1px 6px; border-radius: 999px; font-size: 7px; font-weight: 700;
    }
    .status-present { background: #dcfce7; color: #166534; }
    .status-late { background: #fef3c7; color: #92400e; }
    .status-absent { background: #fee2e2; color: #991b1b; }
    .status-missing { background: #fef3c7; color: #92400e; }
    .status-leave { background: #dbeafe; color: #1e40af; }
    .status-mission { background: #e0e7ff; color: #3730a3; }
    .status-neutral { background: #f3f4f6; color: #374151; }
    .priority-critical { background: #fee2e2; color: #991b1b; }
    .priority-urgent { background: #fef3c7; color: #92400e; }
    .priority-normal { background: #dbeafe; color: #1e40af; }

    /* ─── التذييل ─── */
    .footer {
      margin-top: 14px; padding-top: 8px; border-top: 2px solid #e2e8f0;
      display: flex; justify-content: space-between; font-size: 8px; color: #9ca3af;
    }
    .signatures {
      display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-top: 24px;
    }
    .sig-box { text-align: center; padding-top: 32px; border-top: 1px solid #d1d5db; font-size: 9px; color: #6b7280; }

    /* ─── شريط الإجراءات العلوي التفاعلي ─── */
    .action-bar {
      position: sticky;
      top: 8px;
      z-index: 9999;
      background: #0f172a;
      color: #f8fafc;
      border-radius: 12px;
      padding: 12px 18px;
      margin-bottom: 16px;
      box-shadow: 0 10px 25px -5px rgba(15, 23, 42, 0.35);
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
      body { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
      .no-print, .action-bar { display: none !important; }
      @page { size: A4 landscape; margin: 8mm 6mm; }
    }
  </style>
</head>
<body>
<div class="action-bar no-print">
  <div class="action-bar-content">
    <div class="action-title">📊 التقرير التنفيذي اليومي — ${esc(dateIso)}</div>
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
    💡 لحفظ التقرير بصيغة PDF: اضغط على زر «تحميل وحفظ كملف PDF» واختر الوجهة (Save as PDF) ثم اضغط حفظ.
  </div>
</div>
<div class="page">
  <!-- الرأس -->
  <div class="header">
    <div class="header-right">
      <h1>📊 التقرير التنفيذي اليومي الشامل</h1>
      <p>${dayName}، ${d} ${monthName} ${y} — <span dir="ltr" style="unicode-bidi:isolate">${esc(dateIso)}</span></p>
    </div>
    <div class="header-left">
      <div class="org">${esc(orgName)}</div>
      <div class="sub">${esc(systemName)}</div>
    </div>
  </div>

  <!-- بطاقات الملخص التنفيذي -->
  <div class="summary-cards">
    <div class="card primary">
      <div class="label">مطلوب حضورهم</div>
      <div class="value">${requiredToday}</div>
      <div class="hint">من ${totalEmployees} موظفًا</div>
    </div>
    <div class="card good">
      <div class="label">الحضور الفعلي</div>
      <div class="value">${presentCount}</div>
      <div class="hint">${pctText(attendancePct)}</div>
    </div>
    <div class="card primary">
      <div class="label">الحضور في الموعد</div>
      <div class="value">${onTimeCount}</div>
    </div>
    <div class="card warn">
      <div class="label">متأخرون</div>
      <div class="value">${lateCount}</div>
      <div class="hint">${presentCount > 0 ? `${((lateCount / presentCount) * 100).toFixed(1)}% من الحاضرين` : '—'}</div>
    </div>
    <div class="card warn">
      <div class="label">غياب</div>
      <div class="value">${absentCount}</div>
      <div class="hint">${notYetCount > 0 ? `${notYetCount} لم يحضروا بعد` : 'بعد موعد الحضور وفترة السماح'}</div>
    </div>
    <div class="card good">
      <div class="label">إجازات / عمل ميداني</div>
      <div class="value">${leaveCount + fieldCount}</div>
      <div class="hint">إجازات ${leaveCount} · ميداني ${fieldCount}</div>
    </div>
  </div>

  <!-- معدل الحضور والالتزام -->
  <div class="rates-bar">
    <div class="rate-item">
      <div class="pct" style="color:${pctTone(attendancePct)}">${pctText(attendancePct)}</div>
      <div class="lbl">نسبة الحضور (من المطلوب حضورهم)</div>
    </div>
    <div style="width:1px;height:30px;background:#bfdbfe"></div>
    <div class="rate-item">
      <div class="pct" style="color:${pctTone(punctualityPct)}">${pctText(punctualityPct)}</div>
      <div class="lbl">الحضور في الموعد (من الحاضرين)</div>
    </div>
  </div>

  <!-- قسم الموظفين -->
  ${
    employees.length
      ? `  <div class="section">
    <div class="section-title">📋 تفصيل حضور الموظفين (${employees.length})</div>
    <table>
      <thead>
        <tr>
          <th>الكود</th><th>الاسم</th><th>الإدارة</th><th>الحالة</th>
          <th>الحضور</th><th>الانصراف</th><th>التأخير</th>
        </tr>
      </thead>
      <tbody>${employeeRows}</tbody>
    </table>
  </div>`
      : ''
  }

  <!-- قسم المأموريات -->
  ${
    missionsArr.length
      ? `  <div class="section">
    <div class="section-title">✈ المأموريات (${missionsArr.length})</div>
    <table>
      <thead>
        <tr>
          <th>الكود</th><th>الاسم</th><th>النوع</th><th>الوجهة</th>
          <th>البداية</th><th>النهاية</th><th>الحالة</th><th>الغرض</th>
        </tr>
      </thead>
      <tbody>${missionRows}</tbody>
    </table>
  </div>`
      : ''
  }

  <!-- قسم القوافل -->
  ${
    convoysArr.length
      ? `  <div class="section">
    <div class="section-title">🚌 القوافل (${convoys?.length ?? 0})</div>
    <table>
      <thead>
        <tr>
          <th>الكود</th><th>العنوان</th><th>النوع</th><th>المشاركون</th>
          <th>البداية</th><th>النهاية</th><th>الحالة</th>
        </tr>
      </thead>
      <tbody>${convoyRows}</tbody>
    </table>
  </div>`
      : ''
  }

  <!-- قسم الإجازات -->
  ${
    leaves?.length
      ? `  <div class="section">
    <div class="section-title">📅 الإجازات (${leaves?.length ?? 0})</div>
    <table>
      <thead>
        <tr>
          <th>الكود</th><th>الاسم</th><th>النوع</th><th>البداية</th>
          <th>النهاية</th><th>الأيام</th><th>الحالة</th>
        </tr>
      </thead>
      <tbody>${leaveRows}</tbody>
    </table>
  </div>`
      : ''
  }

  <!-- قسم طلبات الموقع -->
  ${
    locationRequests?.length
      ? `  <div class="section">
    <div class="section-title">📍 طلبات الموقع (${locationRequests?.length ?? 0})</div>
    <table>
      <thead>
        <tr>
          <th>الكود</th><th>الاسم</th><th>النوع</th><th>الموقع</th>
          <th>وقت الطلب</th><th>الحالة</th>
        </tr>
      </thead>
      <tbody>${locationRows}</tbody>
    </table>
  </div>`
      : ''
  }

  <!-- قسم الخلافات -->
  ${
    disputes?.length
      ? `  <div class="section">
    <div class="section-title">⚖ الخلافات والطلبات (${disputes?.length ?? 0})</div>
    <table>
      <thead>
        <tr>
          <th>الرقم</th><th>العنوان</th><th>النوع</th><th>الحالة</th><th>الأولوية</th><th>مقدم الطلب</th>
        </tr>
      </thead>
      <tbody>${disputeRows}</tbody>
    </table>
  </div>`
      : ''
  }

  <!-- التذييل -->
  <div class="footer">
    <span>تم الإنشاء بواسطة ${esc(systemName)}</span>
    <span>تاريخ الطباعة: ${new Date().toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' })}</span>
  </div>

  <!-- التوقيعات -->
  <div class="signatures">
    <div class="sig-box">مُعد التقرير<br><small>قسم الحضور والانصراف</small></div>
    <div class="sig-box">مراجعة المدير المباشر<br><small>التوقيع: _______________</small></div>
    <div class="sig-box">اعتماد المدير التنفيذي<br><small>التوقيع: _______________</small></div>
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
  return html;
}

/** تنزيل التقرير التنفيذي اليومي كملف PDF (كان ملف HTML). */
export function downloadExecutiveDailyReportHtml(
  data: ExecutiveDailyReportDetail,
  orgName = 'جمعية خواطر أحلى شباب',
  systemName = 'منظومة أحلى شباب الإدارية',
): void {
  exportExecutiveDailyReport(data, orgName, systemName);
}

/**
 * تصدير التقرير التنفيذي اليومي كملف PDF حقيقي دون فتح أي نوافذ HTML.
 */
export function exportExecutiveDailyReport(data: ExecutiveDailyReportDetail, orgName = 'جمعية خواطر أحلى شباب', systemName = 'منظومة أحلى شباب الإدارية') {
  const html = buildExecutiveDailyReportHtml(data, orgName, systemName);
  void import('../../core/pdfExport')
    .then(({ downloadHtmlAsPdf }) => downloadHtmlAsPdf(html, `التقرير التنفيذي اليومي ${data.dateIso}`, `التقرير_التنفيذي_اليومي_${data.dateIso}.pdf`))
    .catch((err) => {
      console.error('Failed to export executive daily report PDF:', err);
    });
}
