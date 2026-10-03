/**
 * أدوات تصدير البيانات — CSV (يفتح في Excel) وطباعة PDF.
 * لا تعتمد على مكتبات خارجية؛ CSV بترميز UTF-8 مع BOM يفتح بالعربية في Excel.
 */

export interface ExportColumn<T> {
  key: string;
  header: string;
  /** استخراج القيمة النصية للخلية */
  get: (row: T) => string | number | null | undefined;
}

/**
 * يحمي خلية CSV: يمنع حقن الصيغ (أي خلية تبدأ بـ = + - @ tab أو CR تُسبق
 * بفاصلة عليا) ويغلّف ما يحتوي فاصلة أو تنصيص أو سطر جديد بتنصيص مزدوج.
 * متاحة عمومًا لبناة التقارير المخصصة خارج نموذج الأعمدة.
 */
export function csvSafeCell(value: string | number | null | undefined): string {
  if (value === null || value === undefined) return '';
  let s = String(value);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  if (/[",\n\r]/.test(s)) s = `"${s.replace(/"/g, '""')}"`;
  return s;
}

function csvCell(value: string | number | null | undefined): string {
  return csvSafeCell(value);
}

/** توليد محتوى CSV مع BOM لدعم العربية في Excel */
export function toCsv<T>(columns: ExportColumn<T>[], rows: T[]): string {
  const header = columns.map((c) => csvCell(c.header)).join(',');
  const body = rows.map((row) => columns.map((c) => csvCell(c.get(row))).join(',')).join('\n');
  return `\uFEFF${header}\n${body}`;
}

/** تنزيل ملف CSV باسم محدد */
export function downloadCsv(filename: string, csv: string): void {
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

export interface PrintableSection {
  title: string;
  subtitle?: string;
  table: {
    headers: string[];
    rows: string[][];
  };
}

/**
 * توليد كود HTML الكامل للتقرير مع شريط أدوات تفاعلي للتحميل كـ PDF أو HTML،
 * مع تنسيقات طباعة معتمدة تخفي أزرار التحكم تماماً عند التصدير والطباعة.
 */
export function generateReportHtml(sections: PrintableSection[], documentTitle: string, summary?: { label: string; value: string }[]): string {
  const esc = (s: string): string =>
    String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');

  const formatCell = (text: string): string => {
    const s = String(text ?? '').trim();
    if (s === 'معلق عن العمل' || s === 'suspended') {
      return `<span class="badge badge-suspended">${esc(s)}</span>`;
    }
    if (s === 'مدفوعة' || s === 'paid' || s === 'نشط' || s === 'active') {
      return `<span class="badge badge-paid">${esc(s)}</span>`;
    }
    if (s === 'بانتظار السداد' || s === 'pending_payment' || s === 'pending') {
      return `<span class="badge badge-pending">${esc(s)}</span>`;
    }
    if (s === 'مضاعفة' || s === 'doubled') {
      return `<span class="badge badge-doubled">${esc(s)}</span>`;
    }
    if (s === 'ملغاة' || s === 'cancelled') {
      return `<span class="badge badge-cancelled">${esc(s)}</span>`;
    }
    return esc(s);
  };

  const tableHtml = (t: { headers: string[]; rows: string[][] }) => `
    <table>
      <thead><tr>${t.headers.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead>
      <tbody>
        ${t.rows.map((r, i) => `<tr class="${i % 2 === 0 ? 'even' : 'odd'}">${r.map((c) => `<td>${formatCell(c)}</td>`).join('')}</tr>`).join('\n')}
      </tbody>
    </table>`;

  const summaryHtml =
    summary && summary.length > 0
      ? `<div class="summary-grid">${summary.map((s) => `<div class="summary-card"><span class="summary-value">${esc(s.value)}</span><span class="summary-label">${esc(s.label)}</span></div>`).join('')}</div>`
      : '';

  const body = sections
    .map(
      (s) => `
        <h2>${esc(s.title)}</h2>
        ${s.subtitle ? `<p class="sub">${esc(s.subtitle)}</p>` : ''}
        ${tableHtml(s.table)}
      `,
    )
    .join('\n');

  const now = new Date();
  const dateIso = now.toISOString().slice(0, 10);
  const dateStr = now.toLocaleDateString('ar-EG', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
  const timeStr = now.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' });
  const safeFilename = `${documentTitle.replace(/\s+/g, '_')}_${dateIso}`;

  return `<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>${esc(safeFilename)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800;900&display=swap" rel="stylesheet" />
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body {
    direction: rtl !important;
    text-align: right !important;
    unicode-bidi: embed !important;
    font-family: 'Cairo', system-ui, -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif;
    padding: 24px;
    color: #1f2937;
    line-height: 1.6;
    background: #f8fafc;
    -webkit-font-smoothing: antialiased;
  }
  table, th, td, div, span, p, h1, h2 {
    direction: rtl;
    unicode-bidi: embed;
  }

  /* ─── شريط الإجراءات العلوي (يظهر للمستخدم على الشاشة ويختفي تماماً عند الطباعة والحفظ كـ PDF) ─── */
  .action-bar {
    position: sticky;
    top: 12px;
    z-index: 9999;
    background: #0f172a;
    color: #f8fafc;
    border-radius: 14px;
    padding: 16px 20px;
    margin-bottom: 24px;
    box-shadow: 0 10px 25px -5px rgba(15, 23, 42, 0.35), 0 8px 10px -6px rgba(15, 23, 42, 0.2);
    border: 1px solid #334155;
  }
  .action-bar-content {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    flex-wrap: wrap;
  }
  .action-info {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .action-badge {
    font-size: 11px;
    font-weight: 700;
    color: #38bdf8;
    background: rgba(56, 189, 248, 0.12);
    padding: 2px 8px;
    border-radius: 6px;
    display: inline-block;
    width: fit-content;
  }
  .action-title {
    font-size: 15px;
    font-weight: 800;
    color: #ffffff;
  }
  .action-buttons {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
  }
  .btn-action {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 9px 18px;
    font-size: 13px;
    font-weight: 700;
    font-family: inherit;
    border-radius: 8px;
    cursor: pointer;
    border: none;
    transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  }
  .btn-pdf {
    background: linear-gradient(135deg, #10b981 0%, #059669 100%);
    color: #ffffff;
    box-shadow: 0 4px 14px rgba(16, 185, 129, 0.35);
  }
  .btn-pdf:hover {
    background: linear-gradient(135deg, #059669 0%, #047857 100%);
    transform: translateY(-1px);
    box-shadow: 0 6px 18px rgba(16, 185, 129, 0.45);
  }
  .btn-print {
    background: #2563eb;
    color: #ffffff;
  }
  .btn-print:hover {
    background: #1d4ed8;
    transform: translateY(-1px);
  .btn-close {
    background: transparent;
    color: #94a3b8;
    border: 1px solid #334155;
  }
  .btn-close:hover {
    background: rgba(239, 68, 68, 0.15);
    color: #f87171;
    border-color: #ef4444;
  }
  .action-tip {
    margin-top: 12px;
    padding-top: 10px;
    border-top: 1px solid #1e293b;
    font-size: 12px;
    color: #cbd5e1;
    line-height: 1.5;
  }
  .action-tip strong {
    color: #38bdf8;
  }

  /* ─── ورقة التقرير الرسمية ─── */
  .report-paper {
    background: #ffffff;
    border-radius: 12px;
    padding: 36px 40px;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05), 0 2px 4px -2px rgba(0, 0, 0, 0.05);
    border: 1px solid #e2e8f0;
  }

  .header { display: flex; align-items: center; justify-content: space-between; border-bottom: 3px solid #f59e0b; padding-bottom: 16px; margin-bottom: 24px; }
  .header-right h1 { font-size: 24px; font-weight: 900; color: #111827; }
  .header-right .org { font-size: 13px; color: #6b7280; margin-top: 3px; font-weight: 600; }
  .header-left { text-align: left; font-size: 12px; color: #9ca3af; }
  .header-left .date { font-weight: 700; color: #374151; font-size: 13px; }

  .summary-grid { display: flex; gap: 12px; margin-bottom: 24px; flex-wrap: wrap; }
  .summary-card { flex: 1; min-width: 120px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 14px; text-align: center; }
  .summary-value { display: block; font-size: 20px; font-weight: 900; color: #111827; }
  .summary-label { display: block; font-size: 11px; color: #6b7280; margin-top: 3px; font-weight: 600; }

  h2 { font-size: 16px; font-weight: 800; margin: 26px 0 10px; color: #1e293b; border-bottom: 2px solid #e2e8f0; padding-bottom: 6px; }
  p.sub { color: #64748b; font-size: 12px; margin: 0 0 12px; font-weight: 600; }

  table { width: 100%; border-collapse: collapse; font-size: 12px; margin-bottom: 12px; }
  thead { display: table-header-group; }
  tr { page-break-inside: avoid; break-inside: avoid; }
  th, td { border: 1px solid #cbd5e1; padding: 8px 10px; text-align: right; }
  /* بلا letter-spacing: يفصل الحروف العربية عن بعضها في ملفات PDF */
  th { background: #f59e0b; color: #ffffff; font-weight: 800; font-size: 11px; }
  tr.even td { background: #ffffff; }
  tr.odd td { background: #fffbeb; }

  /* ─── شارات الحالة الملونة بالجدول ─── */
  .badge {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 9999px;
    font-size: 10px;
    font-weight: 700;
    white-space: nowrap;
  }
  .badge-suspended { background: #fee2e2; color: #991b1b; border: 1px solid #fca5a5; }
  .badge-paid { background: #dcfce7; color: #166534; border: 1px solid #86efac; }
  .badge-pending { background: #fef3c7; color: #92400e; border: 1px solid #fde68a; }
  .badge-doubled { background: #ffedd5; color: #9a3412; border: 1px solid #fed7aa; }
  .badge-cancelled { background: #f1f5f9; color: #475569; border: 1px solid #cbd5e1; }

  /* ─── قسم التوقيعات والاعتماد الرسمي ─── */
  .signatures {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 16px;
    margin-top: 36px;
    padding-top: 20px;
    border-top: 1px dashed #cbd5e1;
    page-break-inside: avoid;
    break-inside: avoid;
  }
  .sig-box { text-align: center; }
  .sig-role { font-size: 11px; font-weight: 800; color: #334155; margin-bottom: 24px; }
  .sig-line { font-size: 10px; color: #94a3b8; }

  .footer { margin-top: 32px; border-top: 1px solid #e2e8f0; padding-top: 14px; display: flex; justify-content: space-between; font-size: 11px; color: #94a3b8; }
  .footer .brand { font-weight: 700; color: #f59e0b; }

  @media print {
    html, body {
      padding: 0 !important;
      background: #ffffff !important;
      font-family: 'Cairo', system-ui, -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif !important;
      direction: rtl !important;
      text-align: right !important;
    }
    .no-print, .action-bar { display: none !important; }
    /* حشوة أمان صغيرة: محرك PDF يصوّر بلا حشوة، فيُقصّ الحرف الملاصق لحافة الصفحة */
    .report-paper { border: none !important; box-shadow: none !important; padding: 2px 8px 12px !important; border-radius: 0 !important; }
    .summary-card { break-inside: avoid; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    table { break-inside: auto; width: 100% !important; }
    tr { break-inside: avoid; page-break-inside: avoid; }
    th { -webkit-print-color-adjust: exact; print-color-adjust: exact; background-color: #f59e0b !important; color: #ffffff !important; }
    .badge { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .signatures { break-inside: avoid; }
    @page { size: A4 portrait; margin: 10mm 8mm; }
  }
</style>
</head>
<body>

<div class="action-bar no-print">
  <div class="action-bar-content">
    <div class="action-info">
      <span class="action-badge">📄 تقرير معتمد رسمي</span>
      <span class="action-title">${esc(documentTitle)}</span>
    </div>
    <div class="action-buttons">
      <button type="button" class="btn-action btn-pdf" onclick="saveAsPdf()" title="حفظ التقرير كملف PDF على جهازك">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
        <span>تحميل وحفظ كملف PDF</span>
      </button>
      <button type="button" class="btn-action btn-print" onclick="saveAsPdf()" title="طباعة فورية للتقرير">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 6 2 18 2 18 9"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/></svg>
        <span>طباعة</span>
      </button>
      <button type="button" class="btn-action btn-close" onclick="window.close()" title="إغلاق هذه النافذة">
        <span>إغلاق</span>
      </button>
    </div>
  </div>
  <div class="action-tip">
    💡 <strong>طريقة التنزيل كملف PDF:</strong> اضغط على زر <strong>«تحميل وحفظ كملف PDF»</strong> أعلاه، ثم اختر الوجهة <strong>(Save as PDF / حفظ بتنسيق PDF)</strong> واضغط حفظ، أو استخدم الاختصار <strong>Ctrl + P</strong>.
  </div>
</div>

<div class="report-paper">
  <div class="header">
    <div class="header-right">
      <h1>${esc(documentTitle)}</h1>
      <div class="org">جمعية أحلى شباب — إدارة الموارد البشرية</div>
    </div>
    <div class="header-left">
      <div class="date">${esc(dateStr)}</div>
      <div>${esc(timeStr)}</div>
    </div>
  </div>

  ${summaryHtml}
  ${body}

  <div class="signatures">
    <div class="sig-box">
      <div class="sig-role">إعداد: مسؤول الموارد البشرية</div>
      <div class="sig-line">التوقيع: ____________________</div>
    </div>
    <div class="sig-box">
      <div class="sig-role">مراجعة: الإدارة المالية</div>
      <div class="sig-line">التوقيع: ____________________</div>
    </div>
    <div class="sig-box">
      <div class="sig-role">اعتماد: المسؤول العام للنظام</div>
      <div class="sig-line">الختم والاعتماد: ____________</div>
    </div>
  </div>

  <div class="footer">
    <span>نظام إدارة الموارد البشرية — <span class="brand">أحلى شباب</span></span>
    <span>تم الإنشاء: ${esc(dateStr)} · ${esc(timeStr)}</span>
  </div>
</div>

<script>
  function saveAsPdf() {
    window.focus();
    try {
      window.print();
    } catch (e) {
      console.error(e);
    }
  }

  // انتظر تحميل الخطوط العربية تماماً قبل فتح حوار الطباعة التلقائي لمنع تشويه الحروف أو انعكاسها
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(function() {
      setTimeout(function() { saveAsPdf(); }, 400);
    }).catch(function() {
      setTimeout(function() { saveAsPdf(); }, 800);
    });
  } else {
    setTimeout(function() { saveAsPdf(); }, 800);
  }
</script>
</body>
</html>`;
}

/**
 * تصدير تقرير كملف PDF حقيقي دون فتح نوافذ HTML.
 */
export function printReport(sections: PrintableSection[], documentTitle: string, summary?: { label: string; value: string }[]): void {
  const html = generateReportHtml(sections, documentTitle, summary);
  void import('./pdfExport')
    .then(({ downloadHtmlAsPdf, pdfFileName }) =>
      downloadHtmlAsPdf(html, documentTitle, pdfFileName(`${documentTitle}_${new Date().toISOString().slice(0, 10)}`)),
    )
    .catch((err) => {
      console.error('Failed to export report PDF:', err);
    });
}

/** تنزيل التقرير كملف PDF. */
export function downloadReportHtml(sections: PrintableSection[], documentTitle: string, summary?: { label: string; value: string }[]): void {
  printReport(sections, documentTitle, summary);
}
