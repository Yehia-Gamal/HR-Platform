import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

const _warnStatuses = {'غائب دون إذن', 'يحتاج مراجعة'};

String _fmtTime(String? t) => (t != null && t.length >= 5) ? t.substring(0, 5) : '—';

/// يهرّب محارف HTML الخاصة لمنع XSS/injection عند إدراج نصوص المستخدم في قوالب HTML.
String _escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _pctColor(double pct) =>
    pct >= 90 ? '#059669' : pct >= 75 ? '#f59e0b' : '#dc2626';

/// يُنشئ HTML منسّق لكشف الحضور الشهري — نفس تصميم نسخة الويب بالضبط.
String _buildAttendanceHtml(MonthlyAttendanceStatement stmt) {
  final s = stmt.summary;
  final monthName = (stmt.month >= 1 && stmt.month <= 12)
      ? _months[stmt.month - 1]
      : '';
  final attendancePct = stmt.attendancePercentage;
  final compliancePct = s.hoursComplianceRate;
  final complianceAvailable = s.hoursComplianceAvailable;

  final dayRows = StringBuffer();
  for (final d in stmt.days) {
    final tags = <String>[];
    // استنتاج الغياب والعطلة من حقل status بدل خصائص غير موجودة.
    if (d.status.contains('غائب')) tags.add('غائب');
    if (d.status == 'عطلة رسمية') tags.add('عطلة رسمية');
    if (d.hasLeave) tags.add('إجازة');
    if (d.hasMission) tags.add('مأمورية');
    if (d.hasPermit) tags.add('إذن');
    if (d.hasConvoyFundi) tags.add('قافلة/فاندي');
    if (d.missingCheckIn) tags.add('نقص حضور');
    if (d.missingCheckOut) tags.add('نقص انصراف');
    if (d.isOpenShift) tags.add('بانتظار الانصراف');
    if (d.isFuture) tags.add('قادم');
    if (d.hasCorrection) tags.add('تصحيح');

    final isRest = d.status == 'راحة أسبوعية' || d.status == 'عطلة رسمية';
    final isWarn = _warnStatuses.contains(d.status);
    final rowBg = d.isFuture
        ? '#f8fafc'
        : d.isOpenShift
        ? '#f0f9ff'
        : isRest
        ? '#f0f9ff'
        : isWarn
        ? '#fef2f2'
        : '';
    final statusColor = isWarn ? '#dc2626' : isRest ? '#0369a1' : '#111827';

    dayRows.writeln('''<tr style="border-bottom:1px solid #e5e7eb;${rowBg.isNotEmpty ? 'background:$rowBg;' : ''}">
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${_escapeHtml(d.date)}</td>
      <td style="padding:6px 8px;text-align:center">${_escapeHtml(d.dayNameAr)}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${_fmtTime(d.checkIn)}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;direction:ltr">${_fmtTime(d.checkOut)}</td>
      <td style="padding:6px 8px;text-align:center">${d.shiftName.isNotEmpty ? _escapeHtml(d.shiftName) : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums">${d.workHours > 0 ? d.workHours.toStringAsFixed(1) : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;${d.lateMinutes > 0 ? 'color:#d97706;font-weight:700;' : ''}">${d.lateMinutes > 0 ? '${d.lateMinutes} د' : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;${d.earlyLeaveMinutes > 0 ? 'color:#d97706;font-weight:700;' : ''}">${d.earlyLeaveMinutes > 0 ? '${d.earlyLeaveMinutes} د' : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-variant-numeric:tabular-nums;${d.overtimeMinutes > 0 ? 'color:#059669;font-weight:700;' : ''}">${d.overtimeMinutes > 0 ? '${d.overtimeMinutes} د' : '—'}</td>
      <td style="padding:6px 8px;text-align:center;font-weight:700;color:$statusColor">${_escapeHtml(d.status)}</td>
      <td style="padding:6px 8px;text-align:center;font-size:9px">${tags.isNotEmpty ? tags.join('، ') : _escapeHtml(d.correctionNote ?? '')}</td>
    </tr>''');
  }

  final now = DateTime.now();
  final printDate = '${now.day} ${_months[now.month - 1]} ${now.year}';

  return '''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>كشف حضور — ${_escapeHtml(stmt.employeeNameAr)} — $monthName ${stmt.year}</title>
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
  <div class="header">
    <div class="header-right">
      <h1>📋 كشف الحضور والانصراف الشهري</h1>
      <p>$monthName ${stmt.year} — من ${_escapeHtml(stmt.startDate)} إلى ${_escapeHtml(stmt.endDate)}</p>
    </div>
    <div class="header-left">
      <div class="org">جمعية خواطر أحلى شباب</div>
      <div class="sub">منظومة الإدارة المؤسسية</div>
    </div>
  </div>

  <div class="emp-grid">
    <div class="emp-field"><label>الاسم</label><span>${_escapeHtml(stmt.employeeNameAr)}</span></div>
    <div class="emp-field"><label>الكود</label><span>${stmt.employeeCode != null ? _escapeHtml(stmt.employeeCode!) : '—'}</span></div>
    <div class="emp-field"><label>الإدارة</label><span>${_escapeHtml(stmt.department)}</span></div>
    <div class="emp-field"><label>المسمى الوظيفي</label><span>${_escapeHtml(stmt.jobTitle)}</span></div>
    <div class="emp-field"><label>الفرع</label><span>${_escapeHtml(stmt.branch)}</span></div>
    <div class="emp-field"><label>المدير المباشر</label><span>${_escapeHtml(stmt.manager)}</span></div>
    <div class="emp-field"><label>تاريخ التعيين</label><span style="direction:ltr;text-align:right">${stmt.hireDate != null ? _escapeHtml(stmt.hireDate!) : '—'}</span></div>
    <div class="emp-field"><label>الفترة</label><span>$monthName ${stmt.year}</span></div>
  </div>

  <div class="rates-bar">
    <div class="rate-item">
      <div class="pct" style="color:${_pctColor(attendancePct)}">${attendancePct.toStringAsFixed(0)}%</div>
      <div class="lbl">نسبة الحضور</div>
    </div>
    <div style="width:1px;height:40px;background:#bfdbfe"></div>
    <div class="rate-item">
      <div class="pct" style="color:${complianceAvailable ? _pctColor(compliancePct) : '#64748b'}">${complianceAvailable ? '${compliancePct.toStringAsFixed(0)}%' : 'غير متاح'}</div>
      <div class="lbl">التزام الساعات</div>
    </div>
  </div>

  <div class="summary-grid">
    <div class="metric"><div class="label">أيام الحضور</div><div class="value">${s.attendanceRatePresentDays}</div><div class="hint">من ${s.attendanceRateDueDays} يوم عمل في الشهر</div></div>
    <div class="metric${s.absentDays > 0 ? ' warn' : ''}"><div class="label">أيام الغياب</div><div class="value">${s.absentDays}</div></div>
    <div class="metric"><div class="label">وردية مفتوحة</div><div class="value">${s.openShiftDays}</div><div class="hint">بانتظار الانصراف</div></div>
    <div class="metric"><div class="label">أيام قادمة</div><div class="value">${s.upcomingDays}</div><div class="hint">لا تُحسب غيابًا</div></div>
    <div class="metric"><div class="label">أيام الإجازات</div><div class="value">${s.leaveDays}</div></div>
    <div class="metric"><div class="label">أيام المأموريات</div><div class="value">${s.missionDays}</div></div>
    <div class="metric"><div class="label">إذنات</div><div class="value">${s.permitCount}</div></div>
    <div class="metric"><div class="label">قوافل/فاندي</div><div class="value">${s.convoyFundiDays}</div></div>
    <div class="metric"><div class="label">ساعات العمل</div><div class="value">${(s.hoursRateWorkedMinutes / 60).toStringAsFixed(1)}</div><div class="hint">من ${(s.hoursRateRequiredMinutes / 60).toStringAsFixed(1)} ساعة شهرية — ${compliancePct.toStringAsFixed(0)}%</div></div>
    <div class="metric"><div class="label">تغطية أيام العمل</div><div class="value">${s.coverageRate.toStringAsFixed(0)}%</div><div class="hint">${s.coverageDays} من ${s.scheduledDays}</div></div>
    <div class="metric good"><div class="label">ساعات إضافية</div><div class="value">${s.totalOvertimeMinutes} د</div></div>
  </div>

  <div class="stats-bar">
    <div class="stat-item"><span class="s-label">تأخير كلي:</span><span class="s-value">${s.totalLateMinutes} د</span></div>
    <div class="stat-item"><span class="s-label">خروج مبكر:</span><span class="s-value">${s.totalEarlyLeaveMinutes} د</span></div>
    <div class="stat-item"><span class="s-label">نسيان حضور:</span><span class="s-value">${s.missingCheckInCount}</span></div>
    <div class="stat-item"><span class="s-label">نسيان انصراف:</span><span class="s-value">${s.missingCheckOutCount}</span></div>
    <div class="stat-item"><span class="s-label">عطل رسمية:</span><span class="s-value">${s.holidayDays}</span></div>
    <div class="stat-item"><span class="s-label">أيام راحة:</span><span class="s-value">${s.restDays}</span></div>
    <div class="stat-item"><span class="s-label">تصحيحات:</span><span class="s-value">${s.correctionCount}</span></div>
  </div>

  <table>
    <thead>
      <tr>
        <th>التاريخ</th><th>اليوم</th><th>الحضور</th><th>الانصراف</th>
        <th>الوردية</th><th>ساعات فعلية</th><th>التأخير</th>
        <th>خروج مبكر</th><th>إضافي</th><th>الحالة</th><th>ملاحظات</th>
      </tr>
    </thead>
    <tbody>
      $dayRows
    </tbody>
  </table>

  <div class="footer">
    <span>تم الإنشاء بواسطة منظومة أحلى شباب الإدارية</span>
    <span>تاريخ الطباعة: $printDate</span>
  </div>

  <div class="signatures">
    <div class="sig-box">الموظف</div>
    <div class="sig-box">المدير المباشر</div>
    <div class="sig-box">الموارد البشرية</div>
  </div>
</div>
</body>
</html>''';
}

/// يحوّل كشف الحضور إلى PDF ويفتح حوار المشاركة/الحفظ.
Future<void> exportAttendancePdf(MonthlyAttendanceStatement statement) async {
  final html = _buildAttendanceHtml(statement);
  final monthName = (statement.month >= 1 && statement.month <= 12)
      ? _months[statement.month - 1]
      : '${statement.month}';
  final fileName =
      'كشف-حضور-${statement.employeeCode ?? statement.employeeNameAr}-${statement.year}-$monthName.pdf';

  // TODO(pdf-refactor): convertHtml deprecated في printing >= 6. الحل النهائي هو بناء
  // المستند مباشرة بـ package:pdf بدلاً من تمرير HTML. حالياً نُكتم التحذير لأن البديل
  // من نفس إصدار printing المثبّت غير متاح.
  // ignore: deprecated_member_use
  final pdfBytes = await Printing.convertHtml(
    html: html,
    format: PdfPageFormat.a4.landscape,
  );

  await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
}
