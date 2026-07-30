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

export function AnalyticsDashboardPage() {
  const query = useAnalyticsDashboard();
  const data = query.data;

  return (
    <div className="space-y-5">
      <PageHeader eyebrow="التقارير" title="لوحة التحليلات" description="نظرة شاملة على الأداء التشغيلي" />

      {query.isError ? (
        <ErrorState title="تعذر تحميل التحليلات" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading ? (
        <MetricSkeletonRow count={4} />
      ) : data ? (
        <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
          <ChartCard title="حركة الطلبات الشهرية" subtitle="معتمد / مرفوض / معلق">
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
