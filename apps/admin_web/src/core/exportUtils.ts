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
 * طباعة تقرير PDF عبر نافذة طباعة المتصفح.
 * تُفتح نافذة جديدة بها HTML بسيط ثم تُستدعى الطباعة تلقائياً.
 */
export function printReport(sections: PrintableSection[], documentTitle: string): void {
  const win = window.open('', '_blank', 'width=900,height=700');
  if (!win) return;

  const esc = (s: string): string => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  const tableHtml = (t: { headers: string[]; rows: string[][] }) => `
    <table>
      <thead><tr>${t.headers.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead>
      <tbody>
        ${t.rows.map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join('')}</tr>`).join('\n')}
      </tbody>
    </table>`;

  const body = sections
    .map(
      (s) => `
        <h2>${esc(s.title)}</h2>
        ${s.subtitle ? `<p class="sub">${esc(s.subtitle)}</p>` : ''}
        ${tableHtml(s.table)}
      `,
    )
    .join('\n');

  win.document.write(`<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8" />
<title>${esc(documentTitle)}</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; padding: 24px; color: #1f2937; }
  h1 { font-size: 20px; margin-bottom: 4px; }
  h2 { font-size: 15px; margin: 22px 0 8px; color: #374151; border-bottom: 1px solid #e5e7eb; padding-bottom: 4px; }
  p.sub { color: #6b7280; font-size: 12px; margin: 0 0 8px; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  th, td { border: 1px solid #d1d5db; padding: 6px 8px; text-align: right; }
  th { background: #f3f4f6; font-weight: 700; }
  tr:nth-child(even) td { background: #fafafa; }
  .meta { color: #6b7280; font-size: 12px; margin-top: 20px; }
</style>
</head>
<body>
<h1>${esc(documentTitle)}</h1>
${body}
<p class="meta">نظام إدارة الموارد البشرية — أحلى شباب · ${esc(new Date().toLocaleDateString('ar-EG'))}</p>
<script>window.onload = function(){ window.focus(); window.print(); };</script>
</body>
</html>`);
  win.document.close();
}
