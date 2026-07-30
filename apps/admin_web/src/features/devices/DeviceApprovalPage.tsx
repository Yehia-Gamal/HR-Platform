import { Ban, CheckCircle2, Clock3, MonitorSmartphone, Shield, ShieldAlert, ShieldOff, Smartphone } from 'lucide-react';
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
import { useToast } from '../../ui/Toast';
import type { AdminDevice, PendingDevice } from './useDevices';
import { useAllDevices, useApproveDevice, useDeviceApprovals, useRevokeDevice } from './useDevices';

type Tab = 'pending' | 'all';

export function DeviceApprovalPage() {
  const [tab, setTab] = useState<Tab>('pending');

  return (
    <div className="space-y-5">
      <PageHeader title="أجهزة الموظفين" description="مراجعة وموافقة على أجهزة الموظفين وإدارة الأجهزة المسجلة" />

      {/* ألسنة */}
      <Tabs
        tabs={[
          { id: 'pending', label: 'طلبات الأجهزة' },
          { id: 'all', label: 'كل الأجهزة' },
        ]}
        activeTab={tab}
        onTabChange={(id) => setTab(id as Tab)}
        ariaLabel="أقسام الأجهزة"
      >
        {tab === 'pending' ? <PendingDevicesPanel /> : <AllDevicesPanel />}
      </Tabs>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════════
   لسان طلبات الأجهزة (المعلّقة والمحظورة)
   ═══════════════════════════════════════════════════════════════════════════════ */

function PendingDevicesPanel() {
  const query = useDeviceApprovals();
  const approve = useApproveDevice();
  const { toast } = useToast();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [confirmAction, setConfirmAction] = useState<{ device: PendingDevice; approved: boolean } | null>(null);
  const [reason, setReason] = useState('');

  const allDevices = query.data ?? [];
  const filtered = useMemo(() => allDevices.filter((d) => {
    const q = search.trim().toLowerCase();
    const matchesSearch = !q || `${d.employeeName} ${d.employeeCode ?? ''} ${d.deviceName ?? ''} ${d.platform}`.toLowerCase().includes(q);
    return matchesSearch && (statusFilter === 'all' || d.status === statusFilter);
  }), [allDevices, search, statusFilter]);

  const pendingCount = allDevices.filter((d) => d.status === 'pending').length;
  const blockedCount = allDevices.filter((d) => d.status === 'blocked').length;

  function handleAction(device: PendingDevice, approved: boolean) {
    setConfirmAction({ device, approved });
    setReason('');
  }

  function executeAction() {
    if (!confirmAction) return;
    const wasApproved = confirmAction.approved;
    approve.mutate(
      { deviceId: confirmAction.device.id, approved: confirmAction.approved, reason: confirmAction.approved ? undefined : reason || undefined },
      {
        onSuccess: () => {
          setConfirmAction(null);
          toast({ message: wasApproved ? 'تمت الموافقة على الجهاز بنجاح' : 'تم رفض الجهاز بنجاح', tone: 'success' });
        },
        onError: (error) => {
          toast({ message: safeErrorMessage(error), tone: 'error' });
        },
      },
    );
  }

  if (query.isLoading) {
    return (
      <div className="space-y-5">
        <MetricSkeletonRow count={3} />
        <ListSkeleton rows={4} />
      </div>
    );
  }

  if (query.isError) {
    return <ErrorState onRetry={() => void query.refetch()} />;
  }

  return (
    <div className="space-y-5">
      {/* مقاييس */}
      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <MetricCard label="إجمالي المعلّقة" value={allDevices.length} icon={MonitorSmartphone} hint="أجهزة تنتظر المراجعة أو محظورة" />
        <MetricCard label="بانتظار الموافقة" value={pendingCount} icon={Clock3} hint="أجهزة جديدة لم تُراجع بعد" />
        <MetricCard label="محظورة" value={blockedCount} icon={ShieldAlert} hint="أجهزة تم رفضها وتحتاج مراجعة" />
      </section>

      {/* فلاتر */}
      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث باسم الموظف أو الكود أو اسم الجهاز..."
        resultText={`${filtered.length} من ${allDevices.length} جهاز`}
        isDirty={search !== '' || statusFilter !== 'all'}
        onClear={() => { setSearch(''); setStatusFilter('all'); }}
      >
        <select
          className="input"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          aria-label="تصفية حسب الحالة"
        >
          <option value="all">كل الحالات</option>
          <option value="pending">بانتظار الموافقة</option>
          <option value="blocked">محظور</option>
        </select>
      </FilterBar>

      {/* قائمة الأجهزة */}
      {filtered.length === 0 ? (
        <EmptyState
          title="لا توجد أجهزة معلّقة"
          description={allDevices.length === 0 ? 'لم يسجّل أي موظف جهازاً جديداً بعد.' : 'لا توجد نتائج مطابقة للفلاتر المحددة.'}
        />
      ) : (
        <section className="space-y-3" aria-label="قائمة الأجهزة">
          {filtered.map((device) => (
            <PendingDeviceCard key={device.id} device={device} onAction={handleAction} isPending={approve.isPending} />
          ))}
        </section>
      )}

      {/* حوار التأكيد */}
      {confirmAction ? (
        <DialogOverlay title={confirmAction.approved ? 'تأكيد الموافقة' : 'تأكيد الرفض'} onClose={() => setConfirmAction(null)} maxWidth="max-w-md">
          <p className="text-sm leading-7 text-[var(--text-muted)]">
            {confirmAction.approved
              ? `هل تريد الموافقة على جهاز "${confirmAction.device.deviceName ?? confirmAction.device.platform}" للموظف ${confirmAction.device.employeeName}؟ سيتمكن الموظف من تسجيل الحضور عبر هذا الجهاز.`
              : `هل تريد رفض جهاز "${confirmAction.device.deviceName ?? confirmAction.device.platform}" للموظف ${confirmAction.device.employeeName}؟`}
          </p>
          {!confirmAction.approved ? (
            <div className="mt-4">
              <label className="text-sm font-bold" htmlFor="rejection-reason">سبب الرفض (اختياري)</label>
              <textarea
                id="rejection-reason"
                className="input mt-1 w-full"
                rows={2}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="مثال: الجهاز غير مسجل ضمن الأجهزة المعتمدة"
              />
            </div>
          ) : null}
          {approve.isError ? <div className="mt-3"><ErrorBanner message={safeErrorMessage(approve.error)} /></div> : null}
          <div className="mt-4 flex gap-2 justify-end">
            <button type="button" className="btn-secondary" onClick={() => setConfirmAction(null)}>إلغاء</button>
            <button
              type="button"
              className={confirmAction.approved ? 'btn-primary' : 'btn-danger'}
              disabled={approve.isPending}
              onClick={executeAction}
            >
              {approve.isPending ? 'جارٍ التنفيذ...' : confirmAction.approved ? 'موافقة' : 'رفض'}
            </button>
          </div>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════════
   لسان كل الأجهزة — عرض + إلغاء إداري
   ═══════════════════════════════════════════════════════════════════════════════ */

function AllDevicesPanel() {
  const [statusFilter, setStatusFilter] = useState<string>('');
  const query = useAllDevices(statusFilter || undefined);
  const revoke = useRevokeDevice();
  const { toast } = useToast();
  const [search, setSearch] = useState('');
  const [revokeTarget, setRevokeTarget] = useState<AdminDevice | null>(null);
  const [revokeReason, setRevokeReason] = useState('');

  const allDevices = query.data ?? [];
  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return allDevices;
    return allDevices.filter((d) =>
      `${d.employeeName} ${d.employeeCode ?? ''} ${d.deviceName ?? ''} ${d.platform}`.toLowerCase().includes(q),
    );
  }, [allDevices, search]);

  const activeCount = allDevices.filter((d) => d.status === 'active').length;
  const revokedCount = allDevices.filter((d) => d.status === 'revoked' || d.status === 'auto_revoked').length;

  function executeRevoke() {
    if (!revokeTarget) return;
    revoke.mutate(
      { deviceId: revokeTarget.id, reason: revokeReason || undefined },
      {
        onSuccess: () => {
          setRevokeTarget(null);
          setRevokeReason('');
          toast({ message: 'تم إلغاء صلاحية الجهاز بنجاح', tone: 'success' });
        },
        onError: (error) => {
          toast({ message: safeErrorMessage(error), tone: 'error' });
        },
      },
    );
  }

  if (query.isLoading) {
    return (
      <div className="space-y-5">
        <MetricSkeletonRow count={3} />
        <ListSkeleton rows={4} />
      </div>
    );
  }

  if (query.isError) {
    return <ErrorState onRetry={() => void query.refetch()} />;
  }

  return (
    <div className="space-y-5">
      {/* مقاييس */}
      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <MetricCard label="إجمالي الأجهزة" value={allDevices.length} icon={MonitorSmartphone} hint="جميع الأجهزة المسجلة" />
        <MetricCard label="أجهزة نشطة" value={activeCount} icon={Shield} hint="أجهزة معتمدة ونشطة حالياً" />
        <MetricCard label="ملغاة" value={revokedCount} icon={ShieldOff} hint="أجهزة تم إلغاء صلاحياتها" />
      </section>

      {/* فلاتر */}
      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث باسم الموظف أو الكود أو اسم الجهاز..."
        resultText={`${filtered.length} من ${allDevices.length} جهاز`}
        isDirty={search !== '' || statusFilter !== ''}
        onClear={() => { setSearch(''); setStatusFilter(''); }}
      >
        <select
          className="input"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          aria-label="تصفية حسب الحالة"
        >
          <option value="">كل الحالات</option>
          <option value="pending">بانتظار الموافقة</option>
          <option value="active">نشط</option>
          <option value="blocked">محظور</option>
          <option value="revoked">ملغي</option>
          <option value="replaced">مُستبدَل</option>
          <option value="auto_revoked">إلغاء تلقائي</option>
        </select>
      </FilterBar>

      {/* قائمة الأجهزة */}
      {filtered.length === 0 ? (
        <EmptyState
          title="لا توجد أجهزة"
          description={allDevices.length === 0 ? 'لم يسجّل أي موظف جهازاً بعد.' : 'لا توجد نتائج مطابقة للبحث.'}
        />
      ) : (
        <section className="space-y-3" aria-label="كل الأجهزة">
          {filtered.map((device) => (
            <AdminDeviceCard key={device.id} device={device} onRevoke={setRevokeTarget} isPending={revoke.isPending} />
          ))}
        </section>
      )}

      {/* حوار إلغاء الجهاز */}
      {revokeTarget ? (
        <DialogOverlay title="إلغاء صلاحية الجهاز" onClose={() => setRevokeTarget(null)} maxWidth="max-w-md">
          <p className="text-sm leading-7 text-[var(--text-muted)]">
            هل تريد إلغاء صلاحية جهاز &quot;{revokeTarget.deviceName ?? revokeTarget.platform}&quot; للموظف {revokeTarget.employeeName}؟
            سيتم تسجيل خروج الموظف من جميع الجلسات وإلغاء إشعارات الجهاز.
          </p>
          <div className="mt-4">
            <label className="text-sm font-bold" htmlFor="revoke-reason">سبب الإلغاء (اختياري)</label>
            <textarea
              id="revoke-reason"
              className="input mt-1 w-full"
              rows={2}
              value={revokeReason}
              onChange={(e) => setRevokeReason(e.target.value)}
              placeholder="مثال: جهاز مفقود أو مشبوه"
            />
          </div>
          {revoke.isError ? <div className="mt-3"><ErrorBanner message={safeErrorMessage(revoke.error)} /></div> : null}
          <div className="mt-4 flex gap-2 justify-end">
            <button type="button" className="btn-secondary" onClick={() => setRevokeTarget(null)}>إلغاء</button>
            <button
              type="button"
              className="btn-danger"
              disabled={revoke.isPending}
              onClick={executeRevoke}
            >
              {revoke.isPending ? 'جارٍ الإلغاء...' : 'إلغاء الصلاحية'}
            </button>
          </div>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════════
   بطاقات الأجهزة
   ═══════════════════════════════════════════════════════════════════════════════ */

function PendingDeviceCard({
  device,
  onAction,
  isPending,
}: {
  device: PendingDevice;
  onAction: (device: PendingDevice, approved: boolean) => void;
  isPending: boolean;
}) {
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
              <span className="text-xs">•</span>
              <span>{platformLabel}</span>
              <span className="text-xs">•</span>
              <StatusBadge status={device.status} />
            </div>
            {device.rejectionReason ? (
              <p className="mt-1 text-xs text-[var(--danger)]">سبب الرفض: {device.rejectionReason}</p>
            ) : null}
            <p className="mt-1 text-xs text-[var(--text-muted)]">تاريخ التسجيل: {dateStr} — {timeStr}</p>
          </div>
        </div>

        <div className="flex gap-2 shrink-0 self-end sm:self-center">
          <button
            type="button"
            className="btn-primary"
            disabled={isPending}
            onClick={() => onAction(device, true)}
            aria-label={`الموافقة على جهاز ${device.employeeName}`}
          >
            <CheckCircle2 className="size-4" aria-hidden="true" />موافقة
          </button>
          <button
            type="button"
            className="btn-danger"
            disabled={isPending}
            onClick={() => onAction(device, false)}
            aria-label={`رفض جهاز ${device.employeeName}`}
          >
            <Ban className="size-4" aria-hidden="true" />رفض
          </button>
        </div>
      </div>
    </article>
  );
}

const revocationSourceLabels: Record<string, string> = {
  admin: 'إلغاء إداري',
  employee: 'طلب الموظف',
  replacement: 'استبدال بجهاز جديد',
};

function AdminDeviceCard({
  device,
  onRevoke,
  isPending,
}: {
  device: AdminDevice;
  onRevoke: (device: AdminDevice) => void;
  isPending: boolean;
}) {
  const registeredDate = new Date(device.registeredAt);
  const dateStr = registeredDate.toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' });
  const platformLabel = device.platform === 'android' ? 'أندرويد' : device.platform === 'ios' ? 'آيفون' : device.platform;
  const canRevoke = device.status === 'active';

  return (
    <article className="card p-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex items-start gap-3 min-w-0">
          <div className="mt-1 flex size-10 items-center justify-center rounded-full bg-[var(--surface-alt)]">
            <Smartphone className="size-5 text-[var(--text-muted)]" aria-hidden="true" />
          </div>
          <div className="min-w-0">
            <p className="font-black truncate">{device.employeeName}</p>
            <p className="text-sm text-[var(--text-muted)]">{device.employeeCode ?? 'بدون كود'}</p>
            <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-[var(--text-muted)]">
              <span>{device.deviceName ?? platformLabel}</span>
              <span className="text-xs">•</span>
              <span>{platformLabel}</span>
              <span className="text-xs">•</span>
              <StatusBadge status={device.status} />
            </div>
            {device.revocationSource ? (
              <p className="mt-1 text-xs text-[var(--text-muted)]">سبب الإلغاء: {revocationSourceLabels[device.revocationSource] ?? device.revocationSource}</p>
            ) : null}
            {device.rejectionReason ? (
              <p className="mt-1 text-xs text-[var(--danger)]">ملاحظة: {device.rejectionReason}</p>
            ) : null}
            <p className="mt-1 text-xs text-[var(--text-muted)]">تاريخ التسجيل: {dateStr}{device.approvedAt ? ` — تمت الموافقة: ${new Date(device.approvedAt).toLocaleDateString('ar-EG')}` : ''}{device.revokedAt ? ` — تم الإلغاء: ${new Date(device.revokedAt).toLocaleDateString('ar-EG')}` : ''}</p>
          </div>
        </div>

        {canRevoke ? (
          <div className="flex gap-2 shrink-0 self-end sm:self-center">
            <button
              type="button"
              className="btn-danger"
              disabled={isPending}
              onClick={() => onRevoke(device)}
              aria-label={`إلغاء صلاحية جهاز ${device.employeeName}`}
            >
              <ShieldOff className="size-4" />إلغاء الصلاحية
            </button>
          </div>
        ) : null}
      </div>
    </article>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════════
   مكونات مساعدة
   ═══════════════════════════════════════════════════════════════════════════════ */
