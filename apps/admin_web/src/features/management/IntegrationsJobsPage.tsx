import { Activity, Bot, Boxes, Cable, CheckCircle2, CircleOff, Clock3, RefreshCw, Search, ServerCog, TriangleAlert } from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useIntegrationCenter, useIntegrationCommands } from './useControlCenters';

type Tab = 'connectors' | 'outbox' | 'logs' | 'automations';

function date(value: string | null) {
  return value ? new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : 'لم يحدث بعد';
}

export function IntegrationsJobsPage() {
  const query = useIntegrationCenter();
  const commands = useIntegrationCommands();
  const [tab, setTab] = useState<Tab>('connectors');
  const [search, setSearch] = useState('');
  const data = query.data;
  const term = search.trim().toLocaleLowerCase('ar');
  const connectors = useMemo(() => (data?.integrations ?? []).filter((item) => !term || `${item.name} ${item.provider} ${item.category} ${item.status}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const outbox = useMemo(() => (data?.outbox ?? []).filter((item) => !term || `${item.eventType} ${item.status} ${item.error ?? ''}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const logs = useMemo(() => (data?.logs ?? []).filter((item) => !term || `${item.operation ?? ''} ${item.status} ${item.direction} ${item.error ?? ''}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const runs = useMemo(() => (data?.automationRuns ?? []).filter((item) => !term || `${item.status} ${item.error ?? ''}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const active = (data?.integrations ?? []).filter((item) => item.enabled && item.status === 'active').length;
  const errors = (data?.integrations ?? []).filter((item) => item.status === 'error').length;
  const queued = (data?.outbox ?? []).filter((item) => ['pending', 'retrying', 'processing'].includes(item.status)).length;
  const failedJobs = (data?.automationRuns ?? []).filter((item) => item.status === 'failed').length;

  return (
    <div className="space-y-6">
      <PageHeader
        title="التكاملات والمهام الخلفية"
        description="مراقبة الموصلات، Outbox المعاملاتي، سجل الاتصالات وتشغيل الأتمتة دون إظهار بيانات الاعتماد أو حمولات تحتوي معلومات شخصية."
        actions={<button type="button" className="btn-secondary" disabled={query.isFetching} onClick={() => void query.refetch()}><RefreshCw className={`size-4 ${query.isFetching ? 'animate-spin' : ''}`} />تحديث الحالة</button>}
      />
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="موصلات نشطة" value={active} icon={Cable} />
        <MetricCard label="موصلات بها خطأ" value={errors} icon={TriangleAlert} />
        <MetricCard label="رسائل في الطابور" value={queued} icon={Boxes} />
        <MetricCard label="تشغيلات فاشلة" value={failedJobs} icon={Bot} />
      </section>

      <section className="filter-bar flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex flex-wrap gap-2" role="tablist" aria-label="أقسام التكاملات">
          <TabButton active={tab === 'connectors'} onClick={() => setTab('connectors')} label={`الموصلات (${data?.integrations.length ?? 0})`} />
          <TabButton active={tab === 'outbox'} onClick={() => setTab('outbox')} label={`Outbox (${data?.outbox.length ?? 0})`} />
          <TabButton active={tab === 'logs'} onClick={() => setTab('logs')} label={`السجل (${data?.logs.length ?? 0})`} />
          <TabButton active={tab === 'automations'} onClick={() => setTab('automations')} label={`الأتمتة (${data?.automationRuns.length ?? 0})`} />
        </div>
        <label className="relative w-full lg:max-w-sm"><Search className="pointer-events-none absolute end-3 top-3 size-4 text-[var(--text-muted)]" /><input className="input pe-10" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="بحث في القسم الحالي…" aria-label="البحث في التكاملات" /></label>
      </section>

      {query.isError ? <ErrorState title="تعذر تحميل مركز التكاملات" description={query.error instanceof Error ? query.error.message : 'تحقق من الصلاحيات والاتصال.'} onRetry={() => void query.refetch()} /> : null}
      {!query.isError && query.isLoading ? (
        <section className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3" aria-label="جارٍ تحميل التكاملات">
          {Array.from({ length: 6 }).map((_, index) => <SkeletonCard key={index} className="h-52 p-5" />)}
        </section>
      ) : null}

      {data && tab === 'connectors' ? (
        <section className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
          {connectors.map((item) => <article className="card p-5" key={item.id}><div className="flex items-start justify-between gap-3"><span className={`rounded-2xl p-3 ${item.status === 'error' ? 'bg-[var(--danger-soft)] text-[var(--danger)]' : 'bg-[var(--surface-muted)] text-[var(--brand-primary)]'}`}><ServerCog className="size-6" /></span><StatusBadge value={item.status} /></div><h2 className="mt-5 font-black">{item.name}</h2><p className="muted mt-1 text-sm">{item.provider} · {item.category}</p><div className="mt-4 rounded-xl bg-[var(--surface-muted)] p-3 text-xs"><span className="muted">آخر مزامنة</span><strong className="mt-1 block">{date(item.lastSyncAt)}</strong>{item.lastError ? <p className="mt-2 font-bold text-[var(--danger)]">{item.lastError}</p> : null}</div><label className="mt-4 flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-[var(--border)] p-3 text-sm font-bold"><span>{item.enabled ? 'الموصل مفعّل' : 'الموصل متوقف'}</span><input type="checkbox" className="size-5 accent-[var(--brand-primary)]" aria-label={`تفعيل الموصل ${item.name}`} checked={item.enabled} disabled={commands.toggle.isPending} onChange={(event) => void commands.toggle.mutateAsync({ id: item.id, enabled: event.target.checked })} /></label></article>)}
          {!connectors.length ? <div className="lg:col-span-2 xl:col-span-3"><EmptyState title="لا توجد موصلات مطابقة" description="غيّر عبارة البحث أو أضف الموصل من إعدادات البيئة." /></div> : null}
        </section>
      ) : null}

      {data && tab === 'outbox' ? (
        <section className="card overflow-hidden">
          <div className="hidden overflow-x-auto md:block"><table className="w-full min-w-[820px] text-right text-sm"><thead className="bg-[var(--surface-muted)]"><tr><th scope="col" className="p-4">الحدث</th><th scope="col" className="p-4">الحالة</th><th scope="col" className="p-4">المحاولات</th><th scope="col" className="p-4">المحاولة التالية</th><th scope="col" className="p-4">الخطأ</th></tr></thead><tbody>{outbox.map((item) => <tr key={item.id} className="border-t border-[var(--border)]"><td className="p-4"><strong className="font-mono text-xs">{item.eventType}</strong><p className="muted mt-1 text-xs">أُنشئ {date(item.createdAt)}</p></td><td className="p-4"><StatusBadge value={item.status} /></td><td className="p-4">{item.attempts} / {item.maxAttempts}</td><td className="p-4 whitespace-nowrap">{date(item.nextAttemptAt)}</td><td className="max-w-sm p-4 text-xs text-[var(--danger)]">{item.error ?? '—'}</td></tr>)}</tbody></table></div>
          <div className="divide-y divide-[var(--border)] md:hidden">{outbox.map((item) => <article key={item.id} className="p-5"><div className="flex items-start justify-between gap-3"><strong className="font-mono text-xs">{item.eventType}</strong><StatusBadge value={item.status} /></div><p className="muted mt-3 text-xs">محاولات {item.attempts}/{item.maxAttempts} · التالي {date(item.nextAttemptAt)}</p>{item.error ? <p className="mt-3 text-sm font-bold text-[var(--danger)]">{item.error}</p> : null}</article>)}</div>
          {!outbox.length ? <EmptyState title="طابور التكامل فارغ" description="لا توجد رسائل مطابقة في Outbox." /> : null}
        </section>
      ) : null}

      {data && tab === 'logs' ? (
        <section className="card overflow-hidden">
          <div className="divide-y divide-[var(--border)]">{logs.map((item) => <article key={item.id} className="flex flex-col gap-3 p-5 lg:flex-row lg:items-center lg:justify-between"><div className="flex min-w-0 items-start gap-3"><span className={`rounded-xl p-2.5 ${item.status === 'success' ? 'bg-[var(--success-soft)] text-[var(--success)]' : item.status === 'failed' ? 'bg-[var(--danger-soft)] text-[var(--danger)]' : 'bg-[var(--surface-muted)]'}`}>{item.status === 'success' ? <CheckCircle2 className="size-5" /> : item.status === 'failed' ? <CircleOff className="size-5" /> : <Activity className="size-5" />}</span><div><div className="flex flex-wrap items-center gap-2"><strong>{item.operation ?? 'عملية تكامل'}</strong><StatusBadge value={item.status} /><StatusBadge value={item.direction} /></div><p className="muted mt-2 text-xs">{date(item.occurredAt)}{item.httpStatus ? ` · HTTP ${item.httpStatus}` : ''}{item.durationMs !== null ? ` · ${item.durationMs}ms` : ''}</p>{item.error ? <p className="mt-2 text-sm font-bold text-[var(--danger)]">{item.error}</p> : null}</div></div></article>)}</div>
          {!logs.length ? <EmptyState title="لا توجد سجلات مطابقة" description="ستظهر اتصالات الموصلات هنا." /> : null}
        </section>
      ) : null}

      {data && tab === 'automations' ? (
        <section className="grid gap-4 lg:grid-cols-2">{runs.map((item) => <article key={item.id} className="card p-5"><div className="flex items-start justify-between gap-3"><span className="rounded-xl bg-[var(--surface-muted)] p-2.5"><Bot className="size-5" /></span><StatusBadge value={item.status} /></div><h2 className="mt-4 font-black">تشغيل أتمتة</h2><p className="muted mt-1 font-mono text-xs">{item.id}</p><div className="mt-4 flex items-center justify-between gap-3 text-xs"><span className="inline-flex items-center gap-2"><Clock3 className="size-4" />بدأ {date(item.createdAt)}</span><span>{item.attempts} محاولة</span></div>{item.error ? <p className="mt-3 rounded-xl bg-[var(--danger-soft)] p-3 text-sm font-bold text-[var(--danger)]">{item.error}</p> : null}</article>)}{!runs.length ? <div className="lg:col-span-2"><EmptyState title="لا توجد تشغيلات مطابقة" description="ستظهر نتائج قواعد الأتمتة هنا." /></div> : null}</section>
      ) : null}
    </div>
  );
}

function TabButton({ active, onClick, label }: { active: boolean; onClick: () => void; label: string }) {
  return <button type="button" role="tab" aria-selected={active} className={`filter-chip ${active ? 'is-active' : ''}`} onClick={onClick}>{label}</button>;
}
