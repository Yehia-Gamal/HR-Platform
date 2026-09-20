import { AlertTriangle, Ban, CheckCircle2, Coins, Flame, ShieldAlert, XCircle } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { ChartCard } from '../../ui/charts/ChartCard';
import { AppPieChart } from '../../ui/charts/AppPieChart';
import { AppBarChart } from '../../ui/charts/AppBarChart';
import { AppLineChart } from '../../ui/charts/AppLineChart';
import { usePenaltyDashboard } from './usePenaltyDashboard';

const _STATUS_ICONS: Record<string, typeof CheckCircle2> = {
  pending_payment: AlertTriangle,
  paid: CheckCircle2,
  doubled: ShieldAlert,
  suspended: Ban,
  cancelled: XCircle,
};

const STATUS_COLORS: Record<string, string> = {
  pending_payment: '#f59e0b',
  paid: '#10b981',
  doubled: '#f97316',
  suspended: '#ef4444',
  cancelled: '#6b7280',
};

export function PenaltyDashboardPage() {
  const { stats, isLoading, isError, error, refetch, fmt } = usePenaltyDashboard();

  if (isError) return <ErrorState description={safeErrorMessage(error)} onRetry={() => void refetch()} />;
  if (isLoading) return <ListSkeleton rows={4} label="جارٍ تحميل الإحصائيات…" />;
  if (!stats || stats.total === 0) return <EmptyState title="لا توجد إحصائيات" description="لم تُسجَّل أي غرامات فورية بعد." />;

  const statusPieData = Object.entries(stats.byStatus).map(([key, v]) => ({
    name: v.label,
    value: v.count,
    color: STATUS_COLORS[key],
  }));

  const deptBarData = stats.byDepartment.map((d) => ({
    name: d.name,
    العدد: d.count,
    المبلغ: d.amount,
  }));

  const dateLineData = stats.byDate.map((d) => ({
    name: d.name,
    العدد: d.count,
    المدفوع: d.paid,
    المعلق: d.pending,
  }));

  return (
    <div className="space-y-5">
      <PageHeader eyebrow="الموارد البشرية" title="لوحة إحصائيات الغرامات الفورية" description="نظرة شاملة على أداء الحضور والغرامات واتجاهات السداد." />

      {/* ─── بطاقات الإجماليات ─────────────────────────────────────── */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          icon={<Coins className="size-5" />}
          label="إجمالي الغرامات"
          value={stats.total.toString()}
          sub={`${fmt(stats.totalAmount)}`}
          color="text-blue-600 dark:text-blue-400"
          bg="bg-blue-500/10"
        />
        <StatCard
          icon={<AlertTriangle className="size-5" />}
          label="بانتظار السداد"
          value={(stats.byStatus.pending_payment?.count ?? 0).toString()}
          sub={fmt(stats.byStatus.pending_payment?.amount ?? 0)}
          color="text-amber-600 dark:text-amber-400"
          bg="bg-amber-500/10"
        />
        <StatCard
          icon={<ShieldAlert className="size-5" />}
          label="مضاعفة / معلّقة"
          value={((stats.byStatus.doubled?.count ?? 0) + (stats.byStatus.suspended?.count ?? 0)).toString()}
          sub={fmt((stats.byStatus.doubled?.amount ?? 0) + (stats.byStatus.suspended?.amount ?? 0))}
          color="text-red-600 dark:text-red-400"
          bg="bg-red-500/10"
        />
        <StatCard
          icon={<CheckCircle2 className="size-5" />}
          label="مدفوعة"
          value={(stats.byStatus.paid?.count ?? 0).toString()}
          sub={fmt(stats.byStatus.paid?.amount ?? 0)}
          color="text-emerald-600 dark:text-emerald-400"
          bg="bg-emerald-500/10"
        />
      </div>

      {/* ─── مخططات ─────────────────────────────────────────────────── */}
      <div className="grid gap-5 lg:grid-cols-2">
        <ChartCard title="توزيع الحالات" subtitle="عدد الغرامات حسب الحالة">
          <AppPieChart data={statusPieData} donut height={280} />
        </ChartCard>

        <ChartCard title="الغرامات حسب الإدارة" subtitle="أعلى 10 إدارات بعدد الغرامات">
          <AppBarChart data={deptBarData} bars={[{ key: 'العدد', label: 'العدد', color: 'var(--brand-primary)' }]} horizontal height={280} />
        </ChartCard>
      </div>

      <ChartCard title="اتجاه الغرامات اليومية" subtitle="آخر 30 يوم">
        <AppLineChart
          data={dateLineData}
          lines={[
            { key: 'العدد', label: 'الإجمالي', color: 'var(--brand-primary)' },
            { key: 'المدفوع', label: 'مدفوعة', color: 'var(--success)' },
            { key: 'المعلق', label: 'معلّقة', color: 'var(--warning)' },
          ]}
          area
          height={320}
        />
      </ChartCard>

      {/* ─── الشرائح ────────────────────────────────────────────────── */}
      {stats.byTier.length > 0 && (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {stats.byTier.map((t) => (
            <div key={t.name} className="card p-4 flex items-center gap-3">
              <div className="rounded-xl p-2.5" style={{ backgroundColor: t.color + '18', color: t.color }}>
                <Flame className="size-4" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-baseline justify-between">
                  <span className="text-lg font-black font-mono" style={{ color: t.color }}>
                    {t.count}
                  </span>
                  <span className="text-xs font-mono font-bold text-[var(--text-secondary)]">{fmt(t.amount)}</span>
                </div>
                <p className="text-xs text-[var(--text-muted)]">{t.name}</p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function StatCard({ icon, label, value, sub, color, bg }: { icon: React.ReactNode; label: string; value: string; sub: string; color: string; bg: string }) {
  return (
    <div className="card p-4">
      <div className="flex items-center gap-3">
        <div className={`rounded-xl ${bg} p-2.5 ${color}`}>{icon}</div>
        <div className="flex-1 min-w-0">
          <p className="text-[11px] text-[var(--text-muted)] font-medium">{label}</p>
          <div className="flex items-baseline gap-2">
            <span className={`text-2xl font-black font-mono ${color}`}>{value}</span>
            <span className="text-xs font-mono text-[var(--text-secondary)]">{sub}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
