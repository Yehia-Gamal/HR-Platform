import { Activity, Crosshair, LocateFixed, MapPin, RefreshCw, Send, Signal, SignalLow, Users } from 'lucide-react';
import { useMemo, useState, type FormEvent } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { ExecutiveMonitoringPage } from './ExecutiveMonitoringPage';
import { useLiveLocationCommands, useLocationDirectory, type LocationDirectoryItem } from './useControlCenters';
import { safeErrorMessage } from '../../core/errorMapper';
import { relativeTime } from '../../core/formatTime';

type LocationState = 'fresh' | 'stale' | 'no_signal';
type RequestDraft = { employee: LocationDirectoryItem; reason: string };

const filters: Array<{ id: 'all' | LocationState | 'active'; label: string }> = [
  { id: 'all', label: 'الكل' },
  { id: 'fresh', label: 'متصل الآن' },
  { id: 'stale', label: 'بيانات قديمة' },
  { id: 'no_signal', label: 'دون إشارة' },
  { id: 'active', label: 'طلبات نشطة' },
];

function locationState(item: LocationDirectoryItem): LocationState {
  if (!item.lastRecordedAt || item.lastLatitude === null || item.lastLongitude === null) return 'no_signal';
  return Date.now() - new Date(item.lastRecordedAt).getTime() <= 15 * 60_000 ? 'fresh' : 'stale';
}

function stateLabel(state: LocationState) {
  return state === 'fresh' ? 'متصل' : state === 'stale' ? 'إشارة قديمة' : 'لا توجد إشارة';
}

const NO_LOCATION = 'لم يُسجل موقع بعد';

export function LiveLocationPage() {
  const [tab, setTab] = useState<'directory' | 'monitoring'>('directory');
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<(typeof filters)[number]['id']>('all');
  const [requestDraft, setRequestDraft] = useState<RequestDraft | null>(null);
  const [mobileView, setMobileView] = useState<'map' | 'directory'>('directory');
  const query = useLocationDirectory(search);
  const commands = useLiveLocationCommands();
  const data = useMemo(() => query.data ?? [], [query.data]);
  const visible = useMemo(
    () => data.filter((item) => filter === 'all' || (filter === 'active' ? Boolean(item.activeRequestId) : locationState(item) === filter)),
    [data, filter],
  );
  const { fresh, missing, active } = useMemo(() => {
    let f = 0, m = 0, a = 0;
    for (const item of data) {
      const st = locationState(item);
      if (st === 'fresh') f++;
      if (st === 'no_signal') m++;
      if (item.activeRequestId) a++;
    }
    return { fresh: f, missing: m, active: a };
  }, [data]);

  async function submitRequest(event: FormEvent) {
    event.preventDefault();
    if (!requestDraft || requestDraft.reason.trim().length < 5) return;
    try {
      await commands.request.mutateAsync({ employeeId: requestDraft.employee.id, reason: requestDraft.reason.trim() });
      setRequestDraft(null);
    } catch {
      /* mutation error surfaced via commands.request.isError */
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="مركز الموقع الحي"
        description="تتبع حالة موظفي الميدان وطلبات التحقق النشطة في الوقت الفعلي."
        actions={
          <button className="btn-secondary" type="button" onClick={() => void query.refetch()} disabled={query.isFetching}>
            <RefreshCw className={`size-4 ${query.isFetching ? 'animate-spin' : ''}`} />
            تحديث
          </button>
        }
      />

      <div className="location-mobile-switch" role="tablist" aria-label="تبويب العرض">
        <button type="button" role="tab" aria-selected={tab === 'directory'} className={`filter-chip ${tab === 'directory' ? 'is-active' : ''}`} onClick={() => setTab('directory')}>
          دليل المواقع
        </button>
        <button type="button" role="tab" aria-selected={tab === 'monitoring'} className={`filter-chip ${tab === 'monitoring' ? 'is-active' : ''}`} onClick={() => setTab('monitoring')}>
          متابعة اليوم
        </button>
      </div>

      {tab === 'monitoring' ? (
        <ExecutiveMonitoringPage embedded />
      ) : (
        <>
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="ضمن نطاق الوصول" value={data.length} icon={Users} />
        <MetricCard label="متصلون خلال 15 دقيقة" value={fresh} icon={Signal} />
        <MetricCard label="طلبات نشطة" value={active} icon={Activity} />
        <MetricCard label="دون موقع مسجل" value={missing} icon={SignalLow} />
      </section>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث بالاسم أو كود الموظف أو الإدارة…"
        resultText={query.isLoading ? undefined : `${visible.length} نتيجة`}
        isDirty={search !== '' || filter !== 'all'}
        onClear={() => {
          setSearch('');
          setFilter('all');
        }}
      >
        <div className="flex flex-wrap gap-2" role="group" aria-label="تصفية حالة الموقع">
          {filters.map((item) => (
            <button key={item.id} type="button" onClick={() => setFilter(item.id)} className={`filter-chip ${filter === item.id ? 'is-active' : ''}`}>
              {item.label}
            </button>
          ))}
        </div>
      </FilterBar>

      <div className="location-mobile-switch" role="tablist" aria-label="طريقة عرض الموقع">
        <button
          type="button"
          role="tab"
          aria-selected={mobileView === 'directory'}
          className={`filter-chip ${mobileView === 'directory' ? 'is-active' : ''}`}
          onClick={() => setMobileView('directory')}
        >
          دليل الموظفين
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={mobileView === 'map'}
          className={`filter-chip ${mobileView === 'map' ? 'is-active' : ''}`}
          onClick={() => setMobileView('map')}
        >
          الخريطة
        </button>
      </div>

      {query.isError ? <ErrorState title="تعذر تحميل دليل الموقع" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} /> : null}

      {!query.isError ? (
        <section className="grid gap-5 2xl:grid-cols-[1.15fr_.85fr]">
          <div className={mobileView === 'map' ? '' : 'location-mobile-hidden'}>
            <LocationMap items={visible} />
          </div>
          <article className={`card overflow-hidden ${mobileView === 'directory' ? '' : 'location-mobile-hidden'}`}>
            <div className="flex items-center justify-between gap-3 border-b border-[var(--border)] p-5">
              <div>
                <h2 className="font-black">دليل الموظفين</h2>
                <p className="muted mt-1 text-sm">{query.isLoading ? '…' : `${visible.length} نتيجة`}</p>
              </div>
              <LocateFixed className="size-5 text-[var(--brand-primary)]" aria-hidden="true" />
            </div>
            {query.isLoading ? (
              <div className="p-5" aria-label="جارٍ تحميل الموظفين">
                <ListSkeleton rows={3} label="جارٍ تحميل بيانات الموقع…" />
              </div>
            ) : null}
            {!query.isLoading && !visible.length ? <EmptyState title="لا توجد نتائج مطابقة" description="غيّر البحث أو مرشح حالة الإشارة." /> : null}
            <div className="max-h-[650px] divide-y divide-[var(--border)] overflow-y-auto">
              {visible.map((item) => {
                const state = locationState(item);
                return (
                  <article key={item.id} className="p-5 transition-colors hover:bg-[var(--surface-muted)]">
                    <div className="flex items-start justify-between gap-3">
                      <UserAvatar displayName={item.name} size="sm" />
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                          <strong className="truncate">{item.name}</strong>
                          <StatusBadge value={state} label={stateLabel(state)} />
                        </div>
                        <p className="muted mt-1 text-xs">
                          {item.employeeCode} · {item.jobTitle ?? 'دون مسمى'} · {item.department ?? 'دون إدارة'}
                        </p>
                      </div>
                      {item.activeRequestStatus ? <StatusBadge value={item.activeRequestStatus} /> : null}
                    </div>
                    <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
                      <div className="rounded-xl bg-[var(--surface-muted)] p-3">
                        <span className="muted block">آخر تحديث</span>
                        <strong className="mt-1 block">{relativeTime(item.lastRecordedAt, NO_LOCATION)}</strong>
                      </div>
                      <div className="rounded-xl bg-[var(--surface-muted)] p-3">
                        <span className="muted block">دقة GPS</span>
                        <strong className="mt-1 block">{item.lastAccuracy === null ? '—' : `${Math.round(item.lastAccuracy)} متر`}</strong>
                      </div>
                    </div>
                    <button
                      type="button"
                      className="btn-secondary mt-4 w-full"
                      disabled={Boolean(item.activeRequestId)}
                      onClick={() => setRequestDraft({ employee: item, reason: '' })}
                    >
                      <Crosshair className="size-4" aria-hidden="true" />
                      {item.activeRequestId ? 'يوجد طلب نشط بالفعل' : 'طلب موقع حي'}
                    </button>
                  </article>
                );
              })}
            </div>
          </article>
        </section>
      ) : null}

      {requestDraft ? (
        <DialogOverlay title={`طلب موقع حي من ${requestDraft.employee.name}`} onClose={() => setRequestDraft(null)} maxWidth="max-w-xl">
          <p className="muted -mt-2 mb-4 text-sm">سيصل الطلب إلى هاتف الموظف لالتقاط موقعه الحالي. لا فيديو ولا كاميرا — موقع فقط (V12 §9).</p>
          <form className="space-y-4" onSubmit={(event) => void submitRequest(event)}>
            <p className="rounded-xl bg-[var(--surface-muted)] p-3 text-sm font-bold">نوع التحقق: موقع حديث عالي الدقة فقط (بدون فيديو).</p>
            <label className="block text-sm font-bold">
              سبب الطلب
              <textarea
                className="input mt-2 min-h-28"
                required
                minLength={5}
                value={requestDraft.reason}
                onChange={(event) => setRequestDraft({ ...requestDraft, reason: event.target.value })}
                placeholder="اكتب سببًا تشغيليًا واضحًا…"
              />
            </label>
            {commands.request.isError ? <ErrorBanner message={safeErrorMessage(commands.request.error)} /> : null}
            <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <button type="button" className="btn-secondary" onClick={() => setRequestDraft(null)}>
                إلغاء
              </button>
              <button className="btn-primary" disabled={commands.request.isPending || requestDraft.reason.trim().length < 5}>
                <Send className="size-4" aria-hidden="true" />
                {commands.request.isPending ? 'جارٍ الإرسال…' : 'إرسال الطلب'}
              </button>
            </div>
          </form>
        </DialogOverlay>
      ) : null}
        </>
      )}
    </div>
  );
}

function LocationMap({ items }: { items: LocationDirectoryItem[] }) {
  const points = items.filter(
    (item): item is LocationDirectoryItem & { lastLatitude: number; lastLongitude: number } =>
      item.lastLatitude !== null && item.lastLongitude !== null,
  );
  const latitudes = points.map((item) => item.lastLatitude);
  const longitudes = points.map((item) => item.lastLongitude);
  const minLat = points.length ? Math.min(...latitudes) : 0;
  const maxLat = points.length ? Math.max(...latitudes) : 0;
  const minLng = points.length ? Math.min(...longitudes) : 0;
  const maxLng = points.length ? Math.max(...longitudes) : 0;
  const latRange = Math.max(maxLat - minLat, 0.01);
  const lngRange = Math.max(maxLng - minLng, 0.01);
  return (
    <article className="card overflow-hidden">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] p-5">
        <div>
          <h2 className="font-black">الخريطة التشغيلية</h2>
          <p className="muted mt-1 text-sm">مواضع تقريبية من آخر نقطة مصرح بعرضها</p>
        </div>
        <div className="flex gap-3 text-xs">
          <span className="inline-flex items-center gap-1.5">
            <i className="size-2.5 rounded-full bg-[var(--success)]" aria-hidden="true" />
            متصل
          </span>
          <span className="inline-flex items-center gap-1.5">
            <i className="size-2.5 rounded-full bg-[var(--warning)]" aria-hidden="true" />
            قديم
          </span>
        </div>
      </div>
      <div className="location-map" role="img" aria-label={`خريطة تشغيلية تحتوي ${points.length} نقطة`}>
        <div className="map-ring map-ring-one" />
        <div className="map-ring map-ring-two" />
        <div className="map-center">
          <Crosshair className="size-5" aria-hidden="true" />
          <span>نطاق التشغيل</span>
        </div>
        {points.map((item, index) => {
          const left = 10 + ((((item.lastLongitude - minLng) / lngRange) * 76 + index * 7) % 80);
          const top = 12 + (((1 - (item.lastLatitude - minLat) / latRange) * 65 + index * 11) % 70);
          const state = locationState(item);
          return (
            <span
              key={item.id}
              className={`map-pin map-pin-${state}`}
              style={{ left: `${left}%`, top: `${top}%` }}
              title={`${item.name} — ${relativeTime(item.lastRecordedAt, NO_LOCATION)}`}
            >
              <MapPin className="size-5" aria-hidden="true" />
              <b>{item.name.split(' ')[0]}</b>
            </span>
          );
        })}
        {!points.length ? (
          <div className="absolute inset-0 grid place-items-center">
            <p className="rounded-xl bg-[var(--surface)]/90 px-4 py-3 text-sm font-bold">لا توجد نقاط متاحة للعرض</p>
          </div>
        ) : null}
      </div>
    </article>
  );
}
