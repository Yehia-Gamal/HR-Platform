import type { Employee360 } from '@ahla/shared-contracts';
import {
  ArrowRight, BadgeCheck, BriefcaseBusiness, Building2, CalendarDays, Clock3, FileText,
  Archive, Gauge, Loader2, MailCheck, Network, Pencil, Phone, Plus, ShieldCheck, Star, Trash2, UserRound, UsersRound, X,
} from 'lucide-react';
import { useMemo, useState } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { MonthlyStatementSection } from '../attendance/MonthlyStatementSection';
import {
  useEmployee360, useResendInvite, useEmployees, useChangeManager, useArchiveEmployee,
  useUpdateEmployee, useEmployeeDepartments, useAssignDepartment, useRemoveDepartment, useDeleteEmployee,
} from './useEmployees';
import { useOrganizationLookups } from './useOrganizationLookups';

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
  const [showEditDialog, setShowEditDialog] = useState(false);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const [showAddDeptDialog, setShowAddDeptDialog] = useState(false);
  const navigate = useNavigate();
  const item = query.data;

  if (query.isError) {
    const raw = query.error instanceof Error ? query.error.message : String(query.error ?? '');
    const isNotFound = /PGRST116|no rows|not found|P0002|EMPLOYEE_NOT_FOUND/i.test(raw);
    return <ErrorState
      title={isNotFound ? 'الموظف غير موجود' : 'تعذر فتح ملف الموظف'}
      description={isNotFound ? 'تم حذف أو أرشفة هذا الموظف، أو أنه خارج نطاق صلاحيتك.' : safeErrorMessage(query.error)}
      action={<div className="flex gap-3">
        {!isNotFound ? <button type="button" className="btn-secondary" onClick={() => void query.refetch()}>إعادة المحاولة</button> : null}
        <Link to="/hr/employees" className="btn-primary">العودة لقائمة الموظفين</Link>
      </div>}
    />;
  }
  if (query.isLoading) {
    return <SkeletonCard className="h-72" />;
  }
  if (!item) {
    return <ErrorState
      title="الموظف غير موجود"
      description="تم حذف أو أرشفة هذا الموظف، أو أنه خارج نطاق صلاحيتك."
      action={<Link to="/hr/employees" className="btn-primary">العودة لقائمة الموظفين</Link>}
    />;
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
      setResendError(safeErrorMessage(error));
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="ملف الموظف 360°"
        description="ملخص موحّد للبيانات الوظيفية والحضور والطلبات والأداء والمستندات والعهد، بعد تطبيق RLS والنطاق الفعلي."
        actions={<div className="flex flex-wrap gap-2">
          {showResend ? <button type="button" className="btn-secondary" disabled={resend.isPending} onClick={() => void onResend()}><MailCheck className="size-4" aria-hidden="true" />{resend.isPending ? 'جارٍ الإرسال…' : 'إعادة إرسال دعوة التفعيل'}</button> : null}
          {canEdit ? <button type="button" className="btn-primary" onClick={() => setShowEditDialog(true)}><Pencil className="size-4" aria-hidden="true" />تعديل البيانات</button> : null}
          {canEdit && item.isActive ? <button type="button" className="btn-secondary text-[var(--danger)]" onClick={() => setShowArchiveDialog(true)}><Archive className="size-4" aria-hidden="true" />أرشفة الموظف</button> : null}
          {canEdit && auth.access?.workspaces.includes('main_admin') ? <button type="button" className="btn-secondary text-[var(--danger)]" onClick={() => setShowDeleteDialog(true)}><Trash2 className="size-4" aria-hidden="true" />حذف نهائي</button> : null}
          <Link to="/hr/employees" className="btn-secondary"><ArrowRight className="size-4" aria-hidden="true" />عودة للموظفين</Link>
        </div>}
      />

      {resendMessage ? <div className="flex gap-2 rounded-xl border border-[var(--success)] bg-[var(--success-soft)] p-4 text-sm text-[var(--success)]"><MailCheck className="size-5 shrink-0" aria-hidden="true" />{resendMessage}</div> : null}
      {resendError ? <div role="alert" className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-4 text-sm text-[var(--danger)]">{resendError}</div> : null}

      <section className="card flex flex-col gap-5 p-5 lg:flex-row lg:items-center">
        <UserAvatar displayName={item.fullNameAr} photoUrl={item.photoUrl} size="lg" eager />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-3"><h2 className="text-2xl font-black">{item.fullNameAr}</h2><StatusBadge status={item.status} /></div>
          <p className="muted mt-1">{item.jobTitle ?? 'بدون مسمى وظيفي'} • {item.employeeCode}</p>
          <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-sm">
            <Info icon={Network} label={item.department ?? 'بدون إدارة'} />
            {item.departments.length > 1 && <span className="inline-flex items-center gap-1 rounded-full bg-[var(--brand-soft)] px-2 py-0.5 text-xs font-bold text-[var(--brand)]"><Building2 className="size-3" aria-hidden="true" />+{item.departments.length - 1} إدارة أخرى</span>}
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
            <Data label="الدرجة" value={item.grade} />
            <Data label="الفرع" value={item.branch} />
            <Data label="موقع العمل" value={item.workSite} />
            <Data label="تاريخ التعيين" value={item.hireDate ? dateFormatter.format(new Date(item.hireDate)) : null} />
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

      {/* إدارات الموظف — V17 multi-department */}
      {employeeId && <DepartmentsSection employeeId={employeeId} canEdit={canEdit} onAdd={() => setShowAddDeptDialog(true)} />}

      {/* كشف الحضور والانصراف الشهري (V12 §18) */}
      {employeeId && <MonthlyStatementSection employeeId={employeeId} />}

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
          onSuccess={() => { setShowArchiveDialog(false); void navigate('/hr/employees'); }} />
      )}
      {showEditDialog && employeeId && (
        <EditEmployeeDialog
          item={item}
          onClose={() => setShowEditDialog(false)}
          onSuccess={() => { setShowEditDialog(false); void query.refetch(); }}
        />
      )}
      {showDeleteDialog && employeeId && (
        <DeleteEmployeeDialog
          employeeId={employeeId}
          employeeName={item.fullNameAr}
          employeeCode={item.employeeCode}
          onClose={() => setShowDeleteDialog(false)}
          onSuccess={() => { setShowDeleteDialog(false); void navigate('/hr/employees'); }}
        />
      )}
      {showAddDeptDialog && employeeId && (
        <AddDepartmentDialog
          employeeId={employeeId}
          onClose={() => setShowAddDeptDialog(false)}
          onSuccess={() => { setShowAddDeptDialog(false); void query.refetch(); }}
        />
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// EditEmployeeDialog — JSONB patch editor for employee fields (migration 0129)
// يشمل: بيانات شخصية + وظيفية + تواريخ + حالة + تغيير المدير المباشر
// ---------------------------------------------------------------------------
const STATUS_LABELS: Record<string, string> = {
  draft: 'مسودة',
  invited: 'نشط',
  onboarding: 'قيد التهيئة',
  active: 'نشط',
  suspended: 'موقوف',
  notice_period: 'فترة إخطار',
  terminated: 'منتهي',
  archived: 'مؤرشف',
  probation_failed: 'فشل فترة الاختبار',
};

function EditEmployeeDialog({ item, onClose, onSuccess }: { item: Employee360; onClose: () => void; onSuccess: () => void }) {
  const auth = useAuth();
  const lookups = useOrganizationLookups();
  const update = useUpdateEmployee();
  const changeManager = useChangeManager();

  const canSensitive = Boolean(auth.access && hasPermission(auth.access, 'people.employee.update_sensitive'));
  const isBusy = update.isPending || changeManager.isPending;

  // --- Basic fields ---
  const [fullNameAr, setFullNameAr] = useState(item.fullNameAr);
  const [phoneE164, setPhoneE164] = useState(item.phoneE164 ?? '');

  // --- Sensitive fields ---
  const [departmentId, setDepartmentId] = useState(item.departmentId ?? '');
  const [branchId, setBranchId] = useState(item.branchId ?? '');
  const [workSiteId, setWorkSiteId] = useState(item.workSiteId ?? '');
  const [jobTitleText, setJobTitleText] = useState(item.jobTitle ?? '');
  const [gradeText, setGradeText] = useState(item.grade ?? '');
  const [employmentTypeId, setEmploymentTypeId] = useState(item.employmentTypeId ?? '');
  const [hireDate, setHireDate] = useState(item.hireDate ?? '');
  const [status, setStatus] = useState(item.status);

  // --- Manager ---
  const [managerId, setManagerId] = useState(item.managerId ?? '');

  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  // Filter child lookups by parent selection
  const workSites = useMemo(() => {
    const opts = lookups.data?.workSites ?? [];
    return branchId ? opts.filter((s) => s.parentId === branchId) : opts;
  }, [lookups.data?.workSites, branchId]);

  // استبعاد الموظف نفسه من قائمة المديرين
  const availableManagers = useMemo(
    () => (lookups.data?.managers ?? []).filter((m) => m.id !== item.id),
    [lookups.data?.managers, item.id],
  );

  // Reset child when parent changes
  const onBranchChange = (value: string) => {
    setBranchId(value);
    const nextSites = (lookups.data?.workSites ?? []).filter((s) => !value || s.parentId === value);
    if (workSiteId && nextSites.every((s) => s.id !== workSiteId)) setWorkSiteId('');
  };

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    // Build JSONB patch — only changed fields
    const changes: Record<string, unknown> = {};
    // Basic
    if (fullNameAr.trim() !== item.fullNameAr) changes.fullNameAr = fullNameAr.trim();
    if ((phoneE164.trim() || null) !== (item.phoneE164 ?? null)) changes.phoneE164 = phoneE164.trim() || null;
    // Sensitive
    if (canSensitive) {
      if ((departmentId || null) !== (item.departmentId ?? null)) changes.departmentId = departmentId || null;
      if ((branchId || null) !== (item.branchId ?? null)) changes.branchId = branchId || null;
      if ((workSiteId || null) !== (item.workSiteId ?? null)) changes.workSiteId = workSiteId || null;
      if ((jobTitleText.trim() || null) !== (item.jobTitle ?? null)) changes.jobTitleName = jobTitleText.trim() || null;
      if ((gradeText.trim() || null) !== (item.grade ?? null)) changes.gradeName = gradeText.trim() || null;
      if ((employmentTypeId || null) !== (item.employmentTypeId ?? null)) changes.employmentTypeId = employmentTypeId || null;
      if ((hireDate || null) !== (item.hireDate ?? null)) changes.hireDate = hireDate || null;
      if (status !== item.status) changes.status = status;
    }

    // Manager — يُعالج عبر RPC مستقل (change_employee_manager_admin)
    const managerChanged = canSensitive && (managerId || null) !== (item.managerId ?? null);
    const hasFieldChanges = Object.keys(changes).length > 0;

    if (!hasFieldChanges && !managerChanged) {
      setError('لم يتم تغيير أي حقل.');
      return;
    }

    try {
      // تنفيذ التعديلات بالتتابع: بيانات الموظف أولاً ثم المدير
      if (hasFieldChanges) {
        await update.mutateAsync({ employeeId: item.id, changes, reason: reason.trim() });
      }
      if (managerChanged) {
        await changeManager.mutateAsync({
          employeeId: item.id,
          managerId: managerId || null,
          reason: reason.trim(),
        });
      }
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="تعديل بيانات الموظف" onClose={onClose} maxWidth="max-w-2xl">
      {/* رأس المعلومات */}
      <div className="-mt-2 mb-5 flex items-center gap-3 rounded-xl bg-[var(--surface-muted)] p-3">
        <UserAvatar displayName={item.fullNameAr} photoUrl={item.photoUrl} size="sm" announceName={false} />
        <div className="min-w-0 flex-1">
          <p className="font-bold">{item.fullNameAr}</p>
          <p className="muted text-xs">{item.employeeCode} • {item.jobTitle ?? 'بدون مسمى وظيفي'}</p>
        </div>
        <StatusBadge status={item.status} />
      </div>

      {/* تنبيه تحميل الهيكل */}
      {lookups.isLoading ? (
        <div className="mb-4 flex items-center gap-2 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] p-3 text-sm">
          <Loader2 className="size-4 animate-spin text-[var(--brand)]" aria-hidden="true" />
          <span className="muted">جارٍ تحميل بيانات الهيكل التنظيمي…</span>
        </div>
      ) : null}
      {lookups.isError ? (
        <div role="alert" className="mb-4 rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">
          تعذر تحميل بيانات الهيكل: {safeErrorMessage(lookups.error)}
        </div>
      ) : null}

      <form onSubmit={(e) => void onSubmit(e)} className="space-y-6">
        {error ? <div role="alert" className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}

        {/* ─── البيانات الشخصية (update_basic) ─── */}
        <fieldset>
          <legend className="mb-1 flex items-center gap-2 font-black"><UserRound className="size-4 text-[var(--brand)]" aria-hidden="true" />البيانات الشخصية</legend>
          <p className="muted mb-3 text-xs">الاسم ورقم الهاتف — يتطلب صلاحية update_basic على الأقل.</p>
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">الاسم بالعربية <span className="text-[var(--danger)]">*</span></span>
              <input type="text" className="input w-full" required minLength={3} maxLength={160} value={fullNameAr} onChange={(e) => setFullNameAr(e.target.value)} disabled={isBusy} />
            </label>
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">الاسم بالإنجليزية</span>
              <input type="text" className="input w-full" maxLength={160} value={fullNameEn} onChange={(e) => setFullNameEn(e.target.value)} disabled={isBusy} dir="ltr" />
            </label>
            <label className="block sm:col-span-2">
              <span className="mb-1.5 block text-sm font-semibold">رقم الهاتف</span>
              <input type="tel" className="input w-full" value={phoneE164} onChange={(e) => setPhoneE164(e.target.value)} disabled={isBusy} dir="ltr" placeholder="+201XXXXXXXXX" />
            </label>
          </div>
        </fieldset>

        {/* ─── الهيكل التنظيمي (update_sensitive) ─── */}
        {canSensitive ? (
          <fieldset>
            <legend className="mb-1 flex items-center gap-2 font-black"><Building2 className="size-4 text-[var(--brand)]" aria-hidden="true" />الهيكل التنظيمي</legend>
            <p className="muted mb-3 text-xs">الفرع والإدارة والفريق وموقع العمل — الفريق والمنصب يتبعان الإدارة، وموقع العمل يتبع الفرع.</p>
            <div className="grid gap-4 sm:grid-cols-2">
              <LookupSelect label="الفرع" value={branchId} options={lookups.data?.branches ?? []} onChange={onBranchChange} disabled={isBusy} />
              <LookupSelect label="موقع العمل" value={workSiteId} options={workSites} onChange={setWorkSiteId} disabled={isBusy} hint={branchId ? undefined : 'اختر الفرع أولاً لتصفية المواقع'} />
              <LookupSelect label="الإدارة" value={departmentId} options={lookups.data?.departments ?? []} onChange={onDepartmentChange} disabled={isBusy} />
              <LookupSelect label="الفريق" value={teamId} options={teams} onChange={setTeamId} disabled={isBusy} hint={departmentId ? undefined : 'اختر الإدارة أولاً لتصفية الفرق'} />
            </div>
          </fieldset>
        ) : null}

        {/* ─── البيانات الوظيفية (update_sensitive) ─── */}
        {canSensitive ? (
          <fieldset>
            <legend className="mb-1 flex items-center gap-2 font-black"><BriefcaseBusiness className="size-4 text-[var(--brand)]" aria-hidden="true" />البيانات الوظيفية</legend>
            <p className="muted mb-3 text-xs">المسمى الوظيفي والمنصب والدرجة ونوع التوظيف والمدير المباشر.</p>
            <div className="grid gap-4 sm:grid-cols-2">
              <LookupSelect label="المسمى الوظيفي" value={jobTitleId} options={lookups.data?.jobTitles ?? []} onChange={setJobTitleId} disabled={isBusy} />
              <LookupSelect label="المنصب" value={positionId} options={positions} onChange={setPositionId} disabled={isBusy} hint={departmentId ? undefined : 'اختر الإدارة أولاً لتصفية المناصب'} />
              <LookupSelect label="الدرجة الوظيفية" value={gradeId} options={lookups.data?.grades ?? []} onChange={setGradeId} disabled={isBusy} />
              <LookupSelect label="نوع التوظيف" value={employmentTypeId} options={lookups.data?.employmentTypes ?? []} onChange={setEmploymentTypeId} disabled={isBusy} />
              <LookupSelect label="المدير المباشر" value={managerId} options={availableManagers} onChange={setManagerId} disabled={isBusy} emptyLabel="بدون مدير مباشر" className="sm:col-span-2" />
            </div>
          </fieldset>
        ) : null}

        {/* ─── التواريخ والحالة (update_sensitive) ─── */}
        {canSensitive ? (
          <fieldset>
            <legend className="mb-1 flex items-center gap-2 font-black"><CalendarDays className="size-4 text-[var(--brand)]" aria-hidden="true" />التواريخ والحالة</legend>
            <p className="muted mb-3 text-xs">تواريخ التعيين والعقد وفترة الاختبار وحالة الموظف.</p>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="block">
                <span className="mb-1.5 block text-sm font-semibold">تاريخ التعيين</span>
                <input type="date" className="input w-full" value={hireDate} onChange={(e) => setHireDate(e.target.value)} disabled={isBusy} />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-sm font-semibold">نهاية العقد</span>
                <input type="date" className="input w-full" value={contractEnd} onChange={(e) => setContractEnd(e.target.value)} disabled={isBusy} />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-sm font-semibold">نهاية فترة الاختبار</span>
                <input type="date" className="input w-full" value={probationEnd} onChange={(e) => setProbationEnd(e.target.value)} disabled={isBusy} />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-sm font-semibold">الحالة</span>
                <select className="input w-full" value={status} onChange={(e) => setStatus(e.target.value as typeof status)} disabled={isBusy}>
                  {Object.entries(STATUS_LABELS).map(([value, label]) => (
                    <option key={value} value={value}>{label}</option>
                  ))}
                </select>
              </label>
            </div>
          </fieldset>
        ) : null}

        {/* ─── سبب التعديل ─── */}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">سبب التعديل <span className="text-[var(--danger)]">*</span></span>
          <textarea className="input min-h-20 w-full" required minLength={5} value={reason} onChange={(e) => setReason(e.target.value)} disabled={isBusy} placeholder="اذكر سبب التعديل للتدقيق…" />
        </label>

        <div className="flex justify-end gap-3 border-t border-[var(--border)] pt-4">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={isBusy}>إلغاء</button>
          <button type="submit" className="btn-primary" disabled={isBusy || reason.trim().length < 5}>
            {isBusy ? <><Loader2 className="size-4 animate-spin" aria-hidden="true" />جارٍ الحفظ…</> : 'حفظ التعديلات'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

function LookupSelect({ label, value, options, onChange, disabled, hint, emptyLabel, className }: {
  label: string;
  value: string;
  options: Array<{ id: string; label: string }>;
  onChange: (value: string) => void;
  disabled?: boolean;
  hint?: string;
  emptyLabel?: string;
  className?: string;
}) {
  return (
    <label className={`block ${className ?? ''}`}>
      <span className="mb-1.5 block text-sm font-semibold">{label}</span>
      <select className="input w-full" value={value} onChange={(e) => onChange(e.target.value)} disabled={disabled}>
        <option value="">{emptyLabel ?? '— غير محدد —'}</option>
        {options.map((opt) => <option key={opt.id} value={opt.id}>{opt.label}</option>)}
      </select>
      {hint ? <span className="muted mt-1 block text-xs">{hint}</span> : null}
    </label>
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
  return (
    <DialogOverlay title="أرشفة الموظف" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(event) => void submit(event)} className="space-y-4">
        <p className="muted text-sm">سيُعطَّل حساب {employeeName} وتُسحب جلساته وأجهزته، مع الاحتفاظ بالسجل التاريخي.</p>
        {error ? <div role="alert" className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}
        <label className="block"><span className="mb-1.5 block text-sm font-semibold">سبب الأرشفة</span><textarea className="input min-h-24 w-full" required minLength={5} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
        <label className="flex items-start gap-2 text-sm"><input type="checkbox" className="mt-1" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /><span>أؤكد تعطيل الحساب وسحب الجلسات والأجهزة الموثوقة.</span></label>
        <div className="flex justify-end gap-3"><button type="button" className="btn-secondary" onClick={onClose} disabled={archive.isPending}>إلغاء</button><button type="submit" className="btn-primary" disabled={archive.isPending || !confirmed || reason.trim().length < 5}>{archive.isPending ? 'جارٍ الأرشفة…' : 'تأكيد الأرشفة'}</button></div>
      </form>
    </DialogOverlay>
  );
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
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="تغيير المدير المباشر" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-4">
        <p className="muted text-sm">المدير الحالي: {currentManagerName ?? 'غير معين'}</p>

        {error ? <div className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}

        <label className="block">
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

        <label className="block">
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

        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={changeManager.isPending} className="btn-secondary">إلغاء</button>
          <button type="submit" disabled={changeManager.isPending || reason.trim().length < 3} className="btn-primary">
            {changeManager.isPending ? 'جارٍ الحفظ...' : 'حفظ التغييرات'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

function Info({ icon: Icon, label, dir }: { icon: typeof UserRound; label: string; dir?: 'ltr' | 'rtl' }) {
  return <span className="inline-flex items-center gap-2"><Icon className="size-4 muted" aria-hidden="true" /><span dir={dir}>{label}</span></span>;
}

function Data({ label, value }: { label: string; value: string | null }) {
  return <div className="rounded-xl bg-[var(--surface-muted)] p-3"><p className="muted text-xs">{label}</p><p className="mt-1 font-bold">{value ?? '—'}</p></div>;
}

// ---------------------------------------------------------------------------
// DepartmentsSection — V17 تعدد الإدارات
// ---------------------------------------------------------------------------
function DepartmentsSection({ employeeId, canEdit, onAdd }: { employeeId: string; canEdit: boolean; onAdd: () => void }) {
  const { data: departments, isLoading } = useEmployeeDepartments(employeeId);
  const removeDept = useRemoveDepartment();

  if (isLoading) return <SkeletonCard className="h-32" />;
  if (!departments || departments.length === 0) {
    return (
      <article className="card p-5">
        <div className="flex items-center justify-between">
          <h3 className="font-black flex items-center gap-2"><Building2 className="size-5" aria-hidden="true" />الإدارات</h3>
          {canEdit ? <button type="button" className="btn-secondary text-sm" onClick={onAdd}><Plus className="size-4" aria-hidden="true" />إضافة إدارة</button> : null}
        </div>
        <p className="muted mt-3 text-sm">لم يُسنَد لأي إدارة بعد.</p>
      </article>
    );
  }

  return (
    <article className="card p-5">
      <div className="flex items-center justify-between">
        <h3 className="font-black flex items-center gap-2"><Building2 className="size-5" aria-hidden="true" />الإدارات ({departments.length})</h3>
        {canEdit ? <button type="button" className="btn-secondary text-sm" onClick={onAdd}><Plus className="size-4" aria-hidden="true" />إضافة إدارة</button> : null}
      </div>
      <div className="mt-4 space-y-2">
        {departments.map((dept) => (
          <div key={dept.id} className="flex items-center justify-between gap-3 rounded-xl bg-[var(--surface-muted)] p-3">
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <p className="font-bold">{dept.departmentName}</p>
                {dept.isPrimary ? <span className="inline-flex items-center gap-1 rounded-full bg-[var(--brand-soft)] px-2 py-0.5 text-xs font-bold text-[var(--brand)]"><Star className="size-3" aria-hidden="true" />أساسية</span> : null}
              </div>
              {dept.jobTitle ? <p className="muted mt-1 text-xs">{dept.jobTitle}</p> : null}
            </div>
            {canEdit ? (
              <button
                type="button"
                className="rounded-lg p-1.5 text-[var(--text-muted)] hover:bg-[var(--danger-soft)] hover:text-[var(--danger)] transition-colors"
                disabled={removeDept.isPending}
                onClick={() => void removeDept.mutateAsync({ employeeId, departmentId: dept.departmentId })}
                title="إزالة من الإدارة"
              >
                <X className="size-4" />
              </button>
            ) : null}
          </div>
        ))}
      </div>
    </article>
  );
}

// ---------------------------------------------------------------------------
// DeleteEmployeeDialog — حذف الموظف نهائياً
// ---------------------------------------------------------------------------
const DELETE_ERROR_MAP: Record<string, string> = {
  main_admin_required: 'هذا الإجراء متاح فقط للمسؤول الرئيسي.',
  self_delete_not_allowed: 'لا يمكنك حذف حسابك الخاص.',
  delete_reason_required: 'سبب الحذف مطلوب (10 أحرف على الأقل).',
  delete_confirmation_mismatch: 'كود الموظف غير مطابق. تأكد من كتابته بشكل صحيح.',
  employee_not_found: 'الموظف غير موجود أو تم حذفه مسبقاً.',
  employee_history_requires_archive: 'لا يمكن حذف هذا الموظف لوجود سجلات مرتبطة (حضور، طلبات، تقييمات...). استخدم الأرشفة بدلاً من الحذف.',
};

function deleteErrorMessage(err: unknown): string {
  const msg = safeErrorMessage(err);
  for (const [key, label] of Object.entries(DELETE_ERROR_MAP)) {
    if (msg.includes(key)) return label;
  }
  return msg;
}

function DeleteEmployeeDialog({ employeeId, employeeName, employeeCode, onClose, onSuccess }: { employeeId: string; employeeName: string; employeeCode: string; onClose: () => void; onSuccess: () => void }) {
  const deleteEmployee = useDeleteEmployee();
  const [confirmCode, setConfirmCode] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  const canSubmit = !deleteEmployee.isPending && confirmCode === employeeCode && reason.trim().length >= 10;

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await deleteEmployee.mutateAsync({ employeeId, confirmationCode: confirmCode, reason: reason.trim() });
      onSuccess();
    } catch (err) {
      setError(deleteErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="⚠️ حذف الموظف نهائياً" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-4">
        <p className="text-sm">سيتم حذف <strong>{employeeName}</strong> نهائياً من النظام. لا يمكن التراجع عن هذا الإجراء.</p>
        {error ? <div role="alert" className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">سبب الحذف</span>
          <textarea
            className="input w-full"
            rows={2}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="اكتب سبب الحذف (10 أحرف على الأقل)..."
            disabled={deleteEmployee.isPending}
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">اكتب كود الموظف <code className="rounded bg-[var(--surface-raised)] px-1.5 py-0.5 text-xs font-mono">{employeeCode}</code> للتأكيد</span>
          <input
            className="input w-full"
            dir="ltr"
            value={confirmCode}
            onChange={(e) => setConfirmCode(e.target.value)}
            placeholder={employeeCode}
            disabled={deleteEmployee.isPending}
          />
        </label>
        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={deleteEmployee.isPending} className="btn-secondary">إلغاء</button>
          <button type="submit" disabled={!canSubmit} className="btn-primary bg-[var(--danger)] hover:bg-[var(--danger)]">
            {deleteEmployee.isPending ? 'جارٍ الحذف...' : 'حذف نهائي'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

// ---------------------------------------------------------------------------
// AddDepartmentDialog — إضافة إدارة لموظف
// ---------------------------------------------------------------------------
function AddDepartmentDialog({ employeeId, onClose, onSuccess }: { employeeId: string; onClose: () => void; onSuccess: () => void }) {
  const lookups = useOrganizationLookups();
  const assignDept = useAssignDepartment();
  const [departmentId, setDepartmentId] = useState('');
  const [jobTitle, setJobTitle] = useState('');
  const [isPrimary, setIsPrimary] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const departments = useMemo(() => lookups.data?.departments ?? [], [lookups.data]);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await assignDept.mutateAsync({
        employeeId,
        departmentId,
        jobTitle: jobTitle.trim() || undefined,
        isPrimary,
        note: 'إضافة من صفحة ملف الموظف',
      });
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="إضافة إدارة للموظف" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-4">
        {error ? <div role="alert" className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">الإدارة</span>
          <select className="input w-full" value={departmentId} onChange={(e) => setDepartmentId(e.target.value)} required disabled={assignDept.isPending || lookups.isLoading}>
            <option value="">اختر إدارة…</option>
            {departments.map((d) => <option key={d.id} value={d.id}>{d.label}</option>)}
          </select>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">المسمى الوظيفي في هذه الإدارة (اختياري)</span>
          <input className="input w-full" value={jobTitle} onChange={(e) => setJobTitle(e.target.value)} disabled={assignDept.isPending} placeholder="مثال: مسؤول مشتريات" />
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={isPrimary} onChange={(e) => setIsPrimary(e.target.checked)} disabled={assignDept.isPending} />
          <span>تعيين كإدارة أساسية</span>
        </label>
        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={assignDept.isPending} className="btn-secondary">إلغاء</button>
          <button type="submit" disabled={assignDept.isPending || !departmentId} className="btn-primary">
            {assignDept.isPending ? 'جارٍ الإضافة...' : 'إضافة'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}
