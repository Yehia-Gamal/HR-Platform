import {
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
  Activity,
  AlertOctagon,
  Ban,
} from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { safeErrorMessage } from '../../core/errorMapper';
import { useSystemHealth } from './useSystemHealth';
import { useSystemAlerts, useUpdateAlertStatus, useResolveAllAlerts, useAcknowledgeAllAlerts, type SystemAlert } from './useSystemAlerts';
import { useCronHealthSummary, useCronJobHealth, useObservabilityEvents } from './useCronHealth';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';

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
function MonitorSection({ title, icon: Icon, children }: { title: string; icon: React.ComponentType<{ className?: string }>; children: React.ReactNode }) {
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

// ─── أيقونة المصدر ───
function getSourceIcon(source: string) {
  if (source.includes('sec') || source.includes('auth')) return Shield;
  if (source.includes('cron') || source.includes('sched')) return Clock;
  if (source.includes('queue') || source.includes('integration')) return Database;
  return AlertTriangle;
}

// ─── عنصر تنبيه ───
function AlertRow({
  alert,
  onAcknowledge,
  onResolve,
  isPending,
}: {
  alert: SystemAlert;
  onAcknowledge: (id: string) => void;
  onResolve: (id: string) => void;
  isPending?: boolean;
}) {
  const isP0 = alert.severity === 'P0';
  const isResolved = alert.status === 'resolved';
  const isAck = alert.status === 'acknowledged';
  const SourceIcon = getSourceIcon(alert.source);

  return (
    <div
      className={`flex flex-col sm:flex-row sm:items-start justify-between gap-3 rounded-xl border p-3.5 transition-all ${
        isResolved
          ? 'border-emerald-500/20 bg-emerald-500/5 dark:bg-emerald-950/15 opacity-75'
          : isP0
            ? 'border-rose-500/30 bg-rose-500/10 dark:bg-rose-950/25 shadow-sm'
            : 'border-amber-500/30 bg-amber-500/10 dark:bg-amber-950/25'
      }`}
    >
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <span
            className={`inline-block rounded-full px-2.5 py-0.5 text-xs font-black shadow-xs ${
              isP0 ? 'bg-rose-600 text-white' : 'bg-amber-500 text-white'
            }`}
          >
            {alert.severity}
          </span>
          <p className="font-bold text-sm text-[var(--text-primary)]">{alert.title}</p>
          <span className="inline-flex items-center gap-1 rounded-md bg-[var(--surface-muted)] px-2 py-0.5 text-xs font-bold text-[var(--text-muted)]">
            <SourceIcon className="size-3" aria-hidden="true" />
            {alert.source}
          </span>
          <span className="rounded-full bg-black/10 dark:bg-white/10 px-2 py-0.5 text-xs font-bold text-[var(--text-muted)]">
            ×{alert.occurrences}
          </span>
        </div>
        {alert.detail && <p className="mt-1.5 text-xs text-[var(--text-muted)] leading-relaxed">{alert.detail}</p>}
        <div className="mt-2 flex flex-wrap items-center gap-3 text-xs text-[var(--text-muted)]">
          <span>آخر ظهور: {fmtTime(alert.last_seen_at)}</span>
          {alert.first_seen_at && alert.first_seen_at !== alert.last_seen_at && (
            <span>أول ظهور: {fmtTime(alert.first_seen_at)}</span>
          )}
        </div>
      </div>
      <div className="flex flex-wrap sm:flex-col items-end gap-1.5 shrink-0">
        {alert.status === 'open' && (
          <div className="flex items-center gap-1.5">
            <button
              type="button"
              disabled={isPending}
              className="inline-flex items-center gap-1 rounded-lg border border-[var(--border)] bg-[var(--surface)] px-2.5 py-1 text-xs font-bold hover:border-[var(--brand)] hover:text-[var(--brand)] transition-colors shadow-xs"
              onClick={() => onAcknowledge(alert.id)}
            >
              <Eye className="size-3.5 inline" aria-hidden="true" /> تأكيد
            </button>
            <button
              type="button"
              disabled={isPending}
              className="inline-flex items-center gap-1 rounded-lg border border-emerald-500/30 bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 px-2.5 py-1 text-xs font-bold hover:bg-emerald-500/25 transition-colors shadow-xs"
              onClick={() => onResolve(alert.id)}
            >
              <CheckCircle2 className="size-3.5 inline" aria-hidden="true" /> حل
            </button>
          </div>
        )}
        {isAck && (
          <div className="flex items-center gap-2">
            <span className="inline-flex items-center gap-1 text-xs font-bold text-amber-600 dark:text-amber-400">
              <CheckCircle2 className="size-3.5" aria-hidden="true" /> مؤكد
            </span>
            <button
              type="button"
              disabled={isPending}
              className="inline-flex items-center gap-1 rounded-lg border border-emerald-500/30 bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 px-2.5 py-1 text-xs font-bold hover:bg-emerald-500/25 transition-colors shadow-xs"
              onClick={() => onResolve(alert.id)}
            >
              <CheckCircle2 className="size-3.5" aria-hidden="true" /> حل
            </button>
          </div>
        )}
        {isResolved && (
          <span className="inline-flex items-center gap-1 rounded-md bg-emerald-500/15 px-2 py-0.5 text-xs font-bold text-emerald-600 dark:text-emerald-400">
            <CheckCircle2 className="size-3.5" aria-hidden="true" /> تم الحل {alert.resolved_at ? `(${fmtTime(alert.resolved_at)})` : ''}
          </span>
        )}
      </div>
    </div>
  );
}

// ─── الصفحة الرئيسية ───
export function ObservabilityDashboardPage() {
  const auth = useAuth();
  const healthQuery = useSystemHealth();
  const alertsQuery = useSystemAlerts();
  const updateStatus = useUpdateAlertStatus();
  const resolveAll = useResolveAllAlerts();
  const acknowledgeAll = useAcknowledgeAllAlerts();

  const [alertTab, setAlertTab] = useState<'active' | 'open' | 'acknowledged' | 'resolved' | 'all'>('active');
  const [severityFilter, setSeverityFilter] = useState<'all' | 'P0' | 'P1'>('all');
  const [sourceFilter, setSourceFilter] = useState<string>('all');

  // صلاحية رصد التفاصيل (cron + أحداث) — full access أو observability.read/admin.observability
  const canReadDetail = Boolean(auth.access && (hasPermission(auth.access, 'observability.read') || hasPermission(auth.access, 'admin.observability')));
  const cronSummaryQuery = useCronHealthSummary(canReadDetail);
  const cronJobsQuery = useCronJobHealth(canReadDetail);
  const eventsQuery = useObservabilityEvents(canReadDetail, 50);

  const health = healthQuery.data as Record<string, unknown> | undefined;
  const alerts = alertsQuery.data ?? [];
  const cronSummary = cronSummaryQuery.data;
  const cronJobs = cronJobsQuery.data ?? [];
  const events = eventsQuery.data ?? [];

  const p0Count = alerts.filter((a) => a.severity === 'P0' && a.status !== 'resolved').length;
  const p1Count = alerts.filter((a) => a.severity === 'P1' && a.status !== 'resolved').length;

  const openAlerts = useMemo(() => alerts.filter((a) => a.status === 'open'), [alerts]);
  const ackAlerts = useMemo(() => alerts.filter((a) => a.status === 'acknowledged'), [alerts]);
  const resolvedAlerts = useMemo(() => alerts.filter((a) => a.status === 'resolved'), [alerts]);
  const activeAlerts = useMemo(() => alerts.filter((a) => a.status !== 'resolved'), [alerts]);

  const uniqueSources = useMemo(() => Array.from(new Set(alerts.map((a) => a.source))), [alerts]);

  const displayedAlerts = useMemo(() => {
    let list =
      alertTab === 'active'
        ? activeAlerts
        : alertTab === 'open'
          ? openAlerts
          : alertTab === 'acknowledged'
            ? ackAlerts
            : alertTab === 'resolved'
              ? resolvedAlerts
              : alerts;

    if (severityFilter !== 'all') {
      list = list.filter((a) => a.severity === severityFilter);
    }
    if (sourceFilter !== 'all') {
      list = list.filter((a) => a.source === sourceFilter);
    }
    return list;
  }, [alertTab, activeAlerts, openAlerts, ackAlerts, resolvedAlerts, alerts, severityFilter, sourceFilter]);

  // استخراج بيانات المراقبة من JSON
  const monitors = useMemo(() => {
    if (!health) return null;
    const queue = health.integration_queue as Record<string, unknown> | undefined;
    const notifs = health.notifications as Record<string, unknown> | undefined;
    const errors = health.errors as Record<string, unknown> | undefined;
    const security = health.security as Record<string, unknown> | undefined;
    return { queue, notifs, errors, security };
  }, [health]);

  const isRefreshing = healthQuery.isFetching || alertsQuery.isFetching || cronJobsQuery.isFetching || eventsQuery.isFetching;

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
            {health?.generated_at != null && <span className="muted text-xs">آخر تحديث: {fmtTime(health.generated_at as string)}</span>}
            <button
              type="button"
              className="btn-secondary"
              disabled={isRefreshing}
              onClick={() => {
                void healthQuery.refetch();
                void alertsQuery.refetch();
                void cronSummaryQuery.refetch();
                void cronJobsQuery.refetch();
                void eventsQuery.refetch();
              }}
            >
              <RefreshCw className={`size-4 ${isRefreshing ? 'animate-spin' : ''}`} aria-hidden="true" />
              تحديث
            </button>
          </div>
        }
      />

      {healthQuery.isLoading ? <SkeletonCard className="h-64" /> : null}

      {/* ─── بطاقات الصحة الإجمالية ─── */}
      <section className="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          label="تنبيهات حرجة (P0)"
          value={p0Count}
          hint={p0Count > 0 ? 'تحتاج تدخلاً فورياً' : 'لا توجد تنبيهات حرجة'}
          icon={ShieldAlert}
          onClick={() => document.getElementById('alerts-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
        />
        <MetricCard
          label="تنبيهات (P1)"
          value={p1Count}
          hint={p1Count > 0 ? 'تحتاج مراجعة' : 'لا توجد تنبيهات'}
          icon={AlertTriangle}
          onClick={() => document.getElementById('alerts-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
        />
        <MetricCard
          label="أخطاء آخر ساعة"
          value={monitors?.errors ? num(monitors.errors.errors_last_1h) : '—'}
          hint={monitors?.errors ? `${num(monitors.errors.fatal_last_1h)} حرجة` : undefined}
          icon={XCircle}
          onClick={() => document.getElementById('alerts-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
        />
        <MetricCard
          label="أحداث أمنية حرجة"
          value={monitors?.security ? num(monitors.security.critical_last_1h) : '—'}
          hint={monitors?.security ? `${num(monitors.security.high_last_1h)} عالية` : undefined}
          icon={Shield}
          onClick={() => document.getElementById('alerts-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
        />
      </section>

      {/* ─── التنبيهات المفتوحة ─── */}
      <section id="alerts-section" className="card p-5">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <Bell className="size-5 text-[var(--brand)]" aria-hidden="true" />
            <h3 className="font-black text-base">التنبيهات المفتوحة</h3>
            {activeAlerts.length > 0 && (
              <span className="rounded-full bg-rose-500/15 px-2.5 py-0.5 text-xs font-black text-rose-600 dark:text-rose-400">
                {activeAlerts.length} نشط
              </span>
            )}
          </div>
          {alertsQuery.isError && <ErrorBanner message={safeErrorMessage(alertsQuery.error)} />}

          {/* أزرار العمليات الجماعية */}
          {displayedAlerts.some((a) => a.status !== 'resolved') && (
            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                disabled={resolveAll.isPending}
                className="btn-secondary !py-1 !px-2.5 !text-xs text-emerald-700 dark:text-emerald-400 border-emerald-500/30"
                onClick={() =>
                  resolveAll.mutate({
                    ids: displayedAlerts.filter((a) => a.status !== 'resolved').map((a) => a.id),
                  })
                }
              >
                <CheckCircle2 className="size-3.5 inline ms-1" />
                حل المعروض ({displayedAlerts.filter((a) => a.status !== 'resolved').length})
              </button>
              {displayedAlerts.some((a) => a.status === 'open') && (
                <button
                  type="button"
                  disabled={acknowledgeAll.isPending}
                  className="btn-secondary !py-1 !px-2.5 !text-xs"
                  onClick={() =>
                    acknowledgeAll.mutate({
                      ids: displayedAlerts.filter((a) => a.status === 'open').map((a) => a.id),
                    })
                  }
                >
                  <Eye className="size-3.5 inline ms-1" />
                  تأكيد المعروض ({displayedAlerts.filter((a) => a.status === 'open').length})
                </button>
              )}
            </div>
          )}
        </div>

        {/* ألسنة التصفية */}
        <div className="mb-4 flex flex-wrap items-center justify-between gap-2 border-b border-[var(--border)] pb-3">
          <div className="flex flex-wrap gap-1.5" role="tablist" aria-label="حالة التنبيهات">
            {[
              { id: 'active' as const, label: 'النشطة', count: activeAlerts.length },
              { id: 'open' as const, label: 'بانتظار التأكيد', count: openAlerts.length },
              { id: 'acknowledged' as const, label: 'المؤكدة', count: ackAlerts.length },
              { id: 'resolved' as const, label: 'المحلولة', count: resolvedAlerts.length },
              { id: 'all' as const, label: 'الكل', count: alerts.length },
            ].map((tab) => (
              <button
                key={tab.id}
                type="button"
                role="tab"
                aria-selected={alertTab === tab.id}
                onClick={() => setAlertTab(tab.id)}
                className={`rounded-lg px-3 py-1 text-xs font-bold transition-colors ${
                  alertTab === tab.id
                    ? 'bg-[var(--brand)] text-white'
                    : 'text-[var(--text-muted)] hover:bg-[var(--surface-muted)]'
                }`}
              >
                {tab.label}
                <span className="ms-1.5 opacity-75 font-mono">({tab.count})</span>
              </button>
            ))}
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <select
              value={severityFilter}
              onChange={(e) => setSeverityFilter(e.target.value as 'all' | 'P0' | 'P1')}
              className="input !py-1 !px-2 !text-xs w-auto"
              aria-label="تصفية حسب الخطورة"
            >
              <option value="all">كل درجات الخطورة</option>
              <option value="P0">P0 حرجة فقط</option>
              <option value="P1">P1 عالية فقط</option>
            </select>
            {uniqueSources.length > 1 && (
              <select
                value={sourceFilter}
                onChange={(e) => setSourceFilter(e.target.value)}
                className="input !py-1 !px-2 !text-xs w-auto"
                aria-label="تصفية حسب المصدر"
              >
                <option value="all">كل المصادر</option>
                {uniqueSources.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
            )}
          </div>
        </div>

        {alertsQuery.isLoading ? (
          <SkeletonCard className="h-24" />
        ) : alerts.length === 0 || (alertTab === 'active' && activeAlerts.length === 0) ? (
          <EmptyState title="لا توجد تنبيهات مفتوحة" description="النظام يعمل بسلاسة، لا تنبيهات مفتوحة." />
        ) : displayedAlerts.length === 0 ? (
          <EmptyState title="لا توجد تنبيهات مطابقة" description="لا توجد تنبيهات تطابق خيارات التصفية المحددة." />
        ) : (
          <div className="space-y-2.5">
            {displayedAlerts.map((alert) => (
              <AlertRow
                key={alert.id}
                alert={alert}
                onAcknowledge={(id) => updateStatus.mutate({ alertId: id, status: 'acknowledged' })}
                onResolve={(id) => updateStatus.mutate({ alertId: id, status: 'resolved' })}
                isPending={updateStatus.isPending || resolveAll.isPending}
              />
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
      {canReadDetail && cronSummary && (
        <section className="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
          <MetricCard
            label="مهام نشطة"
            value={num(cronSummary.active)}
            hint={`من أصل ${num(cronSummary.total_jobs)} مهمة مجدولة`}
            icon={Activity}
            onClick={() => document.getElementById('cron-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
          />
          <MetricCard
            label="مهام سليمة"
            value={num(cronSummary.healthy)}
            hint={`${num(cronSummary.unstable)} غير مستقرة`}
            icon={CheckCircle2}
            onClick={() => document.getElementById('cron-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
          />
          <MetricCard
            label="مهام فاشلة"
            value={num(cronSummary.failing)}
            hint={`${num(cronSummary.failures_24h_total)} فشل في 24 ساعة`}
            icon={AlertOctagon}
            onClick={() => document.getElementById('cron-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
          />
          <MetricCard
            label="لم تعمل بعد / معطّلة"
            value={num(cronSummary.never_run) + num(cronSummary.disabled)}
            hint={`${num(cronSummary.never_run)} لم تعمل · ${num(cronSummary.disabled)} معطّلة`}
            icon={Ban}
            onClick={() => document.getElementById('cron-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
          />
        </section>
      )}

      {canReadDetail && cronJobs.length > 0 && (
        <section id="cron-section" className="card overflow-hidden">
          <div className="border-b border-[var(--border)] p-5">
            <h3 className="flex items-center gap-2 font-black">
              <Clock className="size-5 text-[var(--brand)]" aria-hidden="true" />
              تفاصيل المهام المجدولة
            </h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] text-sm">
              <thead className="bg-[var(--surface-muted)] text-xs font-black">
                <tr>
                  <th className="p-3 text-start">المهمة</th>
                  <th className="p-3 text-start">الجدول</th>
                  <th className="p-3 text-start">الحالة</th>
                  <th className="p-3 text-start">آخر تشغيل</th>
                  <th className="p-3 text-start">المدة</th>
                  <th className="p-3 text-start">فشل/24س</th>
                </tr>
              </thead>
              <tbody>
                {cronJobs.map((job) => {
                  const status = job.health_status ?? 'never_run';
                  const statusMeta =
                    status === 'healthy'
                      ? { label: 'سليم', cls: 'text-[var(--success)]', Icon: ShieldCheck }
                      : status === 'failing'
                        ? { label: 'فاشل', cls: 'text-[var(--danger)]', Icon: XCircle }
                        : status === 'unstable'
                          ? { label: 'غير مستقرة', cls: 'text-[var(--warning)]', Icon: AlertTriangle }
                          : status === 'disabled'
                            ? { label: 'معطّلة', cls: 'text-[var(--text-muted)]', Icon: Ban }
                            : { label: 'لم تعمل', cls: 'text-[var(--text-muted)]', Icon: Clock };
                  const StatusIcon = statusMeta.Icon;
                  return (
                    <tr key={job.jobid} className="border-t border-[var(--border)]">
                      <td className="p-3 font-bold">{job.jobname}</td>
                      <td className="p-3 font-mono text-xs" dir="ltr">
                        {job.schedule || '—'}
                      </td>
                      <td className={`p-3 font-bold ${statusMeta.cls}`}>
                        <StatusIcon className="me-1 inline size-4" aria-hidden="true" />
                        {statusMeta.label}
                      </td>
                      <td className="p-3 tabular-nums" dir="ltr">
                        {job.last_start ? fmtTime(job.last_start) : '—'}
                      </td>
                      <td className="p-3 tabular-nums" dir="ltr">
                        {job.duration_seconds != null ? `${num(job.duration_seconds, 0).toFixed(1)}s` : '—'}
                      </td>
                      <td className={`p-3 tabular-nums ${job.failures_24h > 0 ? 'text-[var(--danger)]' : ''}`}>{job.failures_24h}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {/* ─── سجل أحداث المراقبة ─── */}
      {canReadDetail && (
        <section className="card overflow-hidden">
          <div className="border-b border-[var(--border)] p-5">
            <h3 className="flex items-center gap-2 font-black">
              <Database className="size-5 text-[var(--brand)]" aria-hidden="true" />
              سجل أحداث المراقبة
            </h3>
          </div>
          {eventsQuery.isError ? (
            <div className="p-4">
              <ErrorBanner message={`تعذر تحميل الأحداث: ${safeErrorMessage(eventsQuery.error)}`} />
            </div>
          ) : eventsQuery.isLoading ? (
            <SkeletonCard className="h-32" />
          ) : events.length === 0 ? (
            <EmptyState title="لا توجد أحداث" description="لم تُسجَّل أحداث مراقبة في آخر 90 يوماً." />
          ) : (
            <div className="divide-y divide-[var(--border)]">
              {events.map((event) => {
                const levelColor =
                  event.level === 'critical' || event.level === 'error'
                    ? 'bg-[var(--danger)] text-white'
                    : event.level === 'warning'
                      ? 'bg-[var(--warning-soft)] text-[var(--warning)]'
                      : 'bg-[var(--surface-muted)] text-[var(--text-muted)]';
                return (
                  <div key={event.id} className="flex items-start gap-3 p-4">
                    <span className={`mt-0.5 rounded-full px-2 py-0.5 text-xs font-black ${levelColor}`}>{event.level}</span>
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-bold">{event.message}</p>
                      <p className="muted mt-0.5 font-mono text-xs">
                        {event.source}
                        {event.event_type ? ` · ${event.event_type}` : ''}
                      </p>
                      {event.duration_ms != null && <p className="muted mt-0.5 text-xs">المدة: {event.duration_ms}ms</p>}
                    </div>
                    <span className="muted shrink-0 text-xs" dir="ltr">
                      {fmtTime(event.created_at)}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </section>
      )}

      <p className="muted flex items-center gap-2 text-xs">
        <Timer className="size-4" aria-hidden="true" />
        تُحدّث اللوحة تلقائياً كل 30 ثانية.
      </p>
    </div>
  );
}
