import { useState } from 'react';
import { PageHeader } from '../../ui/PageHeader';
import { ErrorState } from '../../ui/ErrorState';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { safeErrorMessage } from '../../core/errorMapper';
import { ChartCard } from '../../ui/charts/ChartCard';
import { AppLineChart } from '../../ui/charts/AppLineChart';
import { AppBarChart } from '../../ui/charts/AppBarChart';
import { AppPieChart } from '../../ui/charts/AppPieChart';
import { AppRadarChart } from '../../ui/charts/AppRadarChart';
import { useAnalyticsDashboard } from './useAnalyticsDashboard';

type MonthsBack = 3 | 6 | 12;

const PERIOD_OPTIONS: { value: MonthsBack; label: string }[] = [
  { value: 3, label: '3 أشهر' },
  { value: 6, label: '6 أشهر' },
  { value: 12, label: 'سنة' },
];

export function AnalyticsDashboardPage() {
  const [monthsBack, setMonthsBack] = useState<MonthsBack>(6);
  const query = useAnalyticsDashboard(monthsBack);
  const data = query.data;

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="التقارير"
        title="لوحة التحليلات"
        description="نظرة شاملة على الأداء التشغيلي"
        actions={
          <div className="flex gap-1 rounded-xl border border-[var(--border)] p-1">
            {PERIOD_OPTIONS.map((opt) => (
              <button
                key={opt.value}
                type="button"
                onClick={() => setMonthsBack(opt.value)}
                className={`rounded-lg px-3 py-1.5 text-xs font-bold transition-colors ${
                  monthsBack === opt.value ? 'bg-[var(--brand-primary)] text-white' : 'text-[var(--text-muted)] hover:bg-[var(--surface-raised)]'
                }`}
              >
                {opt.label}
              </button>
            ))}
          </div>
        }
      />

      {query.isError ? (
        <ErrorState title="تعذر تحميل التحليلات" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading ? (
        <MetricSkeletonRow count={4} />
      ) : data ? (
        <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
          <ChartCard title="حركة الطلبات الشهرية" subtitle={`آخر ${monthsBack} أشهر — معتمد / مرفوض / معلق`}>
            <AppLineChart
              data={data.monthlyRequests}
              lines={[
                { key: 'approved', label: 'معتمد' },
                { key: 'rejected', label: 'مرفوض' },
                { key: 'pending', label: 'معلق' },
              ]}
              area
            />
          </ChartCard>

          <ChartCard title="توزيع الأقسام" subtitle="عدد الموظفين لكل قسم">
            <AppPieChart data={data.departmentDistribution} donut />
          </ChartCard>

          <ChartCard title="اتجاه الحضور الأسبوعي" subtitle="حاضر / متأخر / غائب">
            <AppBarChart
              data={data.attendanceTrend}
              bars={[
                { key: 'present', label: 'حاضر' },
                { key: 'late', label: 'متأخر' },
                { key: 'absent', label: 'غائب' },
              ]}
              stacked
            />
          </ChartCard>

          <ChartCard title="مؤشرات الأداء" subtitle="الفعلي مقابل المستهدف">
            <AppRadarChart
              data={data.kpiScores}
              series={[
                { key: 'actual', label: 'الفعلي' },
                { key: 'target', label: 'المستهدف' },
              ]}
            />
          </ChartCard>
        </div>
      ) : null}
    </div>
  );
}
