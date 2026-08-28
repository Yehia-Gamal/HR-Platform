import { BarChart2, Gauge, TrendingUp, TrendingDown, Minus } from 'lucide-react';
import { useMemo } from 'react';
import { AppBarChart } from '../../ui/charts/AppBarChart';
import { AppLineChart } from '../../ui/charts/AppLineChart';
import { ChartCard } from '../../ui/charts/ChartCard';
import { MetricCard } from '../../ui/MetricCard';
import type { KpiEvaluationSummary } from '@ahla/shared-contracts';
import { computePeriodComparison, prepareTrendData, type KpiCycleSnapshot } from './useKpiHistory';

interface KpiComparisonChartsProps {
  currentEvaluations: KpiEvaluationSummary[];
  previousEvaluations: KpiEvaluationSummary[];
  cycles: KpiCycleSnapshot[];
  selectedPeriod?: string;
  onPeriodChange?: (period: string) => void;
}

export function KpiComparisonCharts({ currentEvaluations, previousEvaluations, cycles, selectedPeriod, onPeriodChange }: KpiComparisonChartsProps) {
  const comparison = useMemo(() => computePeriodComparison(currentEvaluations, previousEvaluations), [currentEvaluations, previousEvaluations]);

  const trendData = useMemo(() => prepareTrendData(cycles), [cycles]);

  const periodOptions = useMemo(
    () =>
      cycles
        .slice()
        .sort((a, b) => b.periodMonth.localeCompare(a.periodMonth))
        .map((c) => c.periodMonth),
    [cycles],
  );

  const { overall, byCriterion, distribution } = comparison;

  return (
    <div className="space-y-6" dir="rtl">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold text-[var(--text-primary)]">مقارنة الأداء التاريخي</h2>
          <p className="text-sm text-[var(--text-muted)]">الدورة الحالية مقابل الدورة السابقة — تفصيل حسب المعايير والتوجه الزمني</p>
        </div>
        <select className="input w-auto" value={selectedPeriod ?? ''} onChange={(e) => onPeriodChange?.(e.target.value)} aria-label="اختر الدورة للمقارنة">
          <option value="">— اختر دورة سابقة للمقارنة —</option>
          {periodOptions.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
      </div>

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-label="مؤشرات الملخص">
        <MetricCard
          label="متوسط الدورة الحالية"
          value={overall.currentAvg.toFixed(1)}
          icon={Gauge}
          trend={overall.delta >= 0 ? `+${overall.delta.toFixed(1)}` : `${overall.delta.toFixed(1)}`}
        />
        <MetricCard label="متوسط الدورة السابقة" value={overall.previousAvg.toFixed(1)} icon={BarChart2} />
        <MetricCard label="التقييمات الحالية" value={overall.currentCount} icon={BarChart2} />
        <MetricCard label="التقييمات السابقة" value={overall.previousCount} icon={BarChart2} />
      </section>

      <section className="grid gap-6 lg:grid-cols-2" aria-label="مقارنة تفصيلية">
        <ChartCard title="مقارنة المتوسط حسب المعيار" subtitle="الفروقات بين الدورتين">
          <AppBarChart
            data={byCriterion.map((c) => ({
              name: c.code,
              الحالي: Number(c.currentAvg.toFixed(1)),
              السابق: Number(c.previousAvg.toFixed(1)),
            }))}
            bars={[
              { key: 'الحالي', label: 'الدورة الحالية', color: 'var(--brand-primary)' },
              { key: 'السابق', label: 'الدورة السابقة', color: 'var(--text-muted)' },
            ]}
            xKey="name"
            height={320}
          />
        </ChartCard>

        <ChartCard title="توزيع الدرجات" subtitle="عدد التقييمات في كل نطاق">
          <AppBarChart
            data={distribution.current.map((d, i) => ({
              range: d.range,
              الحالي: d.count,
              السابق: distribution.previous[i]?.count ?? 0,
            }))}
            bars={[
              { key: 'الحالي', label: 'الحالية', color: 'var(--brand-primary)' },
              { key: 'السابق', label: 'السابقة', color: 'var(--text-muted)' },
            ]}
            xKey="range"
            height={320}
            horizontal
          />
        </ChartCard>
      </section>

      <section className="grid gap-6 lg:grid-cols-2" aria-label="الاتجاه الزمني">
        <ChartCard title="تطور المتوسط التاريخي" subtitle="آخر 6 دورات">
          <AppLineChart
            data={trendData}
            lines={[{ key: 'averageScore', label: 'متوسط الدرجة', color: 'var(--brand-primary)' }]}
            xKey="period"
            height={300}
            area
            curved
          />
        </ChartCard>

        <ChartCard title="معدل الإتمام" subtitle="نسبة المدرجة في التقرير الشهري">
          <AppLineChart
            data={trendData}
            lines={[{ key: 'completionRate', label: 'معدل الإتمام %', color: 'var(--success)' }]}
            xKey="period"
            height={300}
            curved
          />
        </ChartCard>
      </section>

      <section aria-label="تفصيل المعايير">
        <h3 className="text-lg font-bold mb-4 text-[var(--text-primary)]">تفصيل الفروقات حسب المعيار</h3>
        <div className="overflow-x-auto">
          <table className="w-full text-sm" role="table">
            <thead>
              <tr className="border-b border-[var(--border)] text-[var(--text-muted)]">
                <th className="text-right py-2 px-3 font-bold">المعيار</th>
                <th className="text-center py-2 px-3 font-bold">الحالية</th>
                <th className="text-center py-2 px-3 font-bold">السابقة</th>
                <th className="text-center py-2 px-3 font-bold">الفرق</th>
                <th className="text-center py-2 px-3 font-bold">الاتجاه</th>
              </tr>
            </thead>
            <tbody>
              {byCriterion.map((c) => (
                <tr key={c.code} className="border-b border-[var(--border)] hover:bg-[var(--surface-muted)]">
                  <td className="py-2 px-3 font-medium text-[var(--text-primary)]">{c.code}</td>
                  <td className="text-center py-2 px-3">{c.currentAvg.toFixed(1)}</td>
                  <td className="text-center py-2 px-3 text-[var(--text-muted)]">{c.previousAvg.toFixed(1)}</td>
                  <td className="text-center py-2 px-3 font-bold">
                    {c.delta >= 0 ? '+' : ''}
                    {c.delta.toFixed(1)}
                  </td>
                  <td className="text-center py-2 px-3">
                    {c.delta > 0.5 ? (
                      <TrendingUp className="size-5 text-[var(--success)] mx-auto" aria-label="تحسن" />
                    ) : c.delta < -0.5 ? (
                      <TrendingDown className="size-5 text-[var(--danger)] mx-auto" aria-label="تراجع" />
                    ) : (
                      <Minus className="size-5 text-[var(--text-muted)] mx-auto" aria-label="ثابت" />
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
