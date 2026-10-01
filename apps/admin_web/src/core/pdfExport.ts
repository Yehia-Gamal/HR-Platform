/**
 * محرك موحّد لتحويل مستندات الطباعة (HTML) إلى ملفات PDF حقيقية.
 *
 * كل تقارير المنظومة كانت تفتح نافذة طباعة أو تُنزّل ملف HTML. هنا يُرسم المستند
 * نفسه (بقالبه وخطوطه) في إطار مخفي ويُصوَّر ثم يُقسَّم إلى صفحات A4:
 *  • الاتجاه من @page في المستند (landscape/portrait).
 *  • القطع بين صفوف الجداول وحدود الكتل فقط — لا يُشطر صف بين صفحتين.
 *  • رأس الجدول يتكرر أعلى كل صفحة تبدأ داخل جسم جدول.
 *  • .page-break يبدأ صفحة جديدة، وكتل break-inside: avoid تنتقل كاملة.
 *  • أزرار الإجراءات (.no-print / .action-bar) والسكربتات لا تدخل الملف.
 * لماذا تصوير لا نص PDF: مكتبات نص PDF لا تُشكّل الحروف العربية ولا تعكس الاتجاه.
 * المكتبات تُحمَّل عند التصدير فقط (chunk «pdf-vendor»).
 */

export type PdfOrientation = 'portrait' | 'landscape';

export interface PdfPageImage {
  dataUrl: string;
  /** ارتفاع الصورة على الصفحة بالمليمتر (العرض = عرض المحتوى). */
  heightMm: number;
  orientation: PdfOrientation;
}

const MARGIN_MM = 8;
const PX_PER_MM = 96 / 25.4;
const SCALE = 2;
const JPEG_QUALITY = 0.9;

type Html2Canvas = (element: HTMLElement, options?: Record<string, unknown>) => Promise<HTMLCanvasElement>;
type JsPdfModule = typeof import('jspdf');
type JsPdfDoc = InstanceType<JsPdfModule['jsPDF']>;

function pageDims(orientation: PdfOrientation) {
  const wMm = orientation === 'landscape' ? 297 : 210;
  const hMm = orientation === 'landscape' ? 210 : 297;
  const contentWmm = wMm - 2 * MARGIN_MM;
  const contentHmm = hMm - 2 * MARGIN_MM;
  return {
    wMm,
    hMm,
    contentWmm,
    widthPx: Math.round(contentWmm * PX_PER_MM),
    pageHeightPx: Math.floor(contentHmm * PX_PER_MM),
  };
}

/** الاتجاه من قاعدة @page في المستند؛ الافتراضي عمودي. */
export function detectOrientation(html: string): PdfOrientation {
  const m = /@page\s*{[^}]*size\s*:\s*([^;}]*)/i.exec(html);
  return m && /landscape/i.test(m[1]) ? 'landscape' : 'portrait';
}

function resolveJsPdf(mod: any): any {
  if (typeof mod?.jsPDF === 'function') return mod.jsPDF;
  if (typeof mod?.default?.jsPDF === 'function') return mod.default.jsPDF;
  if (typeof mod?.default === 'function') return mod.default;
  if (typeof mod === 'function') return mod;
  return mod?.jsPDF || mod?.default?.jsPDF || mod?.default || mod;
}

function resolveHtml2Canvas(mod: any): Html2Canvas {
  if (typeof mod === 'function') return mod;
  if (typeof mod?.default === 'function') return mod.default;
  if (typeof mod?.default?.default === 'function') return mod.default.default;
  return (mod?.default || mod) as Html2Canvas;
}

async function loadLibs(): Promise<{ jspdf: any; html2canvas: Html2Canvas }> {
  const [jspdfModule, h2cModule] = await Promise.all([import('jspdf'), import('html2canvas')]);
  const html2canvas = resolveHtml2Canvas(h2cModule);
  const jsPdfClass = resolveJsPdf(jspdfModule);
  return { jspdf: { jsPDF: jsPdfClass }, html2canvas };
}

/**
 * يزيل السكربتات ويطبّق قواعد الطباعة على الشاشة ويخفي أزرار الإجراءات.
 * حشوة صغيرة حول المحتوى: ذيول الحروف العربية تتجاوز صندوق السطر الأخير قليلاً،
 * والتصوير يقطع عند حدود الجسم.
 */
function preparePrintableHtml(html: string, widthPx: number): string {
  const extra = `<style>
    .no-print, .action-bar { display: none !important; }
    html { margin: 0 !important; padding: 0 !important; background: #fff !important; }
    body { margin: 0 !important; padding: 4px 4px 12px !important; box-sizing: border-box !important; background: #fff !important; width: ${widthPx}px !important; }
  </style>`;
  const stripped = html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/@media\s+print\s*{/gi, '@media all {');
  return stripped.includes('</head>')
    ? stripped.replace(/<\/head>/i, `${extra}</head>`)
    : `${extra}${stripped}`;
}

/**
 * html2canvas يقيس خط الأساس للخطوط في المستند الرئيسي (لا في إطار المستند) بصورة
 * 1×1 يُفترض أنها inline، وTailwind preflight يجعل كل img «block» فيقع القياس سطراً
 * أسفل — فيُرسم كل نص منخفضاً نحو نصف ارتفاع الحرف (يلامس حدود الصفوف ويُقص في آخر
 * الصفحة). هذه القاعدة تعيد صورة القياس inline طوال عمل المُرسِم فقط.
 */
const METRICS_FIX_ID = 'pdf-export-font-metrics-fix';
let metricsFixUsers = 0;

function acquireMetricsFix(): void {
  metricsFixUsers += 1;
  if (document.getElementById(METRICS_FIX_ID)) return;
  const style = document.createElement('style');
  style.id = METRICS_FIX_ID;
  style.textContent = 'img[src^="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP"] { display: inline !important; }';
  document.head.appendChild(style);
}

function releaseMetricsFix(): void {
  metricsFixUsers = Math.max(0, metricsFixUsers - 1);
  if (metricsFixUsers === 0) document.getElementById(METRICS_FIX_ID)?.remove();
}

function relBox(el: Element, originTop: number) {
  const r = el.getBoundingClientRect();
  return { top: Math.floor(r.top - originTop), bottom: Math.ceil(r.bottom - originTop) };
}

/** مُرسِم يُعاد استخدامه لعدة مستندات بنفس الاتجاه (إطار واحد للدفعة كلها). */
export async function createPdfRenderer(orientation: PdfOrientation) {
  const { jspdf, html2canvas } = await loadLibs();
  const dims = pageDims(orientation);
  acquireMetricsFix();
  const iframe = document.createElement('iframe');
  iframe.setAttribute('aria-hidden', 'true');
  iframe.tabIndex = -1;
  iframe.style.cssText = `position:fixed;left:0;top:0;width:${dims.widthPx}px;height:2000px;opacity:0;pointer-events:none;z-index:-9999;border:0;`;
  document.body.appendChild(iframe);

  async function render(html: string): Promise<PdfPageImage[]> {
    const doc = iframe.contentDocument;
    if (!doc) throw new Error('pdf_render_frame_unavailable');
    doc.open();
    doc.write(preparePrintableHtml(html, dims.widthPx));
    doc.close();
    if (doc.fonts?.ready) {
      await Promise.race([doc.fonts.ready, new Promise((r) => setTimeout(r, 600))]);
    }
    const root = doc.body;
    iframe.style.height = `${root.scrollHeight + 40}px`;

    const originTop = root.getBoundingClientRect().top;
    const total = Math.ceil(root.scrollHeight);
    const candidates = new Set<number>([total]);
    root.querySelectorAll('tr').forEach((tr) => candidates.add(relBox(tr, originTop).bottom));
    root.querySelectorAll('body > *, .page > *, section, .card, .metric, h1, h2, h3, table').forEach((el) => {
      const b = relBox(el, originTop);
      candidates.add(b.top);
      candidates.add(b.bottom);
    });
    const avoidSplit: { top: number; bottom: number }[] = [];
    root.querySelectorAll('.closing, .signatures, .card').forEach((el) => {
      const b = relBox(el, originTop);
      avoidSplit.push(b);
      candidates.add(Math.max(0, b.top - 4));
    });
    const forced = Array.from(root.querySelectorAll('.page-break'))
      .map((el) => relBox(el, originTop).bottom)
      .filter((b) => b > 0 && b < total)
      .sort((a, b) => a - b);
    const tables = Array.from(root.querySelectorAll('table')).map((t) => {
      const thead = t.querySelector('thead');
      const tbody = t.querySelector('tbody');
      return {
        head: thead ? relBox(thead, originTop) : null,
        body: tbody ? relBox(tbody, originTop) : relBox(t, originTop),
      };
    });
    const sorted = Array.from(candidates).sort((a, b) => a - b);

    const canvas = await html2canvas(root, {
      scale: SCALE,
      backgroundColor: '#ffffff',
      logging: false,
      useCORS: true,
      windowWidth: dims.widthPx,
      width: dims.widthPx,
      height: total,
    });

    const pages: PdfPageImage[] = [];
    let start = 0;
    while (start < total - 1) {
      const table = tables.find((t) => t.head && start > t.body.top && start < t.body.bottom);
      const headH = table?.head ? table.head.bottom - table.head.top : 0;
      const limit = start + dims.pageHeightPx - headH;
      let cut: number;
      const forcedCut = forced.find((f) => f > start + 1 && f <= limit);
      if (forcedCut !== undefined) {
        cut = forcedCut;
      } else if (limit >= total) {
        cut = total;
      } else {
        cut = -1;
        for (const c of sorted) {
          if (c > start + 40 && c <= limit && !avoidSplit.some((a) => c > a.top + 1 && c < a.bottom - 1)) cut = Math.max(cut, c);
        }
        if (cut <= start) cut = limit;
      }
      const sliceH = cut - start;
      const outH = sliceH + headH;
      const out = document.createElement('canvas');
      out.width = Math.round(dims.widthPx * SCALE);
      out.height = Math.round(outH * SCALE);
      const ctx = out.getContext('2d');
      if (!ctx) throw new Error('pdf_canvas_unavailable');
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, out.width, out.height);
      if (table?.head) {
        ctx.drawImage(canvas, 0, table.head.top * SCALE, canvas.width, headH * SCALE, 0, 0, out.width, headH * SCALE);
      }
      ctx.drawImage(canvas, 0, start * SCALE, canvas.width, sliceH * SCALE, 0, headH * SCALE, out.width, sliceH * SCALE);
      pages.push({ dataUrl: out.toDataURL('image/jpeg', JPEG_QUALITY), heightMm: outH / PX_PER_MM, orientation });
      start = cut;
    }
    return pages;
  }

  function newDocument(title: string, author = 'منظومة أحلى شباب الإدارية'): JsPdfDoc {
    const JsPdfClass = resolveJsPdf(jspdf);
    const pdf = new JsPdfClass({ orientation, unit: 'mm', format: 'a4', compress: true });
    pdf.setProperties({ title, subject: title, creator: author, author });
    return pdf;
  }

  function addPages(pdf: JsPdfDoc, pages: PdfPageImage[], startsDocument: boolean): void {
    pages.forEach((p, i) => {
      if (!(startsDocument && i === 0)) pdf.addPage('a4', orientation);
      pdf.addImage(p.dataUrl, 'JPEG', MARGIN_MM, MARGIN_MM, dims.contentWmm, p.heightMm, undefined, 'FAST');
    });
  }

  function dispose(): void {
    iframe.remove();
    releaseMetricsFix();
  }

  return { render, newDocument, addPages, dispose };
}

export function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

/** اسم ملف آمن لأنظمة الملفات مع امتداد pdf. */
export function pdfFileName(title: string): string {
  const base = title.replace(/[\\/:*?"<>|]/g, '').replace(/\s+/g, '-').trim() || 'تقرير';
  return base.toLowerCase().endsWith('.pdf') ? base : `${base}.pdf`;
}

/** يحوّل مستند طباعة كاملاً إلى PDF وينزّله. */
export async function downloadHtmlAsPdf(html: string, title: string, filename = pdfFileName(title)): Promise<void> {
  const orientation = detectOrientation(html);
  const renderer = await createPdfRenderer(orientation);
  try {
    const pages = await renderer.render(html);
    const pdf = renderer.newDocument(title);
    renderer.addPages(pdf, pages, true);
    downloadBlob(pdf.output('blob'), filename);
  } finally {
    renderer.dispose();
  }
}
