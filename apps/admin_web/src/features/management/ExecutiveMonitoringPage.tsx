import { Activity, CalendarClock, MapPin, RefreshCw, Search, Send, Users } from 'lucide-react';
import { useMemo, useState, type FormEvent } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAuth } from '../auth/AuthProvider';
import { LiveLocationMap, type MapPoint } from './LiveLocationMap';
import { LiveLocationResultCard } from './LiveLocationResultCard';
import { useExecutiveAttendanceOverview, useLiveLocationCommands } from './useControlCenters';

// لوحة المتابعة اليومية للمدير التنفيذي (الأقسام 1 + 2 + 3):
// ملخص الحضور، فلاتر الحالة، قائمة الموظفين، خريطة حية، وإرسال طلب موقع فوري.

type Row = Record<string, any>;

const STATUS_LABELS: Record<string, string> = {
  present: 'حاضر', late: 'متأخر', not_yet: 'لم يحضر بعد', absent: 'غائب',
  checked_out: 'انصرف', left_early: 'انصرف مبكرًا', on_leave: 'إجازة', assignment: 'مأمورية/قافلة/فاندي',
};

const FILTERS: Array<{ id: string; label: string; key?: string }> = [
  { id: 'all', label: 'الكل' },
  { id: 'present', label: 'حاضر', key: 'present' },
  { id: 'late', label: 'متأخر', key: 'late' },
  { id: 'not_yet', label: 'لم يحضر', key: 'not_yet' },
  { id: 'absent', label: 'غائب', key: 'absent' },
  { id: 'on_leave', label: 'إجازة', key: 'on_leave' },
  { id: 'assignment', label: 'مأمورية', key: 'assignment' },
  { id: 'no_response', label: 'لم يستجب لطلب' },
];

function relative(value: string | null): string {
  if (!value) return '—';
  const m = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 60000));
  if (m < 1) return 'الآن';
  if (m < 60) return `منذ ${m} د`;
  const h = Math.round(m / 60);
  return h < 24 ? `منذ ${h} س` : `منذ ${Math.round(h / 24)} يوم`;
}

export function ExecutiveMonitoringPage() {
  const auth = useAuth();
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('all');
  const [selectedRequestId, setSelectedRequestId] = useState<string | null>(null);
  const [draft, setDraft] = useState<{ row: Row; reason: string } | null>(null);

  const overview = useExecutiveAttendanceOverview(null);
  const commands = useLiveLocationCommands();
  const data = (overview.data as Record<string, any>) ?? { summary: { total: 0 }, employees: [] };
  const summary = data.summary ?? { total: 0 };
  const employees: Row[] = Array.isArray(data.employees) ? data.employees : [];

  const visible = useMemo(() => {
    const term = search.trim().toLocaleLowerCase('ar');
    return employees.filter((e) => {
      if (term && !`${e.name} ${e.employeeCode ?? ''} ${e.department ?? ''}`.toLocaleLowerCase('ar').includes(term)) return false;
      if (filter === 'all') return true;
      if (filter === 'no_response') return e.activeRequestStatus && e.activeRequestStatus !== 'completed';
      return e.status === filter;
    });
  }, [employees, search, filter]);

  const mapPoints: MapPoint[] = visible
    .filter((e) => typeof e.lastLatitude === 'number' && typeof e.lastLongitude === 'number')
    .map((e) => ({ id: e.id, lat: e.lastLatitude, lng: e.lastLongitude, accuracy: e.lastAccuracy, label: e.name, sublabel: e.lastAddressAr ?? e.department }));

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!draft || draft.reason.trim().length < 5) return;
    try {
      const created = await commands.request.mutateAsync({ employeeId: draft.row.id, reason: draft.reason.trim() });
      setDraft(null);
      const id = (created as { id?: string } | null)?.id;
      if (id) setSelectedRequestId(id);
      await overview.refetch();
    } catch { /* commands.request.isError displayed in dialog UI */ }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="متابعة الموظفين اليومية"
        description="من حضر ومن تأخّر ومن تغيّب ومن في إجازة أو مأمورية، مع آخر موقع مصرّح به وإمكانية طلب موقع فوري."
        actions={<button className="btn-secondary" type="button" onClick={() => void overview.refetch()} disabled={overview.isFetching}><RefreshCw className={`size-4 ${overview.isFetching ? 'animate-spin' : ''}`} />تحديث</button>}
      />

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="إجمالي الموظفين" value={summary.total ?? 0} icon={Users} />
        <MetricCard label="حاضر" value={summary.present ?? 0} icon={Activity} />
        <MetricCard label="متأخر / لم يحضر" value={(summary.late ?? 0) + (summary.notYet ?? 0)} icon={CalendarClock} />
        <MetricCard label="طلبات موقع نشطة" value={summary.activeLocationRequests ?? 0} icon={MapPin} />
      </section>

      <section className="grid gap-4 sm:grid-cols-3 xl:grid-cols-6 text-center">
        <MiniStat label="إجازة" value={summary.onLeave ?? 0} />
        <MiniStat label="مأمورية" value={summary.onMission ?? 0} />
        <MiniStat label="قافلة" value={summary.onConvoy ?? 0} />
        <MiniStat label="فاندي" value={summary.onFundraising ?? 0} />
        <MiniStat label="انصرف" value={summary.checkedOut ?? 0} />
        <MiniStat label="غائب" value={summary.absent ?? 0} />
      </section>

      <section className="filter-bar">
        <label className="relative min-w-0 flex-1 sm:max-w-md">
          <Search className="pointer-events-none absolute end-3 top-3 size-4 text-[var(--text-muted)]" />
          <input className="input pe-10" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="ابحث بالاسم أو الكود أو الإدارة…" aria-label="بحث" />
        </label>
        <div className="flex flex-wrap gap-2" role="group" aria-label="تصفية الحالة">
          {FILTERS.map((f) => <button key={f.id} type="button" onClick={() => setFilter(f.id)} className={`filter-chip ${filter === f.id ? 'is-active' : ''}`}>{f.label}</button>)}
        </div>
      </section>

      {overview.isError ? <ErrorState description={overview.error instanceof Error ? overview.error.message : 'تحقق من الصلاحيات.'} onRetry={() => void overview.refetch()} /> : null}

      {!overview.isError ? (
        <section className="grid gap-5 2xl:grid-cols-[1.1fr_.9fr]">
          <article className="card overflow-hidden">
            <div className="border-b border-[var(--border)] p-4"><h2 className="font-black">الخريطة الحية</h2><p className="muted mt-1 text-sm">آخر موقع مصرّح بعرضه لكل موظف</p></div>
            <div className="p-4"><LiveLocationMap points={mapPoints} height={460} /></div>
          </article>

          <article className="card overflow-hidden">
            <div className="border-b border-[var(--border)] p-4"><h2 className="font-black">الموظفون</h2><p className="muted mt-1 text-sm">{visible.length} نتيجة</p></div>
            {overview.isLoading ? <div className="space-y-3 p-4">{[1, 2, 3].map((i) => <div key={i} className="h-24 animate-pulse rounded-2xl bg-[var(--surface-muted)]" />)}</div> : null}
            {!overview.isLoading && !visible.length ? <EmptyState title="لا نتائج" description="غيّر البحث أو المرشّح." /> : null}
            <div className="max-h-[620px] divide-y divide-[var(--border)] overflow-y-auto">
              {visible.map((e) => (
                <article key={e.id} className="p-4 transition-colors hover:bg-[var(--surface-muted)]">
                  <div className="flex items-start justify-between gap-3">
                    <UserAvatar displayName={e.name ?? ''} size="sm" />
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2"><strong className="truncate">{e.name}</strong><StatusBadge value={e.status} label={STATUS_LABELS[e.status] ?? e.status} /></div>
                      <p className="muted mt-1 text-xs">{e.employeeCode ?? '—'} · {e.department ?? 'دون إدارة'} · مدير: {e.managerName ?? '—'}</p>
                      <p className="muted mt-1 text-xs">آخر موقع: {relative(e.lastLocationAt)}{e.lastAddressAr ? ` · ${e.lastAddressAr}` : ''}</p>
                    </div>
                    {e.activeRequestStatus ? <StatusBadge value={e.activeRequestStatus} /> : null}
                  </div>
                  {e.id !== auth.access?.employeeId ? <div className="mt-3 flex flex-wrap gap-2">
                    <button type="button" className="btn-secondary flex-1" disabled={Boolean(e.activeRequestId)} onClick={() => setDraft({ row: e, reason: '' })}>
                      <Send className="size-4" />{e.activeRequestId ? 'يوجد طلب نشط' : 'طلب موقع حي'}
                    </button>
                    {e.activeRequestId ? <button type="button" className="btn-secondary" onClick={() => setSelectedRequestId(e.activeRequestId)}>عرض النتيجة</button> : null}
                  </div> : null}
                </article>
              ))}
            </div>
          </article>
        </section>
      ) : null}

      {selectedRequestId ? (
        <DialogOverlay title="نتيجة طلب الموقع" onClose={() => setSelectedRequestId(null)} maxWidth="max-w-2xl">
          <LiveLocationResultCard requestId={selectedRequestId} />
        </DialogOverlay>
      ) : null}

      {draft ? (
        <DialogOverlay title={`طلب موقع حي من ${draft.row.name}`} onClose={() => setDraft(null)} maxWidth="max-w-xl">
          <p className="muted mb-4 text-sm">يصل إشعار عاجل لهاتف الموظف لإرسال موقعه الحالي فقط. لا فيديو ولا كاميرا (V12 §9).</p>
          <form className="space-y-4" onSubmit={(ev) => void submit(ev)}>
              <p className="rounded-xl bg-[var(--surface-muted)] p-3 text-sm font-bold">نوع التحقق: موقع حديث عالي الدقة فقط (بدون فيديو).</p>
              <label className="block text-sm font-bold">سبب الطلب
                <textarea className="input mt-2 min-h-28" required minLength={5} value={draft.reason} onChange={(ev) => setDraft({ ...draft, reason: ev.target.value })} placeholder="سبب تشغيلي واضح…" />
              </label>
              {commands.request.isError ? <p className="rounded-xl bg-red-500/10 p-3 text-sm font-bold text-red-700">{commands.request.error instanceof Error ? commands.request.error.message : 'تعذّر إرسال الطلب.'}</p> : null}
              <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><button type="button" className="btn-secondary" onClick={() => setDraft(null)}>إلغاء</button><button className="btn-primary" disabled={commands.request.isPending || draft.reason.trim().length < 5}><Send className="size-4" />{commands.request.isPending ? 'جارٍ الإرسال…' : 'إرسال الطلب'}</button></div>
            </form>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

function MiniStat({ label, value }: { label: string; value: number }) {
  return <div className="card p-3"><span className="muted block text-xs">{label}</span><strong className="mt-1 block text-xl font-black">{value}</strong></div>;
}
