import {
  ArrowRight, BadgeCheck, BriefcaseBusiness, CalendarDays, Clock3, FileText,
  Archive, Gauge, MailCheck, Network, Phone, ShieldCheck, UserRound, UsersRound,
} from 'lucide-react';
import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useEmployee360, useResendInvite, useEmployees, useChangeManager, useArchiveEmployee } from './useEmployees';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

// Accounts that have not finished activation can still be re-invited.
const PENDING_ACCOUNT_STATES = new Set(['invited', 'onboarding', 'pending', 'draft']);

export function EmployeeDetailPage() {
  const { employeeId } = useParams();
  const auth = useAuth();
  const query = useEmployee360(employeeId);
  const resend = useResendInvite();
  const [resendMessage, setResendMessage] = useState<string | null>(null);
  const [resendError, setResendError] = useState<string | null>(null);
  const [showManagerDialog, setShowManagerDialog] = useState(false);
  const [showArchiveDialog, setShowArchiveDialog] = useState(false);
  const item = query.data;

  if (query.isError) {
    return <ErrorState title="تعذر فتح ملف الموظف" description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} />;
  }
  if (query.isLoading) {
    return <SkeletonCard className="h-72" />;
  }
  if (!item) {
    return <EmptyState title="تعذر فتح ملف الموظف" description="الملف غير موجود أو خارج نطاق صلاحيتك." />;
  }

  const canInvite = Boolean(auth.access && hasPermission(auth.access, 'people.employee.create'));
  const canEdit = Boolean(auth.access && (
    hasPermission(auth.access, 'people.employee.update_sensitive')
    || hasPermission(auth.access, 'people.employee.update_basic')
  ));
  const accountPending = PENDING_ACCOUNT_STATES.has((item.accountStatus ?? item.status ?? '').toLowerCase());
  const showResend = canInvite && accountPending && Boolean(employeeId);

  const onResend = async () => {
    if (!employeeId) return;
    setResendMessage(null); setResendError(null);
    try {
      setResendMessage(await resend.mutateAsync(employeeId));
    } catch (error) {
      setResendError(error instanceof Error ? error.message : 'تعذر إعادة إرسال الدعوة.');
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="ملف الموظف 360°"
        description="ملخص موحّد للبيانات الوظيفية والحضور والطلبات والأداء والمستندات والعهد، بعد تطبيق RLS والنطاق الفعلي."
        actions={<div className="flex flex-wrap gap-2">
          {showResend ? <button type="button" className="btn-secondary" disabled={resend.isPending} onClick={() => void onResend()}><MailCheck className="size-4" aria-hidden="true" />{resend.isPending ? 'جارٍ الإرسال…' : 'إعادة إرسال دعوة التفعيل'}</button> : null}
          {canEdit && item.isActive ? <button type="button" className="btn-secondary text-[var(--danger)]" onClick={() => setShowArchiveDialog(true)}><Archive className="size-4" aria-hidden="true" />أرشفة الموظف</button> : null}
          <Link to="/hr/employees" className="btn-secondary"><ArrowRight className="size-4" aria-hidden="true" />عودة للموظفين</Link>
        </div>}
      />

      {resendMessage ? <div className="flex gap-2 rounded-xl border border-[var(--success)] bg-[var(--success-soft)] p-4 text-sm text-[var(--success)]"><MailCheck className="size-5 shrink-0" aria-hidden="true" />{resendMessage}</div> : null}
      {resendError ? <div role="alert" className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-4 text-sm text-[var(--danger)]">{resendError}</div> : null}

      <section className="card flex flex-col gap-5 p-5 lg:flex-row lg:items-center">
        <UserAvatar displayName={item.fullNameAr} photoUrl={item.photoUrl} size="lg" eager />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-3"><h2 className="text-2xl font-black">{item.fullNameAr}</h2><StatusBadge status={item.status} /></div>
          <p className="muted mt-1">{item.jobTitle ?? item.position ?? 'بدون مسمى وظيفي'} • {item.employeeCode}</p>
          <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-sm">
            <Info icon={Network} label={item.department ?? 'بدون إدارة'} />
            <Info icon={UsersRound} label={item.team ?? 'بدون فريق'} />
            <Info icon={Phone} label={item.phoneE164 ?? 'بدون هاتف'} dir="ltr" />
            <Info icon={ShieldCheck} label={`الحساب: ${item.accountStatus ?? 'غير مرتبط'}`} />
          </div>
        </div>
        <div className="rounded-2xl bg-[var(--surface-muted)] p-4 text-sm lg:min-w-64">
          <p className="font-black">العلاقة الإدارية</p>
          <div className="mt-2 flex items-center justify-between gap-2">
            <p className="muted">المدير المباشر: <span className="font-bold text-[var(--text)]">{item.managerName ?? 'غير معين'}</span></p>
            {canEdit ? <button type="button" onClick={() => setShowManagerDialog(true)} className="text-brand font-bold text-xs">تغيير</button> : null}
          </div>
          <p className="muted mt-1">المرؤوسون المباشرون: {item.directReports}</p>
          <div className="mt-1 flex items-center justify-between gap-2">
            <p className="muted">الأدوار: {item.roles.map((role) => role.name).join('، ') || 'لا توجد'}</p>
            {hasPermission(auth.access!, 'access.role.read') ? <Link to="/admin/access" className="text-brand font-bold text-xs">إدارة الصلاحيات</Link> : null}
          </div>
        </div>
      </section>

      <section className="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="أيام الحضور — 30 يومًا" value={item.attendance30.present} hint={`${item.attendance30.lateDays} أيام تأخير`} icon={BadgeCheck} />
        <MetricCard label="أيام الغياب" value={item.attendance30.absent} icon={Clock3} />
        <MetricCard label="الطلبات المعلقة" value={item.requestCounts.pending} hint={`${item.requestCounts.approved} معتمدة`} icon={FileText} />
        <MetricCard label="أحدث تقييم" value={item.latestKpi?.finalScore ?? item.latestKpi?.currentStage ?? '—'} hint={item.latestKpi?.finalRating ?? undefined} icon={Gauge} />
      </section>

      <section className="grid gap-5 xl:grid-cols-2">
        <article className="card p-5">
          <h3 className="font-black">البيانات الوظيفية</h3>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <Data label="المنصب" value={item.position} />
            <Data label="الدرجة" value={item.grade} />
            <Data label="الفرع" value={item.branch} />
            <Data label="موقع العمل" value={item.workSite} />
            <Data label="تاريخ التعيين" value={item.hireDate ? dateFormatter.format(new Date(item.hireDate)) : null} />
            <Data label="نهاية العقد" value={item.contractEnd ? dateFormatter.format(new Date(item.contractEnd)) : null} />
          </div>
        </article>

        <article className="card p-5">
          <h3 className="font-black">المستندات والعهد</h3>
          <div className="mt-4 space-y-3">
            {item.documents.length === 0 ? <p className="muted text-sm">لا توجد مستندات متاحة.</p> : null}
            {item.documents.slice(0, 5).map((doc) => (
              <div key={doc.id} className="flex items-center justify-between rounded-xl bg-[var(--surface-muted)] p-3">
                <div><p className="font-bold">{doc.title}</p><p className="muted mt-1 text-xs">{doc.expiryDate ? `ينتهي ${dateFormatter.format(new Date(doc.expiryDate))}` : doc.type}</p></div>
                <StatusBadge value={doc.status} />
              </div>
            ))}
            {item.assets.filter((asset) => !asset.returnedAt).map((asset) => (
              <div key={asset.id} className="flex items-center justify-between rounded-xl border border-[var(--border)] p-3">
                <div><p className="font-bold">{asset.assetName}</p><p className="muted mt-1 text-xs">{asset.serial ?? asset.assetType}</p></div><BriefcaseBusiness className="size-5 text-[var(--text-muted)]" aria-label="عهدة قيد الاستلام" />
              </div>
            ))}
          </div>
        </article>
      </section>

      <section className="grid gap-5 xl:grid-cols-2">
        <article className="card overflow-hidden">
          <div className="border-b border-[var(--border)] p-5"><h3 className="font-black">أحدث الطلبات</h3></div>
          <div className="divide-y divide-[var(--border)]">
            {item.recentRequests.length === 0 ? <p className="muted p-5 text-sm">لا توجد طلبات.</p> : item.recentRequests.map((request) => (
              <div key={request.id} className="flex items-center justify-between gap-3 p-4"><div><p className="font-bold">{request.title ?? request.requestType}</p><p className="muted mt-1 text-xs">طلب #{request.requestNumber} • {dateFormatter.format(new Date(request.createdAt))}</p></div><StatusBadge value={request.status} /></div>
            ))}
          </div>
        </article>

        <article className="card overflow-hidden">
          <div className="border-b border-[var(--border)] p-5"><h3 className="font-black">أحدث المهام</h3></div>
          <div className="divide-y divide-[var(--border)]">
            {item.recentTasks.length === 0 ? <p className="muted p-5 text-sm">لا توجد مهام.</p> : item.recentTasks.map((task) => (
              <div key={task.id} className="flex items-center justify-between gap-3 p-4"><div><p className="font-bold">{task.title}</p><p className="muted mt-1 text-xs">{task.dueDate ? `الاستحقاق ${dateFormatter.format(new Date(task.dueDate))}` : 'بدون موعد'}</p></div><StatusBadge value={task.status} /></div>
            ))}
          </div>
        </article>
      </section>

      <p className="muted flex items-center gap-2 text-xs"><CalendarDays className="size-4" aria-hidden="true" />آخر تحديث: {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.lastUpdatedAt))}</p>

      {showManagerDialog && employeeId && (
        <ChangeManagerDialog
          employeeId={employeeId}
          currentManagerName={item.managerName}
          onClose={() => setShowManagerDialog(false)}
          onSuccess={() => {
            setShowManagerDialog(false);
            void query.refetch();
          }}
        />
      )}
      {showArchiveDialog && employeeId && (
        <ArchiveEmployeeDialog employeeId={employeeId} employeeName={item.fullNameAr}
          onClose={() => setShowArchiveDialog(false)}
          onSuccess={() => { setShowArchiveDialog(false); void query.refetch(); }} />
      )}
    </div>
  );
}

function ArchiveEmployeeDialog({ employeeId, employeeName, onClose, onSuccess }: { employeeId: string; employeeName: string; onClose: () => void; onSuccess: () => void }) {
  const archive = useArchiveEmployee();
  const [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const submit = async (event: React.FormEvent) => {
    event.preventDefault(); setError(null);
    try { await archive.mutateAsync({ employeeId, reason: reason.trim() }); onSuccess(); }
    catch { setError('تعذر أرشفة الموظف بأمان. تحقق من الصلاحية وأعد المحاولة.'); }
  };
  return <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
    <form onSubmit={(event) => void submit(event)} className="card w-full max-w-md p-6">
      <h2 className="text-lg font-black">أرشفة الموظف</h2>
      <p className="muted mt-2 text-sm">سيُعطّل حساب {employeeName} وتُسحب جلساته وأجهزته، مع الاحتفاظ بالسجل التاريخي.</p>
      {error ? <div role="alert" className="mt-4 rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}
      <label className="mt-4 block"><span className="mb-1.5 block text-sm font-semibold">سبب الأرشفة</span><textarea className="input min-h-24 w-full" required minLength={5} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
      <label className="mt-4 flex items-start gap-2 text-sm"><input type="checkbox" className="mt-1" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /><span>أؤكد تعطيل الحساب وسحب الجلسات والأجهزة الموثوقة.</span></label>
      <div className="mt-6 flex justify-end gap-3"><button type="button" className="btn-secondary" onClick={onClose} disabled={archive.isPending}>إلغاء</button><button type="submit" className="btn-primary" disabled={archive.isPending || !confirmed || reason.trim().length < 5}>{archive.isPending ? 'جارٍ الأرشفة…' : 'تأكيد الأرشفة'}</button></div>
    </form>
  </div>;
}

function ChangeManagerDialog({ employeeId, currentManagerName, onClose, onSuccess }: { employeeId: string; currentManagerName: string | null; onClose: () => void; onSuccess: () => void }) {
  const { data: employees } = useEmployees();
  const changeManager = useChangeManager();
  const [selectedManagerId, setSelectedManagerId] = useState<string>('');
  const [reason, setReason] = useState<string>('');
  const [error, setError] = useState<string | null>(null);

  const availableManagers = (employees ?? []).filter((e) => e.id !== employeeId && e.isActive);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await changeManager.mutateAsync({ employeeId, managerId: selectedManagerId || null, reason });
      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'تعذر تغيير المدير.');
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <form onSubmit={(e) => void onSubmit(e)} className="card w-full max-w-md p-6">
        <h2 className="text-lg font-black">تغيير المدير المباشر</h2>
        <p className="muted mt-2 text-sm">المدير الحالي: {currentManagerName ?? 'غير معين'}</p>

        {error ? <div className="mt-4 rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}

        <label className="mt-4 block">
          <span className="mb-1.5 block text-sm font-semibold">اختر المدير الجديد</span>
          <select
            className="input w-full"
            value={selectedManagerId}
            onChange={(e) => setSelectedManagerId(e.target.value)}
            disabled={changeManager.isPending}
          >
            <option value="">بدون مدير مباشر</option>
            {availableManagers.map((emp) => (
              <option key={emp.id} value={emp.id}>{emp.fullNameAr} ({emp.employeeCode})</option>
            ))}
          </select>
        </label>

        <label className="mt-4 block">
          <span className="mb-1.5 block text-sm font-semibold">سبب التغيير</span>
          <textarea
            className="input min-h-24 w-full"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            required
            minLength={3}
            disabled={changeManager.isPending}
          />
        </label>

        <div className="mt-6 flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={changeManager.isPending} className="btn-secondary">إلغاء</button>
          <button type="submit" disabled={changeManager.isPending || reason.trim().length < 3} className="btn-primary">
            {changeManager.isPending ? 'جارٍ الحفظ...' : 'حفظ التغييرات'}
          </button>
        </div>
      </form>
    </div>
  );
}

function Info({ icon: Icon, label, dir }: { icon: typeof UserRound; label: string; dir?: 'ltr' | 'rtl' }) {
  return <span className="inline-flex items-center gap-2"><Icon className="size-4 muted" aria-hidden="true" /><span dir={dir}>{label}</span></span>;
}

function Data({ label, value }: { label: string; value: string | null }) {
  return <div className="rounded-xl bg-[var(--surface-muted)] p-3"><p className="muted text-xs">{label}</p><p className="mt-1 font-bold">{value ?? '—'}</p></div>;
}
