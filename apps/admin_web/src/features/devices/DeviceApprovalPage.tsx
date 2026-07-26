import { Ban, CheckCircle2, Clock3, MonitorSmartphone, ShieldAlert, Smartphone } from 'lucide-react';
import { useMemo, useState } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import type { PendingDevice } from './useDevices';
import { useApproveDevice, useDeviceApprovals } from './useDevices';

export function DeviceApprovalPage() {
  const query = useDeviceApprovals();
  const approve = useApproveDevice();
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
    if (!approved) {
      setConfirmAction({ device, approved });
      setReason('');
      return;
    }
    setConfirmAction({ device, approved });
    setReason('');
  }

  function executeAction() {
    if (!confirmAction) return;
    approve.mutate(
      { deviceId: confirmAction.device.id, approved: confirmAction.approved, reason: confirmAction.approved ? undefined : reason || undefined },
      { onSuccess: () => setConfirmAction(null) },
    );
  }

  if (query.isLoading) {
    return (
      <div className="space-y-5">
        <PageHeader title="أجهزة الموظفين" description="مراجعة وموافقة على أجهزة الموظفين المسجلة" />
        <MetricSkeletonRow count={3} />
        <ListSkeleton rows={4} />
      </div>
    );
  }

  if (query.isError) {
    return (
      <div className="space-y-5">
        <PageHeader title="أجهزة الموظفين" description="مراجعة وموافقة على أجهزة الموظفين المسجلة" />
        <ErrorState onRetry={() => void query.refetch()} />
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <PageHeader title="أجهزة الموظفين" description="مراجعة وموافقة على أجهزة الموظفين المسجلة" />

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
            <DeviceCard key={device.id} device={device} onAction={handleAction} isPending={approve.isPending} />
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

function DeviceCard({
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
        {/* معلومات الموظف والجهاز */}
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

        {/* أزرار الإجراء */}
        <div className="flex gap-2 shrink-0 self-end sm:self-center">
          <button
            type="button"
            className="btn-primary"
            disabled={isPending}
            onClick={() => onAction(device, true)}
            aria-label={`الموافقة على جهاز ${device.employeeName}`}
          >
            <CheckCircle2 className="size-4" />موافقة
          </button>
          <button
            type="button"
            className="btn-danger"
            disabled={isPending}
            onClick={() => onAction(device, false)}
            aria-label={`رفض جهاز ${device.employeeName}`}
          >
            <Ban className="size-4" />رفض
          </button>
        </div>
      </div>
    </article>
  );
}
