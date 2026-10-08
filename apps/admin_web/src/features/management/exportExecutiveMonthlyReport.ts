import type { ExecutiveMonthlyReport } from './useExecutiveMonthlyReport';

const MONTH_NAMES = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];

function esc(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function pctColor(pct: number): string {
  return pct >= 90 ? '#059669' : pct >= 75 ? '#d97706' : '#dc2626';
}

export function buildExecutiveMonthlyReportHtml(
  data: ExecutiveMonthlyReport,
  orgName = 'جمعية خواطر أحلى شباب',
  systemName = 'منظومة أحلى شباب الإدارية'
): string {
  const { period, attendance, departments, requests, missions, penalties, sla, generatedAt } = data;
  const monthName = MONTH_NAMES[period.month - 1] ?? `شهر ${period.month}`;

  const rowsHtml = departments.map((d) => {
    const rateColor = pctColor(d.attendance_rate);
    return `
      <tr>
        <td style="font-weight: 700; text-align: right;">${esc(d.department_name)}</td>
        <td>${d.employees_count}</td>
        <td>${d.required_days}</td>
        <td>${d.attended_days}</td>
        <td style="color: ${d.absent_days > 0 ? '#dc2626' : 'inherit'}; font-weight: ${d.absent_days > 0 ? '700' : 'normal'};">${d.absent_days}</td>
        <td>${d.late_days}</td>
        <td>${d.total_late_minutes} د</td>
        <td>
          <span style="display: inline-block; padding: 2px 8px; border-radius: 6px; font-weight: 800; color: #fff; background-color: ${rateColor};">
            ${d.attendance_rate.toFixed(1)}%
          </span>
        </td>
      </tr>
    `;
  }).join('');

  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>التقرير الشهري التنفيذي - ${monthName} ${period.year}</title>
  <style>
    @page {
      size: A4 portrait;
      margin: 10mm;
    }
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif;
    }
    body {
      background: #ffffff;
      color: #0f172a;
      font-size: 11px;
      line-height: 1.5;
      padding: 12px;
    }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      border-bottom: 2px solid #0284c7;
      padding-bottom: 12px;
      margin-bottom: 16px;
    }
    .header h1 {
      font-size: 18px;
      font-weight: 800;
      color: #0369a1;
      margin-bottom: 4px;
    }
    .header .subtitle {
      font-size: 12px;
      color: #475569;
    }
    .badge-final {
      background: #ecfdf5;
      color: #047857;
      border: 1px solid #a7f3d0;
      padding: 4px 10px;
      border-radius: 9999px;
      font-weight: 700;
      font-size: 11px;
    }
    .badge-interim {
      background: #eff6ff;
      color: #1d4ed8;
      border: 1px solid #bfdbfe;
      padding: 4px 10px;
      border-radius: 9999px;
      font-weight: 700;
      font-size: 11px;
    }
    .kpi-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 10px;
      margin-bottom: 16px;
    }
    .kpi-card {
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      padding: 10px;
      background: #f8fafc;
      text-align: center;
    }
    .kpi-title {
      font-size: 10px;
      font-weight: 600;
      color: #64748b;
      margin-bottom: 4px;
    }
    .kpi-val {
      font-size: 18px;
      font-weight: 800;
      color: #0f172a;
    }
    .section-title {
      font-size: 13px;
      font-weight: 800;
      color: #1e293b;
      border-right: 4px solid #0284c7;
      padding-right: 8px;
      margin: 14px 0 8px 0;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 14px;
      font-size: 10.5px;
    }
    th, td {
      border: 1px solid #cbd5e1;
      padding: 6px 8px;
      text-align: center;
    }
    th {
      background-color: #f1f5f9;
      font-weight: 700;
      color: #334155;
    }
    .stats-table td {
      text-align: right;
    }
    .stats-table td.val {
      text-align: left;
      font-weight: 700;
      font-family: monospace;
      font-size: 11px;
    }
    .two-cols {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
      margin-bottom: 14px;
    }
    .footer {
      margin-top: 24px;
      border-top: 1px solid #cbd5e1;
      padding-top: 12px;
      display: flex;
      justify-content: space-between;
      color: #64748b;
      font-size: 9.5px;
    }
    .signatures {
      margin-top: 30px;
      display: flex;
      justify-content: space-around;
      text-align: center;
      page-break-inside: avoid;
    }
    .sig-block {
      border-top: 1px dashed #94a3b8;
      padding-top: 8px;
      width: 140px;
      font-weight: 700;
      font-size: 10.5px;
    }
    .sig-role {
      font-size: 9.5px;
      color: #64748b;
      font-weight: normal;
    }
  </style>
</head>
<body>
  <div class="header">
    <div>
      <h1>التقرير الشهري التنفيذي الشامل</h1>
      <div class="subtitle">${esc(orgName)} — لشهر ${monthName} ${period.year}</div>
    </div>
    <div>
      <span class="${period.isFinal ? 'badge-final' : 'badge-interim'}">
        ${period.isFinal ? 'معتمد ونهائي' : `تقرير مؤقت (حتى ${period.effectiveEndDate})`}
      </span>
    </div>
  </div>

  <div class="kpi-grid">
    <div class="kpi-card">
      <div class="kpi-title">نسبة الحضور العامة</div>
      <div class="kpi-val" style="color: ${pctColor(attendance.attendance_rate)};">
        ${attendance.attendance_rate.toFixed(1)}%
      </div>
    </div>
    <div class="kpi-card">
      <div class="kpi-title">الموظفون النشطون</div>
      <div class="kpi-val">${attendance.active_employees_count}</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-title">إجمالي الطلبات والمعتمدة</div>
      <div class="kpi-val">${requests.approved_count} / ${requests.total_requests}</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-title">متوسط سرعة الاعتماد (SLA)</div>
      <div class="kpi-val">${sla.avg_turnaround_hours.toFixed(1)} س</div>
    </div>
  </div>

  <div class="section-title">أداء الحضور والانضباط عبر الإدارات</div>
  <table>
    <thead>
      <tr>
        <th style="text-align: right;">الإدارة / القسم</th>
        <th>الموظفون</th>
        <th>المطلوب</th>
        <th>الحضور</th>
        <th>الغياب</th>
        <th>التأخير</th>
        <th>دقائق التأخير</th>
        <th>نسبة الانضباط</th>
      </tr>
    </thead>
    <tbody>
      ${rowsHtml}
    </tbody>
  </table>

  <div class="two-cols">
    <div>
      <div class="section-title">إحصاءات الحضور والانصراف التفصيلية</div>
      <table class="stats-table">
        <tbody>
          <tr><td>أيام التقويم الإجمالية للموظفين</td><td class="val">${attendance.total_calendar_days}</td></tr>
          <tr><td>أيام العمل الواجبة (المطلوبة)</td><td class="val">${attendance.required_days}</td></tr>
          <tr><td>أيام الحضور الفعلي</td><td class="val">${attendance.attended_days}</td></tr>
          <tr><td>أيام الغياب غير المبرر</td><td class="val" style="color: #dc2626;">${attendance.absent_days}</td></tr>
          <tr><td>أيام التأخير المسجلة</td><td class="val">${attendance.late_days}</td></tr>
          <tr><td>إجمالي دقائق التأخير المسجلة</td><td class="val">${attendance.total_late_minutes} دقيقة</td></tr>
          <tr><td>أيام الإجازات المصرح بها</td><td class="val">${attendance.leave_days}</td></tr>
          <tr><td>أيام المأموريات والقوافل الميدانية</td><td class="val">${attendance.offsite_days}</td></tr>
        </tbody>
      </table>
    </div>

    <div>
      <div class="section-title">حركة الطلبات والقرارات الإدارية</div>
      <table class="stats-table">
        <tbody>
          <tr><td>إجمالي الطلبات المقدمة</td><td class="val">${requests.total_requests}</td></tr>
          <tr><td>الطلبات المعتمدة</td><td class="val" style="color: #059669;">${requests.approved_count}</td></tr>
          <tr><td>الطلبات المرفوضة</td><td class="val" style="color: #dc2626;">${requests.rejected_count}</td></tr>
          <tr><td>طلبات قيد المراجعة</td><td class="val" style="color: #d97706;">${requests.pending_count}</td></tr>
          <tr><td>طلبات الإجازات</td><td class="val">${requests.leave_requests}</td></tr>
          <tr><td>طلبات المأموريات الميدانية</td><td class="val">${requests.mission_requests}</td></tr>
          <tr><td>طلبات القوافل الميدانية</td><td class="val">${requests.convoy_requests}</td></tr>
          <tr><td>أذونات التأخير والانصراف</td><td class="val">${requests.permit_requests}</td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <div class="two-cols">
    <div>
      <div class="section-title">المأموريات الميدانية والامتثال</div>
      <table class="stats-table">
        <tbody>
          <tr><td>إجمالي مأموريات الشهر الميدانية</td><td class="val">${missions.total_executions}</td></tr>
          <tr><td>المأموريات المنجزة بالكامل</td><td class="val">${missions.completed_count}</td></tr>
          <tr><td>مأموريات أغلقت تلقائياً لعدم الإكمال</td><td class="val" style="color: ${missions.auto_closed_count > 0 ? '#d97706' : 'inherit'};">${missions.auto_closed_count}</td></tr>
          <tr><td>تقارير المأموريات المرفوعة والموثقة</td><td class="val">${missions.reported_count}</td></tr>
        </tbody>
      </table>
    </div>

    <div>
      <div class="section-title">الغرامات الفورية ومستوى الخدمة (SLA)</div>
      <table class="stats-table">
        <tbody>
          <tr><td>إجمالي الغرامات المسجلة</td><td class="val">${penalties.total_penalties}</td></tr>
          <tr><td>الغرامات المسددة لصندوق الزمالة</td><td class="val" style="color: #059669;">${penalties.paid_count} (${penalties.paid_amount} ج.م)</td></tr>
          <tr><td>غرامات معلقة أو قيد النزاع</td><td class="val">${penalties.unpaid_count} (${penalties.total_amount - penalties.paid_amount} ج.م)</td></tr>
          <tr><td>وسيط سرعة الرد على الطلبات (Median)</td><td class="val">${sla.median_turnaround_hours.toFixed(1)} ساعة</td></tr>
          <tr><td>القرارات المصعدة بسبب تجاوز المهلة</td><td class="val" style="color: ${sla.escalated_count > 0 ? '#d97706' : 'inherit'};">${sla.escalated_count}</td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <div class="signatures">
    <div class="sig-block">
      مُعد التقرير
      <div class="sig-role">قسم الحضور والمتابعة</div>
    </div>
    <div class="sig-block">
      مدير الموارد البشرية
      <div class="sig-role">مراجعة واعتماد</div>
    </div>
    <div class="sig-block">
      المدير التنفيذي
      <div class="sig-role">الاعتماد النهائي</div>
    </div>
  </div>

  <div class="footer">
    <span>تم استخراج التقرير بواسطة ${esc(systemName)}</span>
    <span>تاريخ التوليد: ${generatedAt ? new Date(generatedAt).toLocaleString('ar-EG') : new Date().toLocaleString('ar-EG')}</span>
  </div>
</body>
</html>`;
}

export function exportExecutiveMonthlyReport(
  data: ExecutiveMonthlyReport,
  orgName = 'جمعية خواطر أحلى شباب',
  systemName = 'منظومة أحلى شباب الإدارية'
): Promise<void> {
  const html = buildExecutiveMonthlyReportHtml(data, orgName, systemName);
  const monthName = MONTH_NAMES[data.period.month - 1] ?? `${data.period.month}`;
  const title = `التقرير الشهري التنفيذي ${monthName} ${data.period.year}`;
  const filename = `التقرير_الشهري_التنفيذي_${data.period.year}_${String(data.period.month).padStart(2, '0')}.pdf`;

  return import('../../core/pdfExport')
    .then(({ downloadHtmlAsPdf }) => downloadHtmlAsPdf(html, title, filename))
    .catch((err) => {
      console.error('Failed to export executive monthly report PDF:', err);
      throw err;
    });
}
