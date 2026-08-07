import {
  Activity,
  AlertTriangle,
  Bell,
  Clock,
  Database,
  RefreshCw,
  Shield,
  ShieldAlert,
  ShieldCheck,
  Timer,
  XCircle,
  CheckCircle2,
  Eye,
} from 'lucide-react';
import { useMemo } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { useAuth } from '../auth/AuthProvider';
import { safeErrorMessage } from '../../core/errorMapper';
import { useSystemHealth } from './useSystemHealth';
import { useSystemAlerts, useUpdateAlertStatus, type SystemAlert } from './useSystemAlerts';

// ─── مساعدات استخراج البيانات من JSON غير المنمّط ───
function num(v: unknown, fallback = 0): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

function fmtTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  try {
    return new Intl.DateTimeFormat('ar-EG', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(iso));
  } catch {
    return String(iso);
  }
}

// ─── بطاقة قسم مراقبة ───
function MonitorSection({
  title,
  icon: Icon,
  children,
}: {
  title: string;
  icon: React.ComponentType<{ className?: string }>;
  children: React.ReactNode;
}) {
  return (
    <article className="card p-5">
      <h3 className="mb-3 flex items-center gap-2 font-black">
        <Icon className="size-5 text-[var(--brand)]" aria-hidden="true" />
        {title}
      </h3>
      {children}
    </article>
  );
}

// ─── زر مراقبة صغير ───
function StatItem({ label, value, tone }: { label: string; value: number | string; tone?: 'ok' | 'warn' | 'danger' }) {
  const color = tone === 'danger' ? 'text-[var(--danger)]' : tone === 'warn' ? 'text-[var(--warning)]' : tone === 'ok' ? 'text-[var(--success)]' : '';
  return (
    <div className="flex items-center justify-between gap-2 rounded-lg bg-[var(--surface-muted)] px-3 py-2">
      <span className="muted text-sm">{label}</span>
      <span className={`text-lg font-black tabular-nums ${color}`}>{value}</span>
    </div>
  );
}

// ─── عنصر تنبيه ───
function AlertRow({ alert, onAcknowledge }: { alert: SystemAlert; onAcknowledge: (id: string) => void }) {
  const isP0 = alert.severity === 'P0';
  return (
    <div className={`flex items-start justify-between gap-3 rounded-xl border p-3 ${isP0 ? 'border-[var(--danger)]/30 bg-[var(--danger-soft)]/50' : 'border-[var(--border)] bg-[var(--surface-muted)]/40'}`}>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className={`inline-block rounded-full px-2 py-0.5 text-xs font-black ${isP0 ? 'bg-[var(--danger)] text-white' : 'bg-[var(--warning-soft)] text-[var(--warning)]'}`}>
            {alert.severity}
          </span>
          <p className="font-bold">{alert.title}</p>
          <span className="muted text-xs">×{alert.occurrences}</span>
        </div>
        {alert.detail && <p className="muted mt-1 text-xs">{alert.detail}</p>}
        <p className="muted mt-1 text-xs">
          {fmtTime(alert.last_seen_at)} · المصدر: {alert.source}
        </p>
      </div>
      <div className="flex flex-col items-end gap-1">
        {alert.status === 'open' && (
          <button
            type="button"
            className="rounded-lg border border-[var(--border)] px-2 py-1 text-xs font-bold hover:border-[var(--brand)] hover:text-[var(--brand)] transition-colors"
            onClick={() => onAcknowledge(alert.id)}
          >
            <Eye className="size-3.5 inline" aria-hidden="true" /> تأكيد
          </button>
        )}
        {alert.status === 'acknowledged' && (
          <span className="text-xs font-bold text-[var(--success)]">
            <CheckCircle2 className="size-3.5 inline" aria-hidden="true" /> مؤكد
          </span>
        )}
      </div>
    </div>
  );
}

// ─── الصفحة الرئيسية ───
export function ObservabilityDashboardPage() {
  const healthQuery = useSystemHealth();
  const alertsQuery = useSystemAlerts();
  const updateStatus = useUpdateAlertStatus();

  const health = healthQuery.data as Record<string, unknown> | undefined;
  const alerts = alertsQuery.data ?? [];

  const p0Count = alerts.filter((a) => a.severity === 'P0' && a.status !== 'resolved').length;
  const p1Count = alerts.filter((a) => a.severity === 'P1' && a.status !== 'resolved').length;

  // استخراج بيانات المراقبة من JSON
  const monitors = useMemo(() => {
    if (!health) return null;
    const queue = health.integration_queue as Record<string, unknown> | undefined;
    const notifs = health.notifications as Record<string, unknown> | undefined;
    const errors = health.errors as Record<string, unknown> | undefined;
    const security = health.security as Record<string, unknown> | undefined;
    const cronJobs = Array.isArray(health.cron) ? (health.cron as Array<Record<string, unknown>>) : [];
    return { queue, notifs, errors, security, cronJobs };
  }, [health]);

  const isRefreshing = healthQuery.isFetching || alertsQuery.isFetching;

  if (healthQuery.isError) {
    return <ErrorState title="تعذر تحميل لوحة المراقبة" description={safeErrorMessage(healthQuery.error)} onRetry={() => void healthQuery.refetch()} />;
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="لوحة مراقبة النظام"
        description="صحة المهام المجدولة، طوابير التكامل، الإشعارات، الأخطاء، والتنبيهات الأمنية."
        actions={
          <div className="flex items-center gap-3">
            {health?.generated_at && (
              <span className="muted text-xs">
                آخر تحديث: {fmtTime(health.generated_at as string)}
              </span>
            )}
            <button
              type="button"
              className="btn-secondary"
              disabled={isRefreshing}
              onClick={() => { void healthQuery.refetch(); void alertsQuery.refetch(); }}
            >
              <RefreshCw className={`size-4 ${isRefreshing ? 'animate-spin' : ''}`} aria-hidden="true" />
              تحديث
            </button>
          </div>
        }
      />

      {healthQuery.isLoading ? (
        <SkeletonCard className="h-64" />
      ) : null}

      {/* ─── بطاقات الصحة الإجمالية ─── */}
      <section className="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          label="تنبيهات حرجة (P0)"
          value={p0Count}
          hint={p0Count > 0 ? 'تحتاج تدخلاً فورياً' : 'لا توجد تنبيهات حرجة'}
          icon={ShieldAlert}
        />
        <MetricCard
          label="تنبيهات (P1)"
          value={p1Count}
          hint={p1Count > 0 ? 'تحتاج مراجعة' : 'لا توجد تنبيهات'}
          icon={AlertTriangle}
        />
        <MetricCard
          label="أخطاء آخر ساعة"
          value={monitors?.errors ? num(monitors.errors.errors_last_1h) : '—'}
          hint={monitors?.errors ? `${num(monitors.errors.fatal_last_1h)} حرجة` : undefined}
          icon={XCircle}
        />
        <MetricCard
          label="أحداث أمنية حرجة"
          value={monitors?.security ? num(monitors.security.critical_last_1h) : '—'}
          hint={monitors?.security ? `${num(monitors.security.high_last_1h)} عالية` : undefined}
          icon={Shield}
        />
      </section>

      {/* ─── التنبيهات المفتوحة ─── */}
      <section className="card p-5">
        <div className="mb-4 flex items-center justify-between">
          <h3 className="flex items-center gap-2 font-black">
            <Bell className="size-5 text-[var(--brand)]" aria-hidden="true" />
            التنبيهات المفتوحة
          </h3>
          {alertsQuery.isError && <ErrorBanner message={safeErrorMessage(alertsQuery.error)} />}
        </div>
        {alertsQuery.isLoading ? (
          <SkeletonCard className="h-24" />
        ) : alerts.length === 0 ? (
          <EmptyState title="لا توجد تنبيهات" description="النظام يعمل بسلاسة، لا تنبيهات مفتوحة." />
        ) : (
          <div className="space-y-2">
            {alerts.map((alert) => (
              <AlertRow key={alert.id} alert={alert} onAcknowledge={(id) => updateStatus.mutate({ alertId: id, status: 'acknowledged' })} />
            ))}
          </div>
        )}
      </section>

      {/* ─── أقسام المراقبة الأربعة ─── */}
      {monitors && (
        <section className="grid gap-5 xl:grid-cols-2">
          {/* طابور التكامل */}
          <MonitorSection title="طابور التكامل" icon={Database}>
            <div className="grid gap-2 sm:grid-cols-2">
              <StatItem label="معلّقة" value={num(monitors.queue?.pending)} />
              <StatItem label="فاشلة" value={num(monitors.queue?.failed)} tone="danger" />
              <StatItem label="حرف ميت" value={num(monitors.queue?.dead_letter)} tone="danger" />
              <StatItem label="متأخرة" value={num(monitors.queue?.overdue)} tone="warn" />
            </div>
          </MonitorSection>

          {/* الإشعارات */}
          <MonitorSection title="الإشعارات (24 ساعة)" icon={Bell}>
            <div className="grid gap-2 sm:grid-cols-2">
              <StatItem label="في الطابور" value={num(monitors.notifs?.queued)} tone="warn" />
              <StatItem label="مُسلَّمة" value={num(monitors.notifs?.delivered_24h)} tone="ok" />
              <StatItem label="فاشلة" value={num(monitors.notifs?.failed_24h)} tone="danger" />
              <StatItem label="عالقة" value={num(monitors.notifs?.stuck)} tone="danger" />
            </div>
          </MonitorSection>

          {/* الأخطاء */}
          <MonitorSection title="الأخطاء (آخر ساعة)" icon={XCircle}>
            <div className="grid gap-2 sm:grid-cols-2">
              <StatItem label="إجمالي الأخطاء" value={num(monitors.errors?.errors_last_1h)} tone="warn" />
              <StatItem label="حرجة" value={num(monitors.errors?.fatal_last_1h)} tone="danger" />
              <StatItem label="تحذيرات" value={num(monitors.errors?.warnings_last_1h)} />
            </div>
          </MonitorSection>

          {/* الأمان */}
          <MonitorSection title="الأمان (آخر ساعة)" icon={Shield}>
            <div className="grid gap-2 sm:grid-cols-2">
              <StatItem label="حرجة" value={num(monitors.security?.critical_last_1h)} tone="danger" />
              <StatItem label="عالية" value={num(monitors.security?.high_last_1h)} tone="warn" />
            </div>
          </MonitorSection>
        </section>
      )}

      {/* ─── صحة المهام المجدولة (pg_cron) ─── */}
      {monitors && monitors.cronJobs.length > 0 && (
        <section className="card overflow-hidden">
          <div className="border-b border-[var(--border)] p-5">
            <h3 className="flex items-center gap-2 font-black">
              <Clock className="size-5 text-[var(--brand)]" aria-hidden="true" />
              صحة المهام المجدولة
            </h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[600px] text-sm">
              <thead className="bg-[var(--surface-muted)] text-xs font-black">
                <tr>
                  <th className="p-3 text-start">المهمة</th>
                  <th className="p-3 text-start">آخر حالة</th>
                  <th className="p-3 text-start">آخر تشغيل</th>
                  <th className="p-3 text-start">الحالة</th>
                </tr>
              </thead>
              <tbody>
                {monitors.cronJobs.map((job, i) => {
                  const status = String(job.last_status ?? 'never_run');
                  const jobName = String(job.jobname ?? '—');
                  const lastRun = job.last_run ? fmtTime(String(job.last_run)) : '—';
                  const healthColor = status === 'succeeded' ? 'text-[var(--success)]' : status === 'failed' ? 'text-[var(--danger)]' : 'text-[var(--text-muted)]';
                  return (
                    <tr key={i} className="border-t border-[var(--border)]">
                      <td className="p-3 font-bold">{jobName}</td>
                      <td className={`p-3 font-bold ${healthColor}`}>{status}</td>
                      <td className="p-3 tabular-nums" dir="ltr">{lastRun}</td>
                      <td className="p-3">
                        {status === 'succeeded' ? (
                          <span className="inline-flex items-center gap-1 text-[var(--success)]"><ShieldCheck className="size-4" aria-hidden="true" /> سليم</span>
                        ) : status === 'failed' ? (
                          <span className="inline-flex items-center gap-1 text-[var(--danger)]"><XCircle className="size-4" aria-hidden="true" /> فاشل</span>
                        ) : (
                          <span className="muted">—</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>
      )}

      <p className="muted flex items-center gap-2 text-xs">
        <Timer className="size-4" aria-hidden="true" />
        تُحدّث اللوحة تلقائياً كل 30 ثانية.
      </p>
    </div>
  );
}
