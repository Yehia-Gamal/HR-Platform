import { Ban, CheckCircle2, Clock3, Eye, EyeOff, MonitorSmartphone, RotateCcw, Shield, ShieldAlert, ShieldOff, Smartphone, Trash2 } from 'lucide-react';
import { useMemo, useState } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { Tabs } from '../../ui/Tabs';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { safeErrorMessage } from '../../core/errorMapper';
import type { AdminDevice, PendingDevice } from './useDevices';
import { useAllDevices, useApproveDevice, useDeleteDevice, useDeviceApprovals, useReinstateDevice, useRevokeDevice } from './useDevices';

type Tab = 'pending' | 'all';

export function DeviceApprovalPage() {
  const [tab, setTab] = useState<Tab>('pending');

  return (
    <div className="space-y-5">
      <PageHeader title="أجهزة الموظفين" description="مراجعة وموافقة على أجهزة الموظفين وإدارة الأجهزة المسجلة" />
      <Tabs
        tabs={[{ id: 'pending', label: 'طلبات الأجهزة' }, { id: 'all', label: 'كل الأجهزة' }]}
        activeTab={tab}
        onTabChange={(id) => setTab(id as Tab)}
        ariaLabel="أقسام الأجهزة"
      >
        {tab === 'pending' ? <PendingDevicesPanel /> : <AllDevicesPanel />}
      </Tabs>
    </div>
  );
}

function PendingDevicesPanel() {
  const query = useDeviceApprovals();
  const approve = useApproveDevice();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [confirmAction, setConfirmAction] = useState<{ device: PendingDevice; approved: boolean } | null>(null);
  const [reason, setReason] = useState('');
  const allDevices = useMemo(() => query.data ?? [], [query.data]);
  const filtered = useMemo(() => allDevices.filter((d) => {
    const q = search.trim().toLowerCase();
    const matchesSearch = !q || `${d.employeeName} ${d.employeeCode ?? ''} ${d.deviceName ?? ''} ${d.platform}`.toLowerCase().includes(q);
    return matchesSearch && (statusFilter === 'all' || d.status === statusFilter);
  }), [allDevices, search, statusFilter]);
  const pendingCount = allDevices.filter((d) => d.status === 'pending').length;
  const blockedCount = allDevices.filter((d) => d.status === 'blocked').length;

  function handleAction(device: PendingDevice, approved: boolean) { setConfirmAction({ device, approved }); setReason(''); }
  function executeAction() {
    if (!confirmAction) return;
    approve.mutate({ deviceId: confirmAction.device.id, approved: confirmAction.approved, reason: confirmAction.approved ? undefined : reason || undefined }, {
      onSuccess: () => { setConfirmAction(null); },
    });
  }

  if (query.isLoading) return (<div className="space-y-5"><MetricSkeletonRow count={3} /><ListSkeleton rows={4} /></div>);
  if (query.isError) return <ErrorState onRetry={() => void query.refetch()} />;

  return (
    <div className="space-y-5">
      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <MetricCard label="إجمالي المعلّقة" value={allDevices.length} icon={MonitorSmartphone} hint="أجهزة تنتظر المراجعة أو محظورة" />
        <MetricCard label="بانتظار الموافقة" value={pendingCount} icon={Clock3} hint="أجهزة جديدة لم تُراجع بعد" />
        <MetricCard label="محظورة" value={blockedCount} icon={ShieldAlert} hint="أجهزة تم رفضها وتحتاج مراجعة" />
      </section>
      <FilterBar searchValue={search} onSearchChange={setSearch} searchPlaceholder="بحث باسم الموظف أو الكود أو اسم الجهاز..." resultText={`${filtered.length} من ${allDevices.length} جهاز`} isDirty={search !== '' || statusFilter !== 'all'} onClear={() => { setSearch(''); setStatusFilter('all'); }}>
        <select className="input" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          <option value="pending">بانتظار الموافقة</option>
          <option value="blocked">محظور</option>
        </select>
      </FilterBar>
      {filtered.length === 0 ? (
        <EmptyState title="لا توجد أجهزة معلّقة" description={allDevices.length === 0 ? 'لم يسجّل أي موظف جهازاً جديداً بعد.' : 'لا توجد نتائج مطابقة للفلاتر المحددة.'} />
      ) : (
        <section className="space-y-3" aria-label="قائمة الأجهزة">
          {filtered.map((device) => (<PendingDeviceCard key={device.id} device={device} onAction={handleAction} isPending={approve.isPending} />))}
        </section>
      )}
      {confirmAction ? (
        <DialogOverlay title={confirmAction.approved ? 'تأكيد الموافقة' : 'تأكيد الرفض'} onClose={() => setConfirmAction(null)} maxWidth="max-w-md">
          <p className="text-sm leading-7 text-[var(--text-muted)]">
            {confirmAction.approved ? `هل تريد الموافقة على جهاز "${confirmAction.device.deviceName ?? confirmAction.device.platform}" للموظف ${confirmAction.device.employeeName}؟ سيتمكن الموظف من تسجيل الحضور عبر هذا الجهاز.` : `هل تريد رفض جهاز "${confirmAction.device.deviceName ?? confirmAction.device.platform}" للموظف ${confirmAction.device.employeeName}؟`}
          </p>
          {!confirmAction.approved ? (
            <div className="mt-4">
              <label className="text-sm font-bold" htmlFor="rejection-reason">سبب الرفض (اختياري)</label>
              <textarea id="rejection-reason" className="input mt-1 w-full" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="مثال: الجهاز غير مسجل ضمن الأجهزة المعتمدة" />
            </div>
          ) : null}
          {approve.isError ? <div className="mt-3"><ErrorBanner message={safeErrorMessage(approve.error)} /></div> : null}
          <div className="mt-4 flex gap-2 justify-end">
            <button type="button" className="btn-secondary" onClick={() => setConfirmAction(null)}>إلغاء</button>
            <button type="button" className={confirmAction.approved ? 'btn-primary' : 'btn-danger'} disabled={approve.isPending} onClick={executeAction}>{approve.isPending ? 'جارٍ التنفيذ...' : confirmAction.approved ? 'موافقة' : 'رفض'}</button>
          </div>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

function AllDevicesPanel() {
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [showTerminated, setShowTerminated] = useState(false);
  const query = useAllDevices(statusFilter || undefined, showTerminated);
  const revoke = useRevokeDevice();
  const remove = useDeleteDevice();
  const reinstate = useReinstateDevice();
  const [search, setSearch] = useState('');
  const [revokeTarget, setRevokeTarget] = useState<AdminDevice | null>(null);
  const [revokeReason, setRevokeReason] = useState('');
  const [deleteTarget, setDeleteTarget] = useState<AdminDevice | null>(null);
  const [deleteReason, setDeleteReason] = useState('');
  const [reinstateTarget, setReinstateTarget] = useState<AdminDevice | null>(null);
  const [reinstateReason, setReinstateReason] = useState('');
  const allDevices = useMemo(() => query.data ?? [], [query.data]);
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return allDevices;
    return allDevices.filter((d) => `${d.employeeName} ${d.employeeCode ?? ''} ${d.deviceName ?? ''} ${d.platform}`.toLowerCase().includes(q));
  }, [allDevices, search]);
  const activeCount = allDevices.filter((d) => d.status === 'active').length;
  const terminatedCount = allDevices.filter((d) => d.status === 'revoked' || d.status === 'replaced' || d.status === 'auto_revoked').length;

  function executeRevoke() {
    if (!revokeTarget) return;
    revoke.mutate({ deviceId: revokeTarget.id, reason: revokeReason || undefined }, {
      onSuccess: () => { setRevokeTarget(null); setRevokeReason(''); },
    });
  }
  function executeDelete() {
    if (!deleteTarget) return;
    remove.mutate({ deviceId: deleteTarget.id, reason: deleteReason || undefined }, {
      onSuccess: () => { setDeleteTarget(null); setDeleteReason(''); },
    });
  }
  function executeReinstate() {
    if (!reinstateTarget) return;
    reinstate.mutate({ deviceId: reinstateTarget.id, reason: reinstateReason || undefined }, {
      onSuccess: () => { setReinstateTarget(null); setReinstateReason(''); },
    });
  }

  if (query.isLoading) return (<div className="space-y-5"><MetricSkeletonRow count={3} /><ListSkeleton rows={4} /></div>);
  if (query.isError) return <ErrorState onRetry={() => void query.refetch()} />;

  return (
    <div className="space-y-5">
      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <MetricCard label="إجمالي الأجهزة" value={allDevices.length} icon={MonitorSmartphone} hint={showTerminated ? 'بما فيها المنتهية' : 'بدون المنتهية'} />
        <MetricCard label="أجهزة نشطة" value={activeCount} icon={Shield} hint="أجهزة معتمدة ونشطة حالياً" />
        <MetricCard label="منتهية" value={terminatedCount} icon={ShieldOff} hint="ملغاة أو مستبدلة" />
      </section>
      <FilterBar searchValue={search} onSearchChange={setSearch} searchPlaceholder="بحث باسم الموظف أو الكود أو اسم الجهاز..." resultText={`${filtered.length} من ${allDevices.length} جهاز`} isDirty={search !== '' || statusFilter !== '' || showTerminated} onClear={() => { setSearch(''); setStatusFilter(''); setShowTerminated(false); }}>
        <select className="input" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} aria-label="تصفية حسب الحالة">
          <option value="">كل الحالات</option>
          <option value="pending">بانتظار الموافقة</option>
          <option value="active">نشط</option>
          <option value="blocked">محظور</option>
          {showTerminated ? (<><option value="revoked">ملغي</option><option value="replaced">مُستبدَل</option><option value="auto_revoked">إلغاء تلقائي</option></>) : null}
        </select>
        <button type="button" className={showTerminated ? 'btn-secondary' : 'btn-ghost'} onClick={() => { setShowTerminated((v) => !v); if (statusFilter === 'revoked' || statusFilter === 'replaced' || statusFilter === 'auto_revoked') { setStatusFilter(''); } }} aria-label={showTerminated ? 'إخفاء الأجهزة المنتهية' : 'إظهار الأجهزة المنتهية'}>
          {showTerminated ? <EyeOff className="size-4" aria-hidden="true" /> : <Eye className="size-4" aria-hidden="true" />}
          {showTerminated ? 'إخفاء المنتهية' : 'إظهار المنتهية'}
        </button>
      </FilterBar>
      {filtered.length === 0 ? (
        <EmptyState title="لا توجد أجهزة" description={allDevices.length === 0 ? 'لم يسجّل أي موظف جهازاً بعد.' : 'لا توجد نتائج مطابقة للبحث.'} />
      ) : (
        <section className="space-y-3" aria-label="كل الأجهزة">
          {filtered.map((device) => (<AdminDeviceCard key={device.id} device={device} onRevoke={setRevokeTarget} onDelete={setDeleteTarget} onReinstate={setReinstateTarget} isRevokePending={revoke.isPending} isDeletePending={remove.isPending} isReinstatePending={reinstate.isPending} />))}
        </section>
      )}
      {revokeTarget ? (
        <DialogOverlay title="إلغاء صلاحية الجهاز" onClose={() => setRevokeTarget(null)} maxWidth="max-w-md">
          <p className="text-sm leading-7 text-[var(--text-muted)]">هل تريد إلغاء صلاحية جهاز &quot;{revokeTarget.deviceName ?? revokeTarget.platform}&quot; للموظف {revokeTarget.employeeName}؟ سيتم تسجيل خروج الموظف من جميع الجلسات وإلغاء إشعارات الجهاز.</p>
          <div className="mt-4">
            <label className="text-sm font-bold" htmlFor="revoke-reason">سبب الإلغاء (اختياري)</label>
            <textarea id="revoke-reason" className="input mt-1 w-full" rows={2} value={revokeReason} onChange={(e) => setRevokeReason(e.target.value)} placeholder="مثال: جهاز مفقود أو مشبوه" />
          </div>
          {revoke.isError ? <div className="mt-3"><ErrorBanner message={safeErrorMessage(revoke.error)} /></div> : null}
          <div className="mt-4 flex gap-2 justify-end">
            <button type="button" className="btn-secondary" onClick={() => setRevokeTarget(null)}>إلغاء</button>
            <button type="button" className="btn-danger" disabled={revoke.isPending} onClick={executeRevoke}>{revoke.isPending ? 'جارٍ الإلغاء...' : 'إلغاء الصلاحية'}</button>
          </div>
        </DialogOverlay>
      ) : null}
      {deleteTarget ? (
        <DialogOverlay title="حذف الجهاز نهائياً" onClose={() => setDeleteTarget(null)} maxWidth="max-w-md">
          <p className="text-sm leading-7 text-[var(--danger)]">تحذير: سيتم حذف جهاز &quot;{deleteTarget.deviceName ?? deleteTarget.platform}&quot; للموظف {deleteTarget.employeeName} نهائياً. لا يمكن التراجع عن هذا الإجراء.</p>
          <div className="mt-4">
            <label className="text-sm font-bold" htmlFor="delete-reason">سبب الحذف (اختياري)</label>
            <textarea id="delete-reason" className="input mt-1 w-full" rows={2} value={deleteReason} onChange={(e) => setDeleteReason(e.target.value)} placeholder="مثال: تنظيف أجهزة قديمة" />
          </div>
          {remove.isError ? <div className="mt-3"><ErrorBanner message={safeErrorMessage(remove.error)} /></div> : null}
          <div className="mt-4 flex gap-2 justify-end">
            <button type="button" className="btn-secondary" onClick={() => setDeleteTarget(null)}>إلغاء</button>
            <button type="button" className="btn-danger" disabled={remove.isPending} onClick={executeDelete}>{remove.isPending ? 'جارٍ الحذف...' : 'حذف نهائي'}</button>
          </div>
        </DialogOverlay>
      ) : null}
      {reinstateTarget ? (
        <DialogOverlay title="إعادة تفعيل الجهاز" onClose={() => setReinstateTarget(null)} maxWidth="max-w-md">
          <p className="text-sm leading-7 text-[var(--text-muted)]">هل تريد إعادة جهاز &quot;{reinstateTarget.deviceName ?? reinstateTarget.platform}&quot; للموظف {reinstateTarget.employeeName} إلى قائمة الانتظار للمراجعة؟ سيحتاج الجهاز لموافقة جديدة قبل تفعيله.</p>
          <div className="mt-4">
            <label className="text-sm font-bold" htmlFor="reinstate-reason">سبب إعادة التفعيل (اختياري)</label>
            <textarea id="reinstate-reason" className="input mt-1 w-full" rows={2} value={reinstateReason} onChange={(e) => setReinstateReason(e.target.value)} placeholder="مثال: تم التحقق من الجهاز وهو آمن" />
          </div>
          {reinstate.isError ? <div className="mt-3"><ErrorBanner message={safeErrorMessage(reinstate.error)} /></div> : null}
          <div className="mt-4 flex gap-2 justify-end">
            <button type="button" className="btn-secondary" onClick={() => setReinstateTarget(null)}>إلغاء</button>
            <button type="button" className="btn-primary" disabled={reinstate.isPending} onClick={executeReinstate}>{reinstate.isPending ? 'جارٍ الإعادة...' : 'إعادة للمراجعة'}</button>
          </div>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

function PendingDeviceCard({ device, onAction, isPending }: { device: PendingDevice; onAction: (device: PendingDevice, approved: boolean) => void; isPending: boolean; }) {
  const registeredDate = new Date(device.registeredAt);
  const dateStr = registeredDate.toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' });
  const timeStr = registeredDate.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' });
  const platformLabel = device.platform === 'android' ? 'أندرويد' : device.platform === 'ios' ? 'آيفون' : device.platform;
  return (
    <article className="card p-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex items-start gap-3 min-w-0">
          <UserAvatar displayName={device.employeeName} photoUrl={device.employeePhotoUrl} size="md" />
          <div className="min-w-0">
            <p className="font-black truncate">{device.employeeName}</p>
            <p className="text-sm text-[var(--text-muted)]">{device.employeeCode ?? 'بدون كود'}</p>
            <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-[var(--text-muted)]">
              <span className="flex items-center gap-1"><Smartphone className="size-3.5" aria-hidden="true" />{device.deviceName ?? platformLabel}</span>
              <span className="text-xs">•</span><span>{platformLabel}</span><span className="text-xs">•</span><StatusBadge status={device.status} />
            </div>
            {device.rejectionReason ? <p className="mt-1 text-xs text-[var(--danger)]">سبب الرفض: {device.rejectionReason}</p> : null}
            <p className="mt-1 text-xs text-[var(--text-muted)]">تاريخ التسجيل: {dateStr} — {timeStr}</p>
          </div>
        </div>
        <div className="flex gap-2 shrink-0 self-end sm:self-center">
          <button type="button" className="btn-primary" disabled={isPending} onClick={() => onAction(device, true)} aria-label={`الموافقة على جهاز ${device.employeeName}`}><CheckCircle2 className="size-4" aria-hidden="true" />موافقة</button>
          <button type="button" className="btn-danger" disabled={isPending} onClick={() => onAction(device, false)} aria-label={`رفض جهاز ${device.employeeName}`}><Ban className="size-4" aria-hidden="true" />رفض</button>
        </div>
      </div>
    </article>
  );
}

const revocationSourceLabels: Record<string, string> = { admin: 'إلغاء إداري', employee: 'طلب الموظف', replacement: 'استبدال بجهاز جديد' };
const terminatedStatuses: AdminDevice['status'][] = ['revoked', 'replaced', 'auto_revoked'];

function AdminDeviceCard({ device, onRevoke, onDelete, onReinstate, isRevokePending, isDeletePending, isReinstatePending }: { device: AdminDevice; onRevoke: (device: AdminDevice) => void; onDelete: (device: AdminDevice) => void; onReinstate: (device: AdminDevice) => void; isRevokePending: boolean; isDeletePending: boolean; isReinstatePending: boolean; }) {
  const registeredDate = new Date(device.registeredAt);
  const dateStr = registeredDate.toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' });
  const platformLabel = device.platform === 'android' ? 'أندرويد' : device.platform === 'ios' ? 'آيفون' : device.platform;
  const canRevoke = device.status === 'active';
  const canReinstate = ['revoked', 'auto_revoked', 'blocked'].includes(device.status);
  const canDelete = terminatedStatuses.includes(device.status);
  return (
    <article className="card p-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex items-start gap-3 min-w-0">
          <div className="mt-1 flex size-10 items-center justify-center rounded-full bg-[var(--surface-alt)]"><Smartphone className="size-5 text-[var(--text-muted)]" aria-hidden="true" /></div>
          <div className="min-w-0">
            <p className="font-black truncate">{device.employeeName}</p>
            <p className="text-sm text-[var(--text-muted)]">{device.employeeCode ?? 'بدون كود'}</p>
            <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-[var(--text-muted)]">
              <span>{device.deviceName ?? platformLabel}</span><span className="text-xs">•</span><span>{platformLabel}</span><span className="text-xs">•</span><StatusBadge status={device.status} />
            </div>
            {device.revocationSource ? <p className="mt-1 text-xs text-[var(--text-muted)]">سبب الإلغاء: {revocationSourceLabels[device.revocationSource] ?? device.revocationSource}</p> : null}
            {device.rejectionReason ? <p className="mt-1 text-xs text-[var(--danger)]">ملاحظة: {device.rejectionReason}</p> : null}
            <p className="mt-1 text-xs text-[var(--text-muted)]">تاريخ التسجيل: {dateStr}{device.approvedAt ? ` — تمت الموافقة: ${new Date(device.approvedAt).toLocaleDateString('ar-EG')}` : ''}{device.revokedAt ? ` — تم الإلغاء: ${new Date(device.revokedAt).toLocaleDateString('ar-EG')}` : ''}</p>
          </div>
        </div>
        {canRevoke ? (
          <div className="flex gap-2 shrink-0 self-end sm:self-center">
            <button type="button" className="btn-danger" disabled={isRevokePending} onClick={() => onRevoke(device)} aria-label={`إلغاء صلاحية جهاز ${device.employeeName}`}><ShieldOff className="size-4" />إلغاء الصلاحية</button>
          </div>
        ) : canReinstate ? (
          <div className="flex gap-2 shrink-0 self-end sm:self-center">
            <button type="button" className="btn-secondary" disabled={isReinstatePending} onClick={() => onReinstate(device)} aria-label={`إعادة تفعيل جهاز ${device.employeeName}`}><RotateCcw className="size-4" />إعادة للمراجعة</button>
            {canDelete ? <button type="button" className="btn-ghost" disabled={isDeletePending} onClick={() => onDelete(device)} aria-label={`حذف جهاز ${device.employeeName} نهائياً`}><Trash2 className="size-4" />حذف</button> : null}
          </div>
        ) : canDelete ? (
          <div className="flex gap-2 shrink-0 self-end sm:self-center">
            <button type="button" className="btn-ghost" disabled={isDeletePending} onClick={() => onDelete(device)} aria-label={`حذف جهاز ${device.employeeName} نهائياً`}><Trash2 className="size-4" />حذف</button>
          </div>
        ) : null}
      </div>
    </article>
  );
}
