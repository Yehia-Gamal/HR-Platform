import type { ExecutiveDailyReportDetail } from '@ahla/shared-contracts';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

export function fmtTime12(t: string | null | undefined): string {
  if (!t) return '—';
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
    .replace(/&/g, '&')
    .replace(/</g, '<')
    .replace(/>/g, '>')
    .replace(/"/g, '"');
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
  };
  if (!status) return '—';
  return map[status] ?? status;
}

function statusClass(status: string | null): string {
  if (status === 'present') return 'status-present';
  if (status === 'late') return 'status-late';
  if (status === 'absent') return 'status-absent';
  if (status === 'missing_checkout') return 'status-missing';
  if (status === 'on_leave') return 'status-leave';
  if (status === 'on_mission') return 'status-mission';
  return 'status-neutral';
}

export function exportExecutiveDailyReport(data: ExecutiveDailyReportDetail, orgName = 'جمعية خواطر أحلى شباب', systemName = 'منظومة أحلى شباب الإدارية') {
  const { dateIso, summary, employees, missions, convoys, leaves, locationRequests, disputes } = data;
  const missionsArr = missions ?? [];
  const convoysArr = convoys ?? [];
  const date = new Date(dateIso);
  const dayName = date.toLocaleDateString('ar-EG', { weekday: 'long' });
  const monthName = MONTHS[date.getMonth()];

  // ========== ملخص تنفيذي ==========
  const totalEmployees = summary.employees?.active ?? employees.length;
  const presentCount = employees.filter((e) => e.status === 'present' || e.status === 'late').length;
  const lateCount = employees.filter((e) => e.status === 'late').length;
  const absentCount = employees.filter((e) => e.status === 'absent').length;
  const leaveCount = employees.filter((e) => e.status === 'on_leave').length;
  const missionCount = employees.filter((e) => e.status === 'on_mission').length;
  const onTimeCount = employees.filter((e) => e.status === 'present').length;

  const attendancePct = totalEmployees > 0 ? ((presentCount / totalEmployees) * 100).toFixed(1) : '0.0';
  const latePct = totalEmployees > 0 ? ((lateCount / totalEmployees) * 100).toFixed(1) : '0.0';

  // ========== جداول تفصيلية ==========
  const employeeRows = employees
    .map(
      (emp) => `
    <tr class="${statusClass(emp.status)}">
      <td style="padding:6px 8px;text-align:center">${esc(emp.employeeCode ?? '—')}</td>
      <td style="padding:6px 8px">${esc(emp.employeeName)}</td>
      <td style="padding:6px 8px;text-align:center"><span class="status-badge ${statusClass(emp.status)}">${esc(statusLabel(emp.status))}</span></td>
      <td style="padding:6px 8px;text-align:center">${esc(emp.departmentName ?? '—')}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums">${esc(fmtTime12(emp.firstCheckIn))}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums">${esc(fmtTime12(emp.lastCheckOut))}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums">${emp.lateMinutes ? `${emp.lateMinutes} د` : '—'}</td>
      <td style="padding:6px 8px;text-align:center">${esc(emp.shiftName ?? '—')}</td>
      <td style="padding:6px 8px;text-align:center">${esc(emp.locationRequestStatus ?? '—')}</td>
      <td style="padding:6px 8px;text-align:center">${emp.hasApprovedLeave ? '✓ إجازة' : emp.hasMission ? '✈ مأمورية' : '—'}</td>
      <td style="padding:6px 8px;text-align:center">${esc(emp.workHours?.toFixed(1) ?? '—')}</td>
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
    .page { max-width: 1120px; margin: 0 auto; }

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
    .card .label { font-size: 7px; color: #6b7280; font-weight: 700; text-transform: uppercase; letter-spacing: 0.3px; }
    .card .value { font-size: 17px; font-weight: 900; color: #111827; margin-top: 1px; }
    .card .hint { font-size: 7px; color: #9ca3af; margin-top: 1px; }

    /* ─── معدل الحضور ─── */
    .rates-bar {
      display: flex; gap: 12px; align-items: center; justify-content: center;
      background: #f0f9ff; border: 1px solid #bfdbfe; border-radius: 6px; padding: 6px 12px; margin-bottom: 10px;
    }
    .rate-item { text-align: center; }
    .rate-item .pct { font-size: 18px; font-weight: 900; }
    .rate-item .lbl { font-size: 7px; color: #6b7280; }

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
      <h1>📊 التقرير التنفيذي اليومي الشامل</h1>
      <p>${dayName}، ${date.getDate()} ${monthName} ${date.getFullYear()} — ${esc(dateIso)}</p>
    </div>
    <div class="header-left">
      <div class="org">${esc(orgName)}</div>
      <div class="sub">${esc(systemName)}</div>
    </div>
  </div>

  <!-- بطاقات الملخص التنفيذي -->
  <div class="summary-cards">
    <div class="card primary">
      <div class="label">إجمالي الموظفين</div>
      <div class="value">${totalEmployees}</div>
    </div>
    <div class="card good">
      <div class="label">الحضور الفعلي</div>
      <div class="value">${presentCount}</div>
      <div class="hint">${attendancePct}%</div>
    </div>
    <div class="card primary">
      <div class="label">الحضور في الموعد</div>
      <div class="value">${onTimeCount}</div>
    </div>
    <div class="card warn">
      <div class="label">متأخرون</div>
      <div class="value">${lateCount}</div>
      <div class="hint">${latePct}%</div>
    </div>
    <div class="card warn">
      <div class="label">غياب</div>
      <div class="value">${absentCount}</div>
    </div>
    <div class="card good">
      <div class="label">إجازات / مأموريات</div>
      <div class="value">${leaveCount + missionCount}</div>
    </div>
  </div>

  <!-- معدل الحضور والالتزام -->
  <div class="rates-bar">
    <div class="rate-item">
      <div class="pct" style="color:${pctColor(parseFloat(attendancePct))}">${attendancePct}%</div>
      <div class="lbl">نسبة الحضور</div>
    </div>
    <div style="width:1px;height:30px;background:#bfdbfe"></div>
    <div class="rate-item">
      <div class="pct" style="color:${pctColor(100 - parseFloat(latePct))}">${(100 - parseFloat(latePct)).toFixed(1)}%</div>
      <div class="lbl">انتظام الحضور</div>
    </div>
  </div>

  <!-- قسم الموظفين -->
  <div class="section">
    <div class="section-title">📋 تفصيل حضور الموظفين (${employees.length})</div>
    <table>
      <thead>
        <tr>
          <th>الكود</th><th>الاسم</th><th>الحالة</th><th>الإدارة</th>
          <th>الحضور</th><th>الانصراف</th><th>التأخير</th>
          <th>الوردية</th><th>الموقع</th><th>العذر</th><th>ساعات العمل</th>
        </tr>
      </thead>
      <tbody>${employeeRows}</tbody>
    </table>
  </div>

  <!-- قسم المأموريات -->
  <div class="section">
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
  </div>

  <!-- قسم القوافل -->
  <div class="section">
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
  </div>

  <!-- قسم الإجازات -->
  <div class="section">
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
  </div>

  <!-- قسم طلبات الموقع -->
  <div class="section">
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
  </div>

  <!-- قسم الخلافات -->
  <div class="section">
    <div class="section-title">⚖ الخلافات والطلبات (${disputes?.length ?? 0})</div>
    <table>
      <thead>
        <tr>
          <th>الرقم</th><th>العنوان</th><th>النوع</th><th>الحالة</th><th>الأولوية</th><th>مقدم الطلب</th>
        </tr>
      </thead>
      <tbody>${disputeRows}</tbody>
    </table>
  </div>

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
  window.onload = function() { setTimeout(function() { window.print(); }, 400); };
</script>
</body>
</html>`;

  const win = window.open('', '_blank');
  if (!win) return;
  win.document.write(html);
  win.document.close();
}
