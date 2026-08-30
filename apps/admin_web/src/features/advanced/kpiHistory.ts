import type { KpiAdminCatalog } from '@ahla/shared-contracts';

interface CycleLike {
  periodMonth?: string;
  status?: string;
  evaluations?: number;
  finalized?: number;
  overdue?: number;
  averageScore?: number | null;
}

/** صفّ زمني مبسّط لدورة KPI — لبنة مقارنة إحصائية بين الأشهر */
export interface KpiHistoryPoint {
  /** key زمني ثابت للترتيب (YYYY-MM) */
  monthKey: string;
  /** تسمية عربية للشهر (مثال: "يوليو 2026") */
  monthLabel: string;
  /** متوسط الدرجات للدورة (قد يكون فارغًا) */
  averageScore: number | null;
  /** عدد التقييمات المدرجة في التقرير */
  finalized: number;
  /** إجمالي التقييمات */
  evaluations: number;
  /** المتأخرة */
  overdue: number;
  /** نسبة الإنجاز ٪ */
  completionRate: number | null;
  /** تسمية حالة الدورة */
  status: string;
}

/** تنسيق شهر عربي قصير من تاريخ YYYY-MM-DD */
export function formatMonthLabel(iso: string): string {
  const d = new Date(`${iso.slice(0, 7)}-01T00:00:00`);
  if (Number.isNaN(d.getTime())) return iso.slice(0, 7);
  return new Intl.DateTimeFormat('ar-EG', { month: 'short', year: 'numeric' }).format(d);
}

/** تحويل صفوف catalog.cycles إلى سلسلة زمنية مرتبة تصاعديًا حسب الشهر */
export function deriveHistory(cycles: CycleLike[] | null | undefined): KpiHistoryPoint[] {
  const groups = new Map<string, KpiHistoryPoint>();
  for (const cycle of cycles ?? []) {
    const monthKey = (cycle.periodMonth ?? '').slice(0, 7);
    if (!monthKey) continue;
    const existing = groups.get(monthKey);
    const score = existing?.averageScore ?? cycle.averageScore ?? null;
    const finalized = (existing?.finalized ?? 0) + (cycle.finalized ?? 0);
    const evaluations = (existing?.evaluations ?? 0) + (cycle.evaluations ?? 0);
    const overdue = (existing?.overdue ?? 0) + (cycle.overdue ?? 0);
    groups.set(monthKey, {
      monthKey,
      monthLabel: formatMonthLabel(monthKey),
      averageScore: score,
      finalized,
      evaluations,
      overdue,
      completionRate: evaluations > 0 ? Math.round((finalized / evaluations) * 1000) / 10 : null,
      status: cycle.status ?? '',
    });
  }
  return [...groups.values()].sort((a, b) => (a.monthKey < b.monthKey ? -1 : a.monthKey > b.monthKey ? 1 : 0));
}

/** صف تحوّل شهر-إلى-شهر */
export interface KpiDeltaRow {
  monthLabel: string;
  averageScore: number | null;
  averageScoreDelta: number | null;
  finalized: number;
  finalizedDelta: number | null;
  overdue: number;
  overdueDelta: number | null;
  completionRate: number | null;
}

/** حساب التحوّل بين كل شهر وسابقه */
export function deriveDeltas(points: KpiHistoryPoint[]): KpiDeltaRow[] {
  return points.map((p, i) => {
    const prev = i > 0 ? points[i - 1] : null;
    const scoreDelta = p.averageScore != null && prev?.averageScore != null ? Math.round((p.averageScore - prev.averageScore) * 100) / 100 : null;
    const finDelta = prev ? p.finalized - prev.finalized : null;
    const overDelta = prev ? p.overdue - prev.overdue : null;
    return {
      monthLabel: p.monthLabel,
      averageScore: p.averageScore,
      averageScoreDelta: scoreDelta,
      finalized: p.finalized,
      finalizedDelta: finDelta,
      overdue: p.overdue,
      overdueDelta: overDelta,
      completionRate: p.completionRate,
    };
  });
}

/** سلسلة بيانات شارت متوسط الدرجات */
export function toScoreSeries(points: KpiHistoryPoint[]): Record<string, unknown>[] {
  return points.map((p) => ({ name: p.monthLabel, score: p.averageScore }));
}

/** سلسلة بيانات شارت التقييمات (مكتملة + متأخرة) */
export function toEvaluationsSeries(points: KpiHistoryPoint[]): Record<string, unknown>[] {
  return points.map((p) => ({ name: p.monthLabel, finalized: p.finalized, overdue: p.overdue }));
}

/** ملف CSV للمقارنة الشهرية */
export function buildComparisonCsv(points: KpiHistoryPoint[]): string {
  const header = 'الشهر,متوسط الدرجات,المدرجة,المتأخرة,نسبة الإنجاز,الحالة';
  const rows = points.map((p) =>
    [p.monthLabel, p.averageScore ?? '', p.finalized, p.overdue, p.completionRate != null ? `${p.completionRate}%` : '', p.status]
      .map((v) => `"${String(v ?? '').replaceAll('"', '""')}"`)
      .join(','),
  );
  return [header, ...rows].join('\n');
}

/** استخراج معايير القالب الرسمي النشط لمخطط الرادار */
export function toRadarData(catalog: Pick<KpiAdminCatalog, 'templates'> | null | undefined): { subject: string; maxScore: number; weight: number }[] {
  const template = (catalog?.templates ?? []).find((t) => t.officialCode === 'OFFICIAL_KPI_100') ?? (catalog?.templates ?? [])[0];
  if (!template) return [];
  return template.criteria.map((c) => ({
    subject: c.name,
    maxScore: c.maxScore,
    weight: c.weight,
  }));
}

/** قائمة أزرار CSV — مساعدة للتصدير */
export function downloadCsv(filename: string, csv: string) {
  const link = document.createElement('a');
  link.href = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' }));
  link.download = filename;
  link.click();
  URL.revokeObjectURL(link.href);
}

/** مدخلات لوحة المقارنة — ملائم لصنف KpiAdminCatalog */
export interface CatalogInput {
  cycles: CycleLike[];
  templates: KpiAdminCatalog['templates'];
}
