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
 * طباعة تقرير PDF احترافي عبر نافذة طباعة المتصفح.
 * يدعم: عنوان فرعي، إجماليات، ألوان الصفوف، ترويسة branded.
 */
export function printReport(sections: PrintableSection[], documentTitle: string, summary?: { label: string; value: string }[]): void {
  const win = window.open('', '_blank', 'width=900,height=700');
  if (!win) return;

  const esc = (s: string): string => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  const tableHtml = (t: { headers: string[]; rows: string[][] }) => `
    <table>
      <thead><tr>${t.headers.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead>
      <tbody>
        ${t.rows.map((r, i) => `<tr class="${i % 2 === 0 ? 'even' : 'odd'}">${r.map((c) => `<td>${esc(c)}</td>`).join('')}</tr>`).join('\n')}
      </tbody>
    </table>`;

  const summaryHtml = summary && summary.length > 0
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
  const dateStr = now.toLocaleDateString('ar-EG', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
  const timeStr = now.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' });

  win.document.write(`<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8" />
<title>${esc(documentTitle)}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;900&display=swap');
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif; padding: 32px; color: #1f2937; line-height: 1.6; }

  .header { display: flex; align-items: center; justify-content: space-between; border-bottom: 3px solid #f59e0b; padding-bottom: 16px; margin-bottom: 24px; }
  .header-right h1 { font-size: 22px; font-weight: 900; color: #111827; }
  .header-right .org { font-size: 13px; color: #6b7280; margin-top: 2px; }
  .header-left { text-align: left; font-size: 12px; color: #9ca3af; }
  .header-left .date { font-weight: 700; color: #374151; }

  .summary-grid { display: flex; gap: 12px; margin-bottom: 24px; flex-wrap: wrap; }
  .summary-card { flex: 1; min-width: 120px; background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 12px; text-align: center; }
  .summary-value { display: block; font-size: 20px; font-weight: 900; color: #111827; }
  .summary-label { display: block; font-size: 11px; color: #6b7280; margin-top: 2px; }

  h2 { font-size: 16px; font-weight: 700; margin: 28px 0 10px; color: #374151; border-bottom: 2px solid #e5e7eb; padding-bottom: 6px; }
  p.sub { color: #6b7280; font-size: 12px; margin: 0 0 10px; }

  table { width: 100%; border-collapse: collapse; font-size: 12px; margin-bottom: 8px; }
  th, td { border: 1px solid #d1d5db; padding: 8px 10px; text-align: right; }
  th { background: #f59e0b; color: #fff; font-weight: 700; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; }
  tr.even td { background: #fff; }
  tr.odd td { background: #fefce8; }

  .footer { margin-top: 32px; border-top: 1px solid #e5e7eb; padding-top: 12px; display: flex; justify-content: space-between; font-size: 11px; color: #9ca3af; }
  .footer .brand { font-weight: 700; color: #f59e0b; }

  @media print {
    body { padding: 20px; }
    .summary-card { break-inside: avoid; }
    table { break-inside: auto; }
    tr { break-inside: avoid; }
  }
</style>
</head>
<body>
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

<div class="footer">
  <span>نظام إدارة الموارد البشرية — <span class="brand">أحلى شباب</span></span>
  <span>تم الإنشاء: ${esc(dateStr)} · ${esc(timeStr)}</span>
</div>
<script>window.onload = function(){ window.focus(); window.print(); };</script>
</body>
</html>`);
  win.document.close();
}
