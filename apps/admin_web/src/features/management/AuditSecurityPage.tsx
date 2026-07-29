import { AlertTriangle, CheckCircle2, Fingerprint, History, Laptop, Loader2, Search, ShieldAlert, ShieldCheck, Smartphone, X } from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { SkeletonCard } from '../../ui/Skeletons';
import { useAuditSecurityCenter, useAuditSecurityCommands } from './useControlCenters';

type Tab = 'security' | 'audit' | 'devices';

function date(value: string) {
  return new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
}

function eventLabel(value: string) {
  const labels: Record<string, string> = {
    login_failed: 'محاولة دخول فاشلة',
    managed_device_registered: 'تسجيل جهاز مُدار',
    privilege_escalation_requested: 'طلب تصعيد صلاحية',
    'access.role_assigned': 'إسناد دور وصلاحيات',
    'employee.updated': 'تحديث سجل موظف',
    'live_location.requested': 'طلب موقع حي',
  };
  return labels[value] ?? value.replaceAll('_', ' ').replaceAll('.', ' · ');
}

export function AuditSecurityPage() {
  const query = useAuditSecurityCenter();
  const commands = useAuditSecurityCommands();
  const [tab, setTab] = useState<Tab>('security');
  const [search, setSearch] = useState('');
  const data = query.data;
  const term = search.trim().toLocaleLowerCase('ar');
  const securityEvents = useMemo(() => (data?.securityEvents ?? []).filter((item) => !term || `${eventLabel(item.eventType)} ${item.severity} ${item.outcome}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const auditEvents = useMemo(() => (data?.auditEvents ?? []).filter((item) => !term || `${eventLabel(item.eventType)} ${item.summary ?? ''} ${item.category} ${item.targetTable ?? ''}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const devices = useMemo(() => (data?.devices ?? []).filter((item) => !term || `${item.name} ${item.platform} ${item.environment} ${item.appVersion}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
  const unhandled = (data?.securityEvents ?? []).filter((item) => !item.handled).length;
  const critical = (data?.securityEvents ?? []).filter((item) => ['high', 'critical'].includes(item.severity) && !item.handled).length;
  const activeDevices = (data?.devices ?? []).filter((item) => item.status === 'active').length;
  const untrusted = (data?.devices ?? []).filter((item) => !item.trusted && item.status === 'active').length;
  const shownCount = tab === 'security' ? securityEvents.length : tab === 'audit' ? auditEvents.length : devices.length;
  const totalCount = tab === 'security' ? data?.securityEvents.length ?? 0 : tab === 'audit' ? data?.auditEvents.length ?? 0 : data?.devices.length ?? 0;

  return (
    <div className="space-y-6">
      <PageHeader title="التدقيق والأمان" description="مركز قراءة ومعالجة للأحداث الأمنية، وسجل تغييرات غير قابل للتعديل، والأجهزة المسجلة دون إظهار المعرّفات أو الأسرار الحساسة." />
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="أحداث غير معالجة" value={unhandled} icon={ShieldAlert} />
        <MetricCard label="عالية الخطورة" value={critical} icon={AlertTriangle} />
        <MetricCard label="أجهزة نشطة" value={activeDevices} icon={Laptop} />
        <MetricCard label="نشطة وغير موثوقة" value={untrusted} icon={Fingerprint} />
      </section>

      <section className="filter-bar flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex flex-wrap gap-2" role="tablist" aria-label="أقسام التدقيق والأمان">
          <TabButton id="tab-security" panelId="panel-security" active={tab === 'security'} onClick={() => setTab('security')} label={`الأحداث الأمنية (${data?.securityEvents.length ?? 0})`} />
          <TabButton id="tab-audit" panelId="panel-audit" active={tab === 'audit'} onClick={() => setTab('audit')} label={`سجل التدقيق (${data?.auditEvents.length ?? 0})`} />
          <TabButton id="tab-devices" panelId="panel-devices" active={tab === 'devices'} onClick={() => setTab('devices')} label={`الأجهزة (${data?.devices.length ?? 0})`} />
        </div>
        <div className="flex w-full flex-col gap-2 lg:max-w-sm">
          <label className="relative block w-full">
            <Search className="pointer-events-none absolute end-3 top-3 size-4 text-[var(--text-muted)]" aria-hidden="true" />
            <input className={`input ps-3 ${search ? 'pe-16' : 'pe-10'}`} value={search} onChange={(event) => setSearch(event.target.value)} placeholder="ابحث في القسم الحالي…" aria-label="البحث في التدقيق والأمان" />
            {search ? (
              <button type="button" className="icon-button absolute end-9 top-1.5 size-7" onClick={() => setSearch('')} aria-label="مسح البحث">
                <X className="size-4" aria-hidden="true" />
              </button>
            ) : null}
          </label>
          {data && term ? <p className="muted text-xs" aria-live="polite">عرض {shownCount} من {totalCount}</p> : null}
        </div>
      </section>

      {query.isError ? (
        <ErrorState title="تعذر تحميل مركز الأمان" description={query.error instanceof Error ? query.error.message : 'تحقق من صلاحيات التدقيق والأمان.'} onRetry={() => void query.refetch()} />
      ) : query.isLoading ? (
        <SkeletonCard className="h-72" />
      ) : null}

      {commands.handleEvent.isError ? <ErrorBanner message={commands.handleEvent.error instanceof Error ? commands.handleEvent.error.message : 'تعذر تأكيد معالجة الحدث.'} /> : null}

      {data && tab === 'security' ? (
        <section className="card overflow-hidden" role="tabpanel" id="panel-security" aria-labelledby="tab-security" tabIndex={0}>
          <div className="divide-y divide-[var(--border)]">
            {securityEvents.map((item) => <article key={item.id} className="flex flex-col gap-4 p-5 lg:flex-row lg:items-center lg:justify-between"><div className="flex min-w-0 items-start gap-3"><span className="rounded-xl p-2.5" style={item.handled ? { background: 'var(--success-soft)', color: 'var(--success)' } : { background: 'var(--danger-soft)', color: 'var(--danger)' }}>{item.handled ? <ShieldCheck className="size-5" aria-hidden="true" /> : <ShieldAlert className="size-5" aria-hidden="true" />}</span><div><div className="flex flex-wrap items-center gap-2"><strong>{eventLabel(item.eventType)}</strong><StatusBadge value={item.severity} /><StatusBadge value={item.outcome} /></div><p className="muted mt-2 text-xs">{date(item.occurredAt)} · {item.handled ? 'تمت المعالجة' : 'بانتظار المراجعة'}</p></div></div>{!item.handled ? <button type="button" className="btn-secondary self-start lg:self-auto" disabled={commands.handleEvent.isPending} onClick={() => void commands.handleEvent.mutateAsync(item.id)}>{commands.handleEvent.isPending ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : <CheckCircle2 className="size-4" aria-hidden="true" />}{commands.handleEvent.isPending ? 'جارٍ المعالجة…' : 'تأكيد المعالجة'}</button> : null}</article>)}
          </div>
          {!securityEvents.length ? <EmptyState title="لا توجد أحداث مطابقة" description="لا توجد أحداث أمنية ضمن نتيجة البحث الحالية." /> : null}
        </section>
      ) : null}

      {data && tab === 'audit' ? (
        <section className="card overflow-hidden" role="tabpanel" id="panel-audit" aria-labelledby="tab-audit" tabIndex={0}>
          <div className="hidden overflow-x-auto md:block"><table className="w-full min-w-[820px] text-start text-sm"><thead className="bg-[var(--surface-muted)]"><tr><th className="p-4">الحدث</th><th className="p-4">التصنيف</th><th className="p-4">الملخص</th><th className="p-4">الكيان</th><th className="p-4">الوقت</th></tr></thead><tbody>{auditEvents.map((item) => <tr key={item.id} className="border-t border-[var(--border)]"><td className="p-4"><strong>{eventLabel(item.eventType)}</strong></td><td className="p-4"><div className="flex gap-2"><StatusBadge value={item.category} /><StatusBadge value={item.severity} /></div></td><td className="p-4">{item.summary ?? '—'}</td><td className="p-4 font-mono text-xs">{item.targetTable ?? '—'}</td><td className="p-4 whitespace-nowrap">{date(item.occurredAt)}</td></tr>)}</tbody></table></div>
          <div className="divide-y divide-[var(--border)] md:hidden">{auditEvents.map((item) => <article key={item.id} className="p-5"><div className="flex items-start gap-3"><History className="mt-0.5 size-5 shrink-0 text-[var(--brand-primary)]" aria-hidden="true" /><div><strong>{eventLabel(item.eventType)}</strong><p className="mt-2 text-sm">{item.summary ?? 'دون ملخص'}</p><div className="mt-3 flex flex-wrap gap-2"><StatusBadge value={item.category} /><StatusBadge value={item.severity} /></div><p className="muted mt-3 text-xs">{date(item.occurredAt)}</p></div></div></article>)}</div>
          {!auditEvents.length ? <EmptyState title="لا توجد أحداث تدقيق مطابقة" description="جرّب عبارة بحث مختلفة." /> : null}
        </section>
      ) : null}

      {data && tab === 'devices' ? (
        <section className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3" role="tabpanel" id="panel-devices" aria-labelledby="tab-devices" tabIndex={0}>
          {devices.map((item) => <article className="card p-5" key={item.id}><div className="flex items-start justify-between gap-3"><span className="rounded-2xl bg-[var(--surface-muted)] p-3">{item.platform === 'web' ? <Laptop className="size-6" aria-hidden="true" /> : <Smartphone className="size-6" aria-hidden="true" />}</span><div className="flex flex-wrap justify-end gap-2"><StatusBadge value={item.status} /><StatusBadge value={item.trusted ? 'trusted' : 'untrusted'} label={item.trusted ? 'موثوق' : 'غير موثوق'} /></div></div><h2 className="mt-5 font-black">{item.name}</h2><p className="muted mt-1 text-sm">{item.platform.toUpperCase()} · الإصدار {item.appVersion}</p><div className="mt-4 grid grid-cols-2 gap-2 text-xs"><div className="rounded-xl bg-[var(--surface-muted)] p-3"><span className="muted block">البيئة</span><strong className="mt-1 block">{item.environment}</strong></div><div className="rounded-xl bg-[var(--surface-muted)] p-3"><span className="muted block">آخر ظهور</span><strong className="mt-1 block">{date(item.lastSeenAt)}</strong></div></div></article>)}
          {!devices.length ? <div className="lg:col-span-2 xl:col-span-3"><EmptyState title="لا توجد أجهزة مطابقة" description="لا توجد أجهزة ضمن البحث الحالي." /></div> : null}
        </section>
      ) : null}
    </div>
  );
}

function TabButton({ id, panelId, active, onClick, label }: { id: string; panelId: string; active: boolean; onClick: () => void; label: string }) {
  return <button type="button" id={id} role="tab" aria-selected={active} aria-controls={panelId} className={`filter-chip ${active ? 'is-active' : ''}`} onClick={onClick}>{label}</button>;
}
