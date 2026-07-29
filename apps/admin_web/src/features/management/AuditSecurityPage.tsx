import { AlertTriangle, CheckCircle2, ChevronDown, ChevronUp, Clock, Cpu, Fingerprint, History, Laptop, Loader2, Monitor, Search, ShieldAlert, ShieldCheck, ShieldX, Smartphone, Trash2, User, X } from 'lucide-react';
import { useCallback, useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { SkeletonCard } from '../../ui/Skeletons';
import { useAuditSecurityCenter, useAuditSecurityCommands } from './useControlCenters';
import type { AuditSecurityData } from './controlCenterTypes';

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
  const devices = useMemo(() => (data?.devices ?? []).filter((item) => !term || `${item.name} ${item.employeeName ?? ''} ${item.platform} ${item.environment} ${item.appVersion} ${item.deviceModel ?? ''}`.toLocaleLowerCase('ar').includes(term)), [data, term]);
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
            {securityEvents.map((item) => <article key={item.id} className="flex flex-col gap-4 p-5 lg:flex-row lg:items-center lg:justify-between"><div className="flex min-w-0 items-start gap-3"><span className="rounded-xl p-2.5" style={item.handled ? { background: 'var(--success-soft)', color: 'var(--success)' } : { background: 'var(--danger-soft)', color: 'var(--danger)' }}>{item.handled ? <ShieldCheck className="size-5" aria-hidden="true" /> : <ShieldAlert className="size-5" aria-hidden="true" />}</span><div><div className="flex flex-wrap items-center gap-2"><strong>{eventLabel(item.eventType)}</strong><StatusBadge value={item.severity} /><StatusBadge value={item.outcome} /></div><p className="muted mt-2 text-xs">{date(item.occurredAt)} · {item.handled ? 'تمت المعالجة' : 'بانتظار المراجعة'}</p></div></div>{!item.handled ? <button type="button" className="btn-secondary self-start lg:self-auto" disabled={commands.handleEvent.isPending} onClick={() => commands.handleEvent.mutate(item.id)}>{commands.handleEvent.isPending ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : <CheckCircle2 className="size-4" aria-hidden="true" />}{commands.handleEvent.isPending ? 'جارٍ المعالجة…' : 'تأكيد المعالجة'}</button> : null}</article>)}
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
        <DevicesPanel devices={devices} commands={commands} />
      ) : null}
    </div>
  );
}

type DeviceItem = AuditSecurityData['devices'][number];

/** تجميع الأجهزة حسب الموظف — لإزالة التكرار وعرض جهاز واحد (الأحدث) لكل موظف+منصة */
function deduplicateDevices(items: DeviceItem[]): DeviceItem[] {
  const map = new Map<string, DeviceItem>();
  for (const item of items) {
    // مفتاح: موظف + منصة (أو id الموظف الفارغ + اسم الجهاز)
    const key = `${item.employeeId ?? 'anon'}-${item.platform}-${item.name}`;
    const existing = map.get(key);
    if (!existing || item.lastSeenAt > existing.lastSeenAt) {
      map.set(key, item);
    }
  }
  return Array.from(map.values());
}

function DevicesPanel({ devices, commands }: { devices: DeviceItem[]; commands: ReturnType<typeof useAuditSecurityCommands> }) {
  const deduplicated = useMemo(() => deduplicateDevices(devices), [devices]);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [revokeTarget, setRevokeTarget] = useState<DeviceItem | null>(null);
  const [revokeReason, setRevokeReason] = useState('');
  const [revokeError, setRevokeError] = useState('');

  const handleRevoke = useCallback(async () => {
    if (!revokeTarget) return;
    const reason = revokeReason.trim();
    if (reason.length < 10) {
      setRevokeError('السبب يجب أن يكون 10 أحرف على الأقل.');
      return;
    }
    setRevokeError('');
    try {
      await commands.revokeDevice.mutateAsync({ deviceId: revokeTarget.id, reason });
      setRevokeTarget(null);
      setRevokeReason('');
    } catch {
      setRevokeError('تعذّر إلغاء تسجيل الجهاز. تحقق من صلاحياتك.');
    }
  }, [revokeTarget, revokeReason, commands.revokeDevice]);

  return (
    <>
      {commands.revokeDevice.isError && !revokeTarget ? <ErrorBanner message="تعذّر إلغاء تسجيل الجهاز." /> : null}

      {/* حوار تأكيد الإلغاء */}
      {revokeTarget ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setRevokeTarget(null)}>
          <div className="card w-full max-w-md space-y-4 p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-3">
              <span className="rounded-xl bg-[var(--danger-soft)] p-2.5 text-[var(--danger)]"><ShieldX className="size-5" aria-hidden="true" /></span>
              <h3 className="text-lg font-black">إلغاء تسجيل الجهاز</h3>
            </div>
            <p className="text-sm">سيتم إلغاء تسجيل <strong>{revokeTarget.name}</strong>{revokeTarget.employeeName ? <> — <span className="text-[var(--brand-primary)]">{revokeTarget.employeeName}</span></> : null}. لا يمكن التراجع عن هذا الإجراء.</p>
            <label className="block">
              <span className="mb-1 block text-sm font-medium">سبب الإلغاء <span className="text-[var(--danger)]">*</span></span>
              <textarea className="input w-full" rows={3} value={revokeReason} onChange={(e) => setRevokeReason(e.target.value)} placeholder="اكتب سبب الإلغاء (10 أحرف على الأقل)…" />
            </label>
            {revokeError ? <p className="text-sm text-[var(--danger)]">{revokeError}</p> : null}
            <div className="flex justify-end gap-2">
              <button type="button" className="btn-secondary" onClick={() => { setRevokeTarget(null); setRevokeReason(''); setRevokeError(''); }}>إلغاء</button>
              <button type="button" className="btn-danger" disabled={commands.revokeDevice.isPending} onClick={() => void handleRevoke()}>
                {commands.revokeDevice.isPending ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : <Trash2 className="size-4" aria-hidden="true" />}
                {commands.revokeDevice.isPending ? 'جارٍ الإلغاء…' : 'تأكيد الإلغاء'}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      <section className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3" role="tabpanel" id="panel-devices" aria-labelledby="tab-devices" tabIndex={0}>
        {deduplicated.map((item) => {
          const isExpanded = expandedId === item.id;
          const isRevoked = item.status === 'revoked';
          return (
            <article className={`card overflow-hidden ${isRevoked ? 'opacity-60' : ''}`} key={item.id}>
              <div className="p-5">
                {/* رأس البطاقة: أيقونة + حالة */}
                <div className="flex items-start justify-between gap-3">
                  <span className="rounded-2xl bg-[var(--surface-muted)] p-3">
                    {item.platform === 'web' ? <Monitor className="size-6" aria-hidden="true" /> : item.platform === 'ios' ? <Smartphone className="size-6" aria-hidden="true" /> : <Smartphone className="size-6" aria-hidden="true" />}
                  </span>
                  <div className="flex flex-wrap justify-end gap-2">
                    <StatusBadge value={item.status} />
                    <StatusBadge value={item.trusted ? 'trusted' : 'untrusted'} label={item.trusted ? 'موثوق' : 'غير موثوق'} />
                  </div>
                </div>

                {/* اسم الجهاز */}
                <h2 className="mt-4 font-black">{item.name}</h2>

                {/* اسم الموظف */}
                <div className="mt-2 flex items-center gap-2 text-sm">
                  <User className="size-4 shrink-0 text-[var(--brand-primary)]" aria-hidden="true" />
                  <span className={item.employeeName ? 'font-medium' : 'muted'}>{item.employeeName ?? 'غير مرتبط بموظف'}</span>
                </div>

                {/* معلومات أساسية */}
                <p className="muted mt-2 text-sm">{item.platform.toUpperCase()}{item.deviceModel ? ` · ${item.deviceModel}` : ''} · الإصدار {item.appVersion}</p>

                {/* شبكة المعلومات المختصرة */}
                <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
                  <div className="rounded-xl bg-[var(--surface-muted)] p-3">
                    <span className="muted flex items-center gap-1"><Clock className="size-3" aria-hidden="true" /> آخر ظهور</span>
                    <strong className="mt-1 block">{date(item.lastSeenAt)}</strong>
                  </div>
                  <div className="rounded-xl bg-[var(--surface-muted)] p-3">
                    <span className="muted flex items-center gap-1"><Cpu className="size-3" aria-hidden="true" /> البيئة</span>
                    <strong className="mt-1 block">{item.environment}</strong>
                  </div>
                </div>

                {/* زر عرض/إخفاء التفاصيل */}
                <button type="button" className="mt-3 flex w-full items-center justify-center gap-1 rounded-xl py-2 text-xs font-medium text-[var(--brand-primary)] transition hover:bg-[var(--surface-muted)]" onClick={() => setExpandedId(isExpanded ? null : item.id)}>
                  {isExpanded ? <ChevronUp className="size-4" aria-hidden="true" /> : <ChevronDown className="size-4" aria-hidden="true" />}
                  {isExpanded ? 'إخفاء التفاصيل' : 'عرض التفاصيل'}
                </button>
              </div>

              {/* التفاصيل الموسّعة */}
              {isExpanded ? (
                <div className="border-t border-[var(--border)] bg-[var(--surface-muted)] px-5 py-4">
                  <dl className="grid grid-cols-2 gap-3 text-xs">
                    {item.osVersion ? <DetailItem label="نظام التشغيل" value={item.osVersion} /> : null}
                    {item.deviceModel ? <DetailItem label="الطراز" value={item.deviceModel} /> : null}
                    <DetailItem label="أول ظهور" value={date(item.firstSeenAt)} />
                    <DetailItem label="آخر ظهور" value={date(item.lastSeenAt)} />
                    <DetailItem label="المنصة" value={item.platform.toUpperCase()} />
                    <DetailItem label="إصدار التطبيق" value={item.appVersion} />
                    <DetailItem label="البيئة" value={item.environment} />
                    <DetailItem label="الثقة" value={item.trusted ? 'موثوق ✓' : 'غير موثوق ✗'} />
                  </dl>

                  {/* زر إلغاء التسجيل */}
                  {!isRevoked ? (
                    <button type="button" className="btn-danger mt-4 w-full" onClick={() => { setRevokeTarget(item); setRevokeReason(''); setRevokeError(''); }}>
                      <Trash2 className="size-4" aria-hidden="true" /> إلغاء تسجيل الجهاز
                    </button>
                  ) : (
                    <p className="mt-4 flex items-center justify-center gap-2 rounded-xl bg-[var(--danger-soft)] p-3 text-sm font-medium text-[var(--danger)]">
                      <ShieldX className="size-4" aria-hidden="true" /> تم إلغاء التسجيل
                    </p>
                  )}
                </div>
              ) : null}
            </article>
          );
        })}
        {!deduplicated.length ? <div className="lg:col-span-2 xl:col-span-3"><EmptyState title="لا توجد أجهزة مطابقة" description="لا توجد أجهزة ضمن البحث الحالي." /></div> : null}
      </section>
    </>
  );
}

function DetailItem({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="muted">{label}</dt>
      <dd className="mt-0.5 font-medium">{value}</dd>
    </div>
  );
}

function TabButton({ id, panelId, active, onClick, label }: { id: string; panelId: string; active: boolean; onClick: () => void; label: string }) {
  return <button type="button" id={id} role="tab" aria-selected={active} aria-controls={panelId} className={`filter-chip ${active ? 'is-active' : ''}`} onClick={onClick}>{label}</button>;
}
