import { AlarmClock, CheckCircle2, Clock3, Headphones, Inbox, UserRoundCheck } from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow, SkeletonCard } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useEnterpriseManagementCatalog } from './useEnterpriseManagement';
import { useServiceDeskCommands } from './useControlCenters';

const terminalStatuses = new Set(['resolved', 'closed', 'cancelled']);

function isOverdue(item: { dueAt: string | null; status: string }) {
  return Boolean(item.dueAt && !terminalStatuses.has(item.status) && new Date(item.dueAt).getTime() < Date.now());
}

function date(value: string | null) {
  return value ? new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : 'بلا موعد SLA';
}

export function ServiceDeskPage() {
  const query = useEnterpriseManagementCatalog();
  const commands = useServiceDeskCommands();
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('open');
  const data = query.data?.serviceRequests ?? [];
  const term = search.trim().toLocaleLowerCase('ar');
  const visible = useMemo(() => data.filter((item) => {
    const statusMatches = status === 'all' || (status === 'open' ? !terminalStatuses.has(item.status) : status === 'overdue' ? isOverdue(item) : item.status === status);
    return statusMatches && (!term || `${item.title} ${item.serviceName} ${item.requesterName} ${item.number}`.toLocaleLowerCase('ar').includes(term));
  }), [data, status, term]);
  const open = data.filter((item) => !terminalStatuses.has(item.status)).length;
  const overdue = data.filter(isOverdue).length;
  const urgent = data.filter((item) => item.priority === 'urgent' && !terminalStatuses.has(item.status)).length;
  const resolved = data.filter((item) => item.status === 'resolved' || item.status === 'closed').length;

  return (
    <div className="space-y-6">
      <PageHeader title="مكتب خدمات الموظفين" description="طابور موحد لطلبات الدعم والخدمات الداخلية، مرتب حسب الأولوية وموعد اتفاقية مستوى الخدمة." />
      {query.isLoading ? (
        <MetricSkeletonRow count={4} />
      ) : (
        <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <MetricCard label="طلبات مفتوحة" value={open} icon={Inbox} />
          <MetricCard label="تجاوزت SLA" value={overdue} icon={AlarmClock} />
          <MetricCard label="عاجلة" value={urgent} icon={Headphones} />
          <MetricCard label="تم حلها" value={resolved} icon={CheckCircle2} />
        </section>
      )}

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="رقم الطلب، الموظف، أو الخدمة…"
        resultText={`عرض ${visible.length} من ${data.length}`}
        isDirty={search !== '' || status !== 'open'}
        onClear={() => {
          setSearch('');
          setStatus('open');
        }}
      >
        <div className="flex flex-wrap gap-2" role="group" aria-label="تصفية طلبات الخدمة">
          {[['open', 'المفتوحة'], ['overdue', 'متأخرة'], ['submitted', 'جديدة'], ['in_progress', 'قيد التنفيذ'], ['resolved', 'محلولة'], ['all', 'الكل']].map(([id, label]) => <button type="button" key={id} className={`filter-chip ${status === id ? 'is-active' : ''}`} aria-pressed={status === id} onClick={() => setStatus(id)}>{label}</button>)}
        </div>
      </FilterBar>

      {query.isError ? (
        <ErrorState
          title="تعذر تحميل مكتب الخدمات"
          description={query.error instanceof Error ? query.error.message : undefined}
          onRetry={() => void query.refetch()}
        />
      ) : query.isLoading ? (
        <section className="grid gap-4 xl:grid-cols-2">{[1, 2, 3, 4].map((item) => <SkeletonCard key={item} className="h-44" />)}</section>
      ) : query.data ? (
        <section className="grid gap-4 xl:grid-cols-2">
          {visible.map((item) => (
            <article className="card p-5" key={item.id} style={isOverdue(item) ? { boxShadow: '0 0 0 1px var(--danger-soft)' } : undefined}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><span className="rounded-lg bg-[var(--surface-muted)] px-2 py-1 font-mono text-xs font-black">#{item.number}</span><StatusBadge value={item.priority} /></div><h2 className="mt-3 text-lg font-black">{item.title}</h2><div className="mt-1 flex items-center gap-2"><UserAvatar displayName={item.requesterName} size="sm" /><p className="muted text-sm">{item.serviceName} · مقدّم الطلب: {item.requesterName}</p></div></div>
                <StatusBadge value={isOverdue(item) ? 'overdue' : item.status} label={isOverdue(item) ? 'متجاوز SLA' : undefined} />
              </div>
              <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-[var(--border)] pt-4">
                <span className={`inline-flex items-center gap-2 text-xs font-bold ${isOverdue(item) ? '' : 'muted'}`} style={isOverdue(item) ? { color: 'var(--danger)' } : undefined}><Clock3 className="size-4" aria-hidden="true" />الاستحقاق: {date(item.dueAt)}</span>
                <ServiceActions id={item.id} status={item.status} pending={commands.transition.isPending} transition={(next) => void commands.transition.mutateAsync({ id: item.id, status: next })} />
              </div>
            </article>
          ))}
          {!visible.length ? <div className="xl:col-span-2"><EmptyState title="لا توجد طلبات مطابقة" description="جرّب اختيار حالة أخرى أو غيّر عبارة البحث." /></div> : null}
        </section>
      ) : null}
    </div>
  );
}

function ServiceActions({ status, pending, transition }: { id: string; status: string; pending: boolean; transition: (status: string) => void }) {
  if (status === 'submitted') return <button type="button" className="btn-primary px-3 py-2 text-xs" disabled={pending} onClick={() => transition('assigned')}><UserRoundCheck className="size-4" aria-hidden="true" />استلام الطلب</button>;
  if (status === 'assigned') return <button type="button" className="btn-secondary px-3 py-2 text-xs" disabled={pending} onClick={() => transition('in_progress')}>بدء التنفيذ</button>;
  if (['in_progress', 'waiting_requester'].includes(status)) return <button type="button" className="btn-primary px-3 py-2 text-xs" disabled={pending} onClick={() => transition('resolved')}><CheckCircle2 className="size-4" aria-hidden="true" />تسجيل الحل</button>;
  if (status === 'resolved') return <button type="button" className="btn-secondary px-3 py-2 text-xs" disabled={pending} onClick={() => transition('closed')}>إغلاق نهائي</button>;
  return null;
}
