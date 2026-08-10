import 'dart:io';
import 'dart:typed_data';

import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _months = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

const _warnStatuses = {'غائب دون إذن', 'يحتاج مراجعة'};

// ألوان مكررة من نسخة HTML السابقة (نفس التصميم)
const _navy = PdfColor.fromInt(0xFF1E3A5F);
const _blue = PdfColor.fromInt(0xFF1E40AF);
const _border = PdfColor.fromInt(0xFFE2E8F0);
const _bg = PdfColor.fromInt(0xFFF8FAFC);
const _bgLight = PdfColor.fromInt(0xFFF0F9FF);
const _bgYellow = PdfColor.fromInt(0xFFFEFCE8);
const _red = PdfColor.fromInt(0xFFDC2626);
const _green = PdfColor.fromInt(0xFF059669);
const _amber = PdfColor.fromInt(0xFFF59E0B);
const _amberDark = PdfColor.fromInt(0xFFD97706);
const _grayText = PdfColor.fromInt(0xFF6B7280);
const _grayHint = PdfColor.fromInt(0xFF9CA3AF);
const _dark = PdfColor.fromInt(0xFF111827);
const _skyLine = PdfColor.fromInt(0xFFBFDBFE);
const _amberLine = PdfColor.fromInt(0xFFFDE68A);
const _rowLine = PdfColor.fromInt(0xFFE5E7EB);
const _white = PdfColor.fromInt(0xFFFFFFFF);

String _fmtTime(String? t) =>
    (t != null && t.length >= 5) ? t.substring(0, 5) : '—';

PdfColor _pctColor(double pct) => pct >= 90 ? _green : (pct >= 75 ? _amber : _red);

/// يحمّل خط Cairo العربي من الأصول (يُستدعى مرة واحدة ويُخزَّن).
pw.Font? _cairoFont;
Future<pw.Font> _loadCairoFont() async {
  if (_cairoFont != null) return _cairoFont!;
  final data = await rootBundle.load('assets/fonts/Cairo.ttf');
  final font = pw.Font.ttf(data.buffer.asByteData());
  _cairoFont = font;
  return font;
}

/// نص بسيط باتجاه RTL افتراضي.
pw.Text _t(String text,
    {double size = 11,
    PdfColor color = _dark,
    pw.FontWeight weight = pw.FontWeight.normal}) =>
    pw.Text(text,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: weight));

/// نص بسيط باتجاه LTR (تواريخ/أرقام/أوقات).
pw.Text _tl(String text,
        {double size = 11,
        PdfColor color = _dark,
        pw.FontWeight weight = pw.FontWeight.normal}) =>
    pw.Text(text,
        textDirection: pw.TextDirection.ltr,
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: weight));

/// بطاقة مترية ضمن شبكة الملخص.
pw.Widget _metric(String label, String value,
    {String hint = '', PdfColor? valueColor, bool warn = false}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      color: _bg,
      border: pw.Border.all(color: _border),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        _t(label, size: 7.5, color: _grayText, weight: pw.FontWeight.bold),
        pw.SizedBox(height: 2),
        _t(value,
            size: 15,
            weight: pw.FontWeight.bold,
            color: warn ? _red : (valueColor ?? _dark)),
        if (hint.isNotEmpty) ...[
          pw.SizedBox(height: 1),
          _t(hint, size: 7, color: _grayHint),
        ],
      ],
    ),
  );
}

pw.Widget _empField(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _t(label, size: 8, color: _grayText, weight: pw.FontWeight.bold),
      pw.SizedBox(height: 1),
      _t(value, size: 11, weight: pw.FontWeight.bold),
    ],
  );
}

/// يُنشئ مستند كشف الحضور الشهري مباشرة بـ package:pdf (بدون HTML).
Future<Uint8List> _buildAttendancePdf(MonthlyAttendanceStatement stmt) async {
  final font = await _loadCairoFont();
  final s = stmt.summary;
  final monthName = (stmt.month >= 1 && stmt.month <= 12)
      ? _months[stmt.month - 1]
      : '';
  final attendancePct = stmt.attendancePercentage;
  final compliancePct = s.hoursComplianceRate;
  final complianceAvailable = s.hoursComplianceAvailable;

  final now = DateTime.now();
  final printDate = '${now.day} ${_months[now.month - 1]} ${now.year}';

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(28, 34, 28, 34),
      theme: pw.ThemeData.withFont(base: font),
      build: (context) => [
        // ---------- Header ----------
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _blue, width: 3)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _t('📋 كشف الحضور والانصراف الشهري',
                      size: 16, color: _blue, weight: pw.FontWeight.bold),
                  _t('$monthName ${stmt.year} — من ${stmt.startDate} إلى ${stmt.endDate}',
                      size: 9, color: _grayText),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _t('جمعية خواطر أحلى شباب',
                      size: 12, color: _blue, weight: pw.FontWeight.bold),
                  _t('منظومة الإدارة المؤسسية', size: 8.5, color: _grayText),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),

        // ---------- Employee grid ----------
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _bg,
            border: pw.Border.all(color: _border),
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: _empField('الاسم', stmt.employeeNameAr)),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                      child: _empField('الكود', stmt.employeeCode ?? '—')),
                  pw.SizedBox(width: 16),
                  pw.Expanded(child: _empField('الإدارة', stmt.department)),
                  pw.SizedBox(width: 16),
                  pw.Expanded(child: _empField('المسمى الوظيفي', stmt.jobTitle)),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: _empField('الفرع', stmt.branch)),
                  pw.SizedBox(width: 16),
                  pw.Expanded(child: _empField('المدير المباشر', stmt.manager)),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                      child: _empField('تاريخ التعيين', stmt.hireDate ?? '—')),
                  pw.SizedBox(width: 16),
                  pw.Expanded(child: _empField('الفترة', '$monthName ${stmt.year}')),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),

        // ---------- Rates bar ----------
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _bgLight,
            border: pw.Border.all(color: _skyLine),
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              _t('${attendancePct.toStringAsFixed(0)}%',
                  size: 20,
                  color: _pctColor(attendancePct),
                  weight: pw.FontWeight.bold),
              pw.SizedBox(width: 6),
              _t('نسبة الحضور', size: 9, color: _grayText),
              pw.SizedBox(width: 16),
              pw.Container(
                  width: 1,
                  height: 36,
                  decoration: pw.BoxDecoration(color: _skyLine)),
              pw.SizedBox(width: 16),
              _t(
                  complianceAvailable
                      ? '${compliancePct.toStringAsFixed(0)}%'
                      : 'غير متاح',
                  size: 20,
                  color: complianceAvailable
                      ? _pctColor(compliancePct)
                      : _grayHint,
                  weight: pw.FontWeight.bold),
              pw.SizedBox(width: 6),
              _t('التزام الساعات', size: 9, color: _grayText),
            ],
          ),
        ),
        pw.SizedBox(height: 10),

        // ---------- Summary metrics grid ----------
        pw.Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _metric('أيام الحضور', '${s.attendanceRatePresentDays}',
                hint: 'من ${s.attendanceRateDueDays} يوم عمل في الشهر'),
            _metric('أيام الغياب', '${s.absentDays}', warn: s.absentDays > 0),
            _metric('وردية مفتوحة', '${s.openShiftDays}',
                hint: 'بانتظار الانصراف'),
            _metric('أيام قادمة', '${s.upcomingDays}',
                hint: 'لا تُحسب غيابًا'),
            _metric('أيام الإجازات', '${s.leaveDays}'),
            _metric('أيام المأموريات', '${s.missionDays}'),
            _metric('إذنات', '${s.permitCount}'),
            _metric('قوافل/فاندي', '${s.convoyFundiDays}'),
            _metric('ساعات العمل',
                (s.hoursRateWorkedMinutes / 60).toStringAsFixed(1),
                hint:
                    'من ${(s.hoursRateRequiredMinutes / 60).toStringAsFixed(1)} ساعة شهرية — ${compliancePct.toStringAsFixed(0)}%'),
            _metric('تغطية أيام العمل', '${s.coverageRate.toStringAsFixed(0)}%',
                hint: '${s.coverageDays} من ${s.scheduledDays}'),
            _metric('ساعات إضافية', '${s.totalOvertimeMinutes} د',
                valueColor: _green),
          ],
        ),
        pw.SizedBox(height: 10),

        // ---------- Stats bar ----------
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: pw.BoxDecoration(
            color: _bgYellow,
            border: pw.Border.all(color: _amberLine),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _t('تأخير كلي: ${s.totalLateMinutes} د',
                  size: 9, weight: pw.FontWeight.bold),
              _t('خروج مبكر: ${s.totalEarlyLeaveMinutes} د',
                  size: 9, weight: pw.FontWeight.bold),
              _t('نسيان حضور: ${s.missingCheckInCount}',
                  size: 9, weight: pw.FontWeight.bold),
              _t('نسيان انصراف: ${s.missingCheckOutCount}',
                  size: 9, weight: pw.FontWeight.bold),
              _t('عطل رسمية: ${s.holidayDays}',
                  size: 9, weight: pw.FontWeight.bold),
              _t('أيام راحة: ${s.restDays}',
                  size: 9, weight: pw.FontWeight.bold),
              _t('تصحيحات: ${s.correctionCount}',
                  size: 9, weight: pw.FontWeight.bold),
            ],
          ),
        ),
        pw.SizedBox(height: 12),

        // ---------- Days table ----------
        pw.Table(
          border: pw.TableBorder.all(color: _rowLine, width: 0.5),
          defaultColumnWidth: pw.FlexColumnWidth(),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _navy),
              children: [
                for (final h in [
                  'التاريخ', 'اليوم', 'الحضور', 'الانصراف', 'الوردية',
                  'ساعات فعلية', 'التأخير', 'خروج مبكر', 'إضافي', 'الحالة',
                  'ملاحظات'
                ])
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4, vertical: 6),
                    alignment: pw.Alignment.center,
                    child: _t(h,
                        size: 8.5,
                        color: _white,
                        weight: pw.FontWeight.bold),
                  ),
              ],
            ),
            for (final d in stmt.days)
              pw.TableRow(
                children: [
                  _dayCell(d.date, ltr: true),
                  _dayCell(d.dayNameAr),
                  _dayCell(_fmtTime(d.checkIn), ltr: true),
                  _dayCell(_fmtTime(d.checkOut), ltr: true),
                  _dayCell(d.shiftName.isNotEmpty ? d.shiftName : '—'),
                  _dayCell(
                      d.workHours > 0 ? d.workHours.toStringAsFixed(1) : '—',
                      ltr: true),
                  _dayCell(d.lateMinutes > 0 ? '${d.lateMinutes} د' : '—',
                      ltr: true,
                      color: d.lateMinutes > 0 ? _amberDark : null,
                      bold: d.lateMinutes > 0),
                  _dayCell(
                      d.earlyLeaveMinutes > 0 ? '${d.earlyLeaveMinutes} د' : '—',
                      ltr: true,
                      color: d.earlyLeaveMinutes > 0 ? _amberDark : null,
                      bold: d.earlyLeaveMinutes > 0),
                  _dayCell(
                      d.overtimeMinutes > 0 ? '${d.overtimeMinutes} د' : '—',
                      ltr: true,
                      color: d.overtimeMinutes > 0 ? _green : null,
                      bold: d.overtimeMinutes > 0),
                  _dayCell(d.status, bold: true, color: _statusColor(d)),
                  _dayCell(_dayNotes(d)),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 14),

        // ---------- Footer ----------
        pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _border, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _t('تم الإنشاء بواسطة منظومة أحلى شباب الإدارية',
                  size: 8.5, color: _grayHint),
              _t('تاريخ الطباعة: $printDate', size: 8.5, color: _grayHint),
            ],
          ),
        ),
        pw.SizedBox(height: 24),

        // ---------- Signatures ----------
        pw.Row(
          children: [
            for (final label in ['الموظف', 'المدير المباشر', 'الموارد البشرية'])
              pw.Expanded(
                child: pw.Container(
                  margin: const pw.EdgeInsets.symmetric(horizontal: 8),
                  padding: const pw.EdgeInsets.only(top: 34),
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                        top: pw.BorderSide(color: _grayHint, width: 1)),
                  ),
                  child: _t(label, size: 9, color: _grayText),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

/// نص مخصص داخل خلية الجدول مع تنسيق حسب اليوم.
pw.Widget _dayCell(String text,
    {bool ltr = false,
    PdfColor? color,
    bool bold = false}) {
  final t = ltr
      ? _tl(text,
          size: 8,
          color: color ?? _dark,
          weight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)
      : _t(text,
          size: 8,
          color: color ?? _dark,
          weight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  return pw.Container(
    alignment: pw.Alignment.center,
    child: t,
  );
}

PdfColor _statusColor(AttendanceStatementDay d) {
  final isRest = d.status == 'راحة أسبوعية' || d.status == 'عطلة رسمية';
  if (_warnStatuses.contains(d.status)) return _red;
  if (isRest) return PdfColor.fromInt(0xFF0369A1);
  return _dark;
}

/// ملاحظات اليوم: مجموعة وسوم + نص التصحيح إن وُجد.
String _dayNotes(AttendanceStatementDay d) {
  final tags = <String>[];
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
  return tags.isNotEmpty ? tags.join('، ') : (d.correctionNote ?? '');
}

/// يحوّل كشف الحضور إلى PDF ويحفظه على الجهاز، ثم يعيد مسار الملف.
Future<String> exportAttendancePdf(MonthlyAttendanceStatement statement) async {
  final pdfBytes = await _buildAttendancePdf(statement);
  final monthName = (statement.month >= 1 && statement.month <= 12)
      ? _months[statement.month - 1]
      : '${statement.month}';
  final fileName =
      'كشف-حضور-${statement.employeeCode ?? statement.employeeNameAr}-${statement.year}-$monthName.pdf';

  final dir = await getDownloadsDirectory();
  final target = dir != null
      ? File('${dir.path}/$fileName')
      : File('${(await getApplicationDocumentsDirectory()).path}/$fileName');
  await target.writeAsBytes(pdfBytes, flush: true);
  return target.path;
}
