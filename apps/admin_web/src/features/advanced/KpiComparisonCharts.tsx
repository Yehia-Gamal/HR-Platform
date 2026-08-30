import { Download, TrendingUp } from 'lucide-react';
import { useMemo } from 'react';
import { AppBarChart } from '../../ui/charts/AppBarChart';
import { AppLineChart } from '../../ui/charts/AppLineChart';
import { AppRadarChart } from '../../ui/charts/AppRadarChart';
import { ChartCard } from '../../ui/charts/ChartCard';
import { buildComparisonCsv, deriveDeltas, deriveHistory, downloadCsv, toEvaluationsSeries, toRadarData, toScoreSeries, type CatalogInput } from './kpiHistory';

function fmtNum(v: number | null): string {
  return v == null ? '—' : new Intl.NumberFormat('ar-EG', { maximumFractionDigits: 1 }).format(v);
}

function deltaBadge(delta: number | null, invert: boolean): React.ReactNode {
  if (delta == null) return <span className="muted text-xs">—</span>;
  const good = invert ? delta < 0 : delta > 0;
  const cls =
    delta === 0
      ? 'bg-[var(--surface-muted)] text-[var(--text-muted)]'
      : good
        ? 'bg-[var(--success-soft)] text-[var(--success)]'
        : 'bg-[var(--danger-soft)] text-[var(--danger)]';
  const arrow = delta > 0 ? '▲' : delta < 0 ? '▼' : '•';
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-black ${cls}`}>
      {arrow} {fmtNum(Math.abs(delta))}
    </span>
  );
}

export function KpiComparisonCharts({ catalog }: { catalog: CatalogInput }) {
  const points = useMemo(() => deriveHistory(catalog?.cycles), [catalog?.cycles]);
  const deltas = useMemo(() => deriveDeltas(points), [points]);
  const scoreSeries = useMemo(() => toScoreSeries(points), [points]);
  const evalSeries = useMemo(() => toEvaluationsSeries(points), [points]);
  const radarData = useMemo(() => toRadarData(catalog), [catalog]);

  const hasData = points.length > 0;
  const hasScores = hasData && points.some((p) => p.averageScore != null);

  const rankDelta = (arr: (number | null)[]): number | null => {
    const vals = arr.filter((v): v is number => v != null);
    if (vals.length < 2) return null;
    return Math.round((vals[vals.length - 1] - vals[0]) * 100) / 100;
  };
  const overallScoreDelta = rankDelta(points.map((p) => p.averageScore));

  const exportCsv = () => {
    if (points.length === 0) return;
    downloadCsv('kpi-historical-comparison.csv', buildComparisonCsv(points));
  };

  return (
    <section className="space-y-5">
      {/* شريط ملخص + تصدير */}
      <div className="card flex flex-wrap items-center justify-between gap-4 p-5">
        <div className="flex items-center gap-3">
          <span className="grid size-11 place-items-center rounded-2xl bg-[var(--brand-primary-soft)] text-[var(--brand-primary)]">
            <TrendingUp className="size-5" aria-hidden="true" />
          </span>
          <div>
            <h2 className="text-lg font-black">المقارنة التاريخية لنتائج KPI</h2>
            <p className="muted text-sm">اتجاه متوسط الدرجات والإنجاز عبر دورات الأشهر السابقة.</p>
          </div>
        </div>
        <button className="btn-secondary" onClick={exportCsv} disabled={!hasData}>
          <Download className="size-4" aria-hidden="true" />
          تصدير CSV
        </button>
      </div>

      {!hasData ? (
        <div className="card p-8 text-center">
          <p className="font-black">لا توجد دورات سابقة للمقارنة</p>
          <p className="muted mt-1 text-sm">جهّز وافتح دورة شهر ليبدأ سجل المقارنة التاريخي.</p>
        </div>
      ) : (
        <>
          {/* اتجاه متوسط الدرجات */}
          <ChartCard title="اتجاه متوسط الدرجات الشهري" subtitle="متوسط النتائج النهائية لكل دورة شهرية — كلما ارتفع الخط زادت جودة الأداء." height={320}>
            <AppLineChart data={scoreSeries} lines={[{ key: 'score', label: 'متوسط الدرجة' }]} xKey="name" area />
          </ChartCard>

          {/* بطاقات مؤشرات الترند */}
          {overallScoreDelta != null ? (
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <div className="card p-5">
                <p className="muted text-xs font-bold">أول شهر في الفترة</p>
                <p className="mt-1 text-lg font-black">{points[0].monthLabel}</p>
                <p className="mt-1 text-2xl font-black">{fmtNum(points[0].averageScore)}</p>
              </div>
              <div className="card p-5">
                <p className="muted text-xs font-bold">أحدث شهر في الفترة</p>
                <p className="mt-1 text-lg font-black">{points[points.length - 1].monthLabel}</p>
                <p className="mt-1 text-2xl font-black">{fmtNum(points[points.length - 1].averageScore)}</p>
              </div>
              <div className="card p-5">
                <p className="muted text-xs font-bold">إجمالي التغيير في المتوسط</p>
                <div className="mt-1 text-2xl font-black">{fmtNum(overallScoreDelta)}</div>
                <div className="mt-1">{deltaBadge(overallScoreDelta, false)}</div>
              </div>
              <div className="card p-5">
                <p className="muted text-xs font-bold">أفضل شهر</p>
                <p className="mt-1 text-lg font-black">
                  {(() => {
                    const best = [...points].sort((a, b) => (b.averageScore ?? -1) - (a.averageScore ?? -1))[0];
                    return best && best.averageScore != null ? `${best.monthLabel}: ${fmtNum(best.averageScore)}` : '—';
                  })()}
                </p>
              </div>
            </div>
          ) : null}

          {/* تقييمات مكتملة + متأخرة */}
          <ChartCard title="الإنجاز والمتأخر شهريًا" subtitle="عدد التقييمات المدرجة في التقارير مقابل المتأخرة لكل دورة." height={320}>
            <AppBarChart
              data={evalSeries}
              bars={[
                { key: 'finalized', label: 'مكتملة' },
                { key: 'overdue', label: 'متأخرة' },
              ]}
              xKey="name"
            />
          </ChartCard>

          {/* رادار قالب المعايير */}
          {radarData.length > 0 ? (
            <ChartCard title="بنية قالب التقييم الرسمي" subtitle="وزن كل بند من بنود القالب مقابل درجته العظمى." height={360}>
              <AppRadarChart
                data={radarData}
                series={[{ key: 'weight', label: 'الوزن' }, ...(radarData.some((r) => r.maxScore > 0) ? [{ key: 'maxScore', label: 'الدرجة العظمى' }] : [])]}
              />
            </ChartCard>
          ) : null}

          {/* جدول التحوّل الشهري */}
          <div className="card overflow-hidden">
            <div className="flex items-center justify-between gap-3 p-4 pb-2">
              <h2 className="text-sm font-black">التحوّل شهر-إلى-شهر</h2>
              <span className="muted text-xs">التغير مقارنة بالشهر السابق في الفترة.</span>
            </div>
            <div className="overflow-x-auto">
              <table className="data-table min-w-[720px]">
                <thead>
                  <tr className="text-start">
                    <th className="p-3 text-start">الشهر</th>
                    <th className="p-3 text-start">المتوسط</th>
                    <th className="p-3 text-start">التغير</th>
                    <th className="p-3 text-start">مكتملة</th>
                    <th className="p-3 text-start">تغير الإنجاز</th>
                    <th className="p-3 text-start">متأخرة</th>
                    <th className="p-3 text-start">تغير المتأخر</th>
                    <th className="p-3 text-start">نسبة الإنجاز</th>
                  </tr>
                </thead>
                <tbody>
                  {deltas.map((d) => (
                    <tr key={d.monthLabel}>
                      <td className="p-3 font-bold">{d.monthLabel}</td>
                      <td className="p-3 font-bold">{fmtNum(d.averageScore)}</td>
                      <td className="p-3">{deltaBadge(d.averageScoreDelta, false)}</td>
                      <td className="p-3 font-bold">{fmtNum(d.finalized ?? 0)}</td>
                      <td className="p-3">{deltaBadge(d.finalizedDelta, false)}</td>
                      <td className="p-3 font-bold">{fmtNum(d.overdue ?? 0)}</td>
                      <td className="p-3">{deltaBadge(d.overdueDelta, true)}</td>
                      <td className="p-3 font-bold">{d.completionRate != null ? `${d.completionRate}%` : '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
      {hasData && !hasScores ? (
        <p className="muted p-4 text-center text-sm">لا توجد درجات نهائية محسوبة بعد في الدورات المعروضة — ستظهر بمجرد اكتمال التقييمات.</p>
      ) : null}
    </section>
  );
}
