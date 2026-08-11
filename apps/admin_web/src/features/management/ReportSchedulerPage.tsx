import { AlarmClockCheck, FileBarChart2, Plus, Send } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow, ListSkeleton } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { safeErrorMessage } from '../../core/errorMapper';
import { useReportSchedulerCatalog, useReportSchedulerCommands } from './useEnterpriseOperations';

export function ReportSchedulerPage() {
  const query = useReportSchedulerCatalog();
  const commands = useReportSchedulerCommands();
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState({
    code: '',
    name: '',
    reportType: 'executive_daily',
    audienceScope: 'organization',
    scheduleKind: 'daily',
    runHour: 8,
    channels: ['in_app'],
  });

  async function submit(e: FormEvent) {
    e.preventDefault();
    try {
      await commands.upsert.mutateAsync(draft);
      setOpen(false);
    } catch {
      /* mutation error surfaced via ErrorBanner */
    }
  }

  const data = query.data;

  return (
    <div className="space-y-6">
      <PageHeader
        title="التقارير المجدولة والتسليم"
        description="جدولة يومية وأسبوعية وشهرية للتقارير التنفيذية، مع تتبع التسليم التلقائي."
        actions={
          <button className="btn-primary" onClick={() => setOpen(true)}>
            <Plus className="size-4" aria-hidden="true" />
            جدولة تقرير
          </button>
        }
      />

      {query.isError ? (
        <ErrorState title="تعذر تحميل جدولة التقارير" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : !data ? (
        <>
          <MetricSkeletonRow />
          <ListSkeleton rows={4} />
        </>
      ) : (
        <>
          <section className="grid gap-4 sm:grid-cols-4">
            <MetricCard label="الجداول" value={data.schedules.length} icon={AlarmClockCheck} />
            <MetricCard label="عمليات التشغيل" value={data.runs.length} icon={FileBarChart2} />
            <MetricCard label="إشعارات منتظرة" value={data.notificationQueue.queued} icon={Send} />
            <MetricCard label="فشل التسليم" value={data.notificationQueue.failed} icon={Send} />
          </section>

          <section className="grid gap-5 xl:grid-cols-[1.2fr_1fr]">
            <article className="card overflow-hidden">
              <div className="border-b border-[var(--border)] p-5">
                <h2 className="font-black">الجداول</h2>
              </div>
              <div className="divide-y divide-[var(--border)]">
                {data.schedules.length ? (
                  data.schedules.map((s) => (
                    <div className="flex justify-between gap-4 p-5" key={s.id}>
                      <div>
                        <p className="font-black">{s.name}</p>
                        <p className="muted text-sm">
                          {s.reportType} · {s.scheduleKind} · الساعة {s.runHour}:00
                        </p>
                        <p className="muted text-xs">التالي: {s.nextRunAt ?? 'يدوي'}</p>
                      </div>
                      <StatusBadge value={s.active ? 'active' : 'inactive'} />
                    </div>
                  ))
                ) : (
                  <EmptyState title="لا توجد تقارير مجدولة" description="أنشئ أول تقرير تنفيذي أو تقرير مدير." />
                )}
              </div>
            </article>

            <article className="card overflow-hidden">
              <div className="border-b border-[var(--border)] p-5">
                <h2 className="font-black">آخر عمليات التشغيل</h2>
              </div>
              <div className="divide-y divide-[var(--border)]">
                {data.runs.length ? (
                  data.runs.map((r) => (
                    <div className="flex justify-between p-5" key={r.id}>
                      <div>
                        <p className="font-black">{r.reportType}</p>
                        <p className="muted text-xs">
                          {r.createdAt} · محاولة {r.attempts}
                        </p>
                      </div>
                      <StatusBadge value={r.status} />
                    </div>
                  ))
                ) : (
                  <EmptyState title="لا توجد عمليات" description="ستظهر بعد تشغيل الجدولة." />
                )}
              </div>
            </article>
          </section>
        </>
      )}

      {open ? (
        <DialogOverlay title="جدولة تقرير" onClose={() => setOpen(false)} maxWidth="max-w-2xl">
          <form className="space-y-4" onSubmit={submit}>
            {commands.upsert.error ? <ErrorBanner message={safeErrorMessage(commands.upsert.error)} /> : null}
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="الكود">
                <input className="input" required value={draft.code} onChange={(e) => setDraft({ ...draft, code: e.target.value })} />
              </Field>
              <Field label="الاسم">
                <input className="input" required value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
              </Field>
              <Field label="نوع التقرير">
                <select className="input" value={draft.reportType} onChange={(e) => setDraft({ ...draft, reportType: e.target.value })}>
                  <option value="executive_daily">تنفيذي يومي</option>
                  <option value="manager_weekly">مدير أسبوعي</option>
                  <option value="hr_monthly">HR شهري</option>
                </select>
              </Field>
              <Field label="التكرار">
                <select className="input" value={draft.scheduleKind} onChange={(e) => setDraft({ ...draft, scheduleKind: e.target.value })}>
                  <option value="daily">يومي</option>
                  <option value="weekly">أسبوعي</option>
                  <option value="monthly">شهري</option>
                </select>
              </Field>
              <Field label="الساعة">
                <input
                  className="input"
                  type="number"
                  min={0}
                  max={23}
                  value={draft.runHour}
                  onChange={(e) => setDraft({ ...draft, runHour: Number(e.target.value) })}
                />
              </Field>
            </div>
            <button type="submit" className="btn-primary" disabled={commands.upsert.isPending}>
              {commands.upsert.isPending ? 'جارٍ الحفظ…' : 'حفظ الجدولة'}
            </button>
          </form>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label>
      <span className="mb-1.5 block text-sm font-bold">{label}</span>
      {children}
    </label>
  );
}
