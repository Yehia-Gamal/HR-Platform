import { Activity, DatabaseBackup, Flag, Settings, ShieldAlert } from 'lucide-react';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { ErrorState } from '../../ui/ErrorState';
import { MetricSkeletonRow, ListSkeleton } from '../../ui/Skeletons';
import { useSystemOverview } from './useManagementOverviews';
import { safeErrorMessage } from '../../core/errorMapper';

export function SystemPage() {
  const q = useSystemOverview();
  const d = q.data;

  return (
    <div className="space-y-6">
      <PageHeader title="إعدادات وصحة النظام" description="Feature Flags والأخطاء والنسخ الاحتياطية وإعدادات المنصة في شاشة تشغيل تقنية واحدة." />

      {q.isError ? (
        <ErrorState title="تعذر تحميل الحالة التقنية" description={safeErrorMessage(q.error)} onRetry={() => void q.refetch()} />
      ) : q.isLoading && !d ? (
        <div className="space-y-6">
          <MetricSkeletonRow count={5} />
          <ListSkeleton rows={4} label="جارٍ تحميل الحالة التقنية…" />
        </div>
      ) : d ? (
        <>
          <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
            <MetricCard label="الميزات المفعلة" value={`${d.enabledFlags}/${d.totalFlags}`} icon={Flag} />
            <MetricCard label="أخطاء غير محلولة" value={d.unresolvedErrors} icon={ShieldAlert} trend={d.unresolvedErrors > 0 ? 'يتطلب متابعة' : undefined} />
            <MetricCard label="أخطاء حرجة" value={d.fatalErrors} icon={Activity} hint={d.fatalErrors > 0 ? 'يتطلب تدخلاً فورياً' : undefined} />
            <MetricCard label="آخر نسخة احتياطية" value={d.latestBackupStatus ?? 'لا يوجد'} icon={DatabaseBackup} />
            <MetricCard label="إعدادات النظام" value={d.settingsCount} icon={Settings} />
          </section>

          <section className="grid gap-5 xl:grid-cols-2">
            <article className="card p-5">
              <h2 className="font-black">Feature Flags</h2>
              <p className="muted mt-1 text-sm">حالة الميزات ونسب إطلاقها عبر البيئات.</p>
              <div className="mt-4 space-y-3">
                {d.flags.length ? (
                  d.flags.map((f) => (
                    <div key={f.id} className="rounded-xl bg-[var(--surface-muted)] p-4">
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <p className="font-black">{f.name ?? f.key}</p>
                          <p className="muted mt-1 font-mono text-xs">
                            {f.key} · {f.environment}
                          </p>
                        </div>
                        <StatusBadge value={f.enabled ? 'active' : 'inactive'} />
                      </div>
                      <div className="mt-3">
                        <div className="flex items-center justify-between gap-2">
                          <span className="muted text-xs">نسبة الإطلاق</span>
                          <span className="text-xs font-black">{f.rolloutPercent}%</span>
                        </div>
                        <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-[var(--surface-subtle)]">
                          <div
                            className="h-full rounded-full bg-[var(--brand-primary)]"
                            style={{
                              width: `${Math.max(0, Math.min(100, f.rolloutPercent))}%`,
                            }}
                          />
                        </div>
                      </div>
                    </div>
                  ))
                ) : (
                  <p className="muted text-sm">لا توجد ميزات معرّفة.</p>
                )}
              </div>
            </article>

            <article className="card p-5">
              <h2 className="font-black">أحدث الأخطاء المفتوحة</h2>
              <p className="muted mt-1 text-sm">آخر الأخطاء غير المحلولة عبر المنصة.</p>
              <div className="mt-4 space-y-3">
                {d.recentErrors.length ? (
                  d.recentErrors.map((e) => (
                    <div key={e.id} className="rounded-xl border border-[var(--border)] p-4">
                      <div className="flex gap-2">
                        <StatusBadge value={e.level} />
                        <span className="muted text-xs">{e.source}</span>
                      </div>
                      <p className="mt-3 text-sm font-bold">{e.message}</p>
                      <p className="muted mt-2 text-xs">
                        {new Intl.DateTimeFormat('ar-EG', {
                          dateStyle: 'medium',
                          timeStyle: 'short',
                        }).format(new Date(e.occurredAt))}
                      </p>
                    </div>
                  ))
                ) : (
                  <p className="muted text-sm">لا توجد أخطاء مفتوحة.</p>
                )}
              </div>
            </article>
          </section>
        </>
      ) : null}
    </div>
  );
}
