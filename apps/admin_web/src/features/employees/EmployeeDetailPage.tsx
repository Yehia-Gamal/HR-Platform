import { cairoTodayIso } from '../../core/cairoTime';
import type { Employee360 } from '@ahla/shared-contracts';
import type { LucideIcon } from 'lucide-react';
import {
  AlertTriangle,
  ArrowRight,
  BadgeCheck,
  BriefcaseBusiness,
  Building2,
  CalendarDays,
  CheckSquare,
  Clock3,
  FileText,
  Archive,
  Eye,
  EyeOff,
  Gauge,
  History,
  ImagePlus,
  KeyRound,
  Lock,
  Mail,
  MailCheck,
  MapPin,
  Network,
  Pencil,
  Phone,
  Plus,
  Printer,
  CreditCard,
  ShieldCheck,
  Star,
  Trash2,
  Trophy,
  X,
} from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { Link, useLocation, useNavigate, useParams, useSearchParams } from 'react-router';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { getSupabase } from '../../core/supabase';
import { prepareAvatarFile } from '../../ui/avatarImage';
import { fixIntlPhoneOrder, isPhoneLikeCode, renderSafeIntlPhoneText } from '../../ui/phoneDisplay';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission, useHrPrefix } from '../workspaces/access';
import { MonthlyStatementSection } from '../attendance/MonthlyStatementSection';
import {
  useEmployee360,
  useResendInvite,
  useEmployees,
  useChangeManager,
  useArchiveEmployee,
  useUpdateEmployee,
  useEmployeeDepartments,
  useAssignDepartment,
  useRemoveDepartment,
  useSyncEmployeeDepartments,
  useDeleteEmployee,
  useSetEmployeePassword,
  useUpdateEmployeeEmail,
  useGrantWeeklyRestCredit,
  useEmployeeActiveShift,
  formatShiftTiming,
} from './useEmployees';
import { normalizePhoneForSubmit, EmployeeEditHistory } from './employeeDetailShared';
import { safeErrorMessage } from '../../core/errorMapper';
import { useToast } from '../../ui/Toast';
import { useOrganizationLookups } from './useOrganizationLookups';
import { useOrganizationAdminCatalog, useOrganizationCommands } from '../management/useAdminOperations';
import { Tabs } from '../../ui/Tabs';
import { EmployeeLeaveTab } from './EmployeeLeaveTab';
import { EmployeeLocationTab } from './EmployeeLocationTab';
import { EmployeeTasksTab } from './EmployeeTasksTab';
import { EmployeeKpiTab } from './EmployeeKpiTab';
import { EmployeeReportsTab } from './EmployeeReportsTab';
import { EmployeeRecognitionTab } from './EmployeeRecognitionTab';
import { EmployeeRetentionScoreCard } from './EmployeeRetentionScoreCard';
import { EmployeeActivityTimeline } from './EmployeeActivityTimeline';
import { EmployeeOrgChartTab } from './EmployeeOrgChartTab';
import { AssignShiftDialog } from './AssignShiftDialog';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

const PENDING_ACCOUNT_STATES = new Set(['invited', 'onboarding', 'pending', 'draft']);

const ACCOUNT_STATUS_LABELS: Record<string, string> = {
  active: 'نشط',
  enabled: 'نشط',
  invited: 'بانتظار التفعيل',
  onboarding: 'بانتظار التفعيل',
  pending: 'بانتظار التفعيل',
  draft: 'مسودة',
  blocked: 'موقوف',
  suspended: 'موقوف',
  disabled: 'معطّل',
};

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function Info({ icon: Icon, label, dir }: { icon: LucideIcon; label: ReactNode; dir?: 'ltr' | 'rtl' }) {
  return (
    <span className="inline-flex items-center gap-2">
      <Icon className="size-4 muted" aria-hidden="true" />
      <span dir={dir}>{label}</span>
    </span>
  );
}

function Data({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="rounded-xl bg-[var(--surface-muted)] p-3">
      <p className="muted text-xs">{label}</p>
      <p className="mt-1 font-bold">{value ?? '—'}</p>
    </div>
  );
}

function LookupSelect({
  label,
  value,
  options,
  onChange,
  disabled,
}: {
  label: string;
  value: string;
  options: Array<{ id: string; label: string }>;
  onChange: (value: string) => void;
  disabled?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold">{label}</span>
      <select className="input w-full" value={value} onChange={(e) => onChange(e.target.value)} disabled={disabled}>
        <option value="">— غير محدد —</option>
        {options.map((opt) => (
          <option key={opt.id} value={opt.id}>
            {opt.label}
          </option>
        ))}
      </select>
    </label>
  );
}

// المسمى الوظيفي: إدخال حر مع اقتراحات — يسمح بكتابة مسمى جديد غير موجود في القائمة
// (يُنشأ تلقائياً عبر update_employee_admin عند الحفظ بنوع jobTitleName).
function JobTitleInput({
  label,
  value,
  options,
  onChange,
  disabled,
}: {
  label: string;
  value: string;
  options: Array<{ id: string; label: string }>;
  onChange: (value: string) => void;
  disabled?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold">{label}</span>
      <input
        className="input w-full"
        list="edit-job-titles-list"
        aria-label={label}
        value={value}
        maxLength={160}
        placeholder="اكتب مسمى جديد أو اختر من الموجود"
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
      />
      <datalist id="edit-job-titles-list">
        {options.map((opt) => (
          <option key={opt.id} value={opt.label} />
        ))}
      </datalist>
    </label>
  );
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
          <h3 className="font-black flex items-center gap-2">
            <Building2 className="size-5" aria-hidden="true" />
            الإدارات
          </h3>
          {canEdit ? (
            <button type="button" className="btn-secondary text-sm" onClick={onAdd}>
              <Plus className="size-4" aria-hidden="true" />
              إضافة إدارة
            </button>
          ) : null}
        </div>
        <p className="muted mt-3 text-sm">لم يُسنَد لأي إدارة بعد.</p>
      </article>
    );
  }

  return (
    <article className="card p-5">
      <div className="flex items-center justify-between">
        <h3 className="font-black flex items-center gap-2">
          <Building2 className="size-5" aria-hidden="true" />
          الإدارات ({departments.length})
        </h3>
        {canEdit ? (
          <button type="button" className="btn-secondary text-sm" onClick={onAdd}>
            <Plus className="size-4" aria-hidden="true" />
            إضافة إدارة
          </button>
        ) : null}
      </div>
      <div className="mt-4 space-y-2">
        {departments.map((dept) => (
          <div key={dept.id} className="flex items-center justify-between gap-3 rounded-xl bg-[var(--surface-muted)] p-3">
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <p className="font-bold">{dept.departmentName}</p>
                {dept.isPrimary ? (
                  <span className="inline-flex items-center gap-1 rounded-full bg-[var(--brand-soft)] px-2 py-0.5 text-xs font-bold text-[var(--brand)]">
                    <Star className="size-3" aria-hidden="true" />
                    أساسية
                  </span>
                ) : null}
              </div>
              {dept.jobTitle ? <p className="muted mt-1 text-xs">{dept.jobTitle}</p> : null}
            </div>
            {canEdit ? (
              <button
                type="button"
                className="rounded-lg p-1.5 text-[var(--text-muted)] hover:bg-[var(--danger-soft)] hover:text-[var(--danger)] transition-colors"
                disabled={removeDept.isPending}
                onClick={() => removeDept.mutate({ employeeId, departmentId: dept.departmentId })}
                title="إزالة من الإدارة"
                aria-label="إزالة من الإدارة"
              >
                <X className="size-4" aria-hidden="true" />
              </button>
            ) : null}
          </div>
        ))}
      </div>
      {removeDept.isError ? <ErrorBanner message={safeErrorMessage(removeDept.error)} /> : null}
    </article>
  );
}

// ---------------------------------------------------------------------------
// EditEmployeeDialog — JSONB patch editor for employee fields (migration 0129)
// ---------------------------------------------------------------------------
function EditEmployeeDialog({ item, onClose, onSuccess }: { item: Employee360; onClose: () => void; onSuccess: () => void }) {
  const auth = useAuth();
  const lookups = useOrganizationLookups();
  const update = useUpdateEmployee();
  const updateEmail = useUpdateEmployeeEmail();

  const canSensitive = Boolean(auth.access && hasPermission(auth.access, 'people.employee.update_sensitive'));

  // --- Basic fields ---
  const [fullNameAr, setFullNameAr] = useState(item.fullNameAr);
  // نصلّح أي رقم محفوظ بترتيب مقلوب (خوارزمية bidi) قبل عرضه في حقل الإدخال.
  const [phoneE164, setPhoneE164] = useState(item.phoneE164 ? fixIntlPhoneOrder(item.phoneE164) : '');
  const [email, setEmail] = useState(item.email ?? '');

  // --- الصورة الشخصية (تُرفع لـ storage وتُحفظ عبر update_employee_admin) ---
  const [photoUrl, setPhotoUrl] = useState(item.photoUrl ?? '');
  const [photoUploading, setPhotoUploading] = useState(false);
  const [photoError, setPhotoError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const uploadedPhotoPathRef = useRef<string | null>(null);
  const didSaveRef = useRef(false);

  // إعادة مزامنة الحقول عند تحديث بيانات الموظف من الخادم (refetch) — لمنع الكتابة فوق تعديلات حديثة.
  const itemVersionRef = useRef<string>(item.lastUpdatedAt ?? item.id);
  useEffect(() => {
    const currentVersion = item.lastUpdatedAt ?? item.id;
    if (itemVersionRef.current !== currentVersion && !didSaveRef.current) {
      itemVersionRef.current = currentVersion;
      setFullNameAr(item.fullNameAr);
      setPhoneE164(item.phoneE164 ? fixIntlPhoneOrder(item.phoneE164) : '');
      setEmail(item.email ?? '');
      setPhotoUrl(item.photoUrl ?? '');
      const nextInitial = Array.from(new Set([...(item.departmentId ? [item.departmentId] : []), ...(item.departments?.map((d) => d.departmentId) ?? [])]));
      setSelectedDeptIds(nextInitial);
      setPrimaryDeptId(item.departmentId ?? nextInitial[0] ?? '');
      setBranchId(item.branchId ?? '');
      setWorkSiteId(item.workSiteId ?? '');
      setJobTitleText(item.jobTitle ?? '');
      setHireDate(item.hireDate ?? '');
    }
  }, [item]);

  // تنظيف الصورة المرفوعة حديثاً إذا أُغلق الحوار دون حفظ.
  useEffect(() => {
    const path = uploadedPhotoPathRef.current;
    return () => {
      if (path && !didSaveRef.current) {
        void getSupabase()
          .then((supabase) => supabase.storage.from('employee-avatars').remove([path]))
          .catch(() => undefined);
      }
    };
  }, []);

  // --- Sensitive fields ---
  const initialDeptIds = useMemo(() => {
    const set = new Set<string>();
    if (item.departmentId) set.add(item.departmentId);
    if (item.departments) {
      for (const d of item.departments) {
        if (d.departmentId) set.add(d.departmentId);
      }
    }
    return Array.from(set);
  }, [item.departmentId, item.departments]);

  const [selectedDeptIds, setSelectedDeptIds] = useState<string[]>(initialDeptIds);
  const [primaryDeptId, setPrimaryDeptId] = useState<string>(item.departmentId ?? initialDeptIds[0] ?? '');
  const syncDepartments = useSyncEmployeeDepartments();

  // إنشاء إدارة جديدة من داخل الحوار ثم إسنادها فوراً للموظف.
  const [newDeptName, setNewDeptName] = useState('');
  const [creatingDept, setCreatingDept] = useState(false);
  const [deptCreateError, setDeptCreateError] = useState<string | null>(null);
  const [locallyCreatedDepts, setLocallyCreatedDepts] = useState<{ id: string; label: string }[]>([]);
  const orgCatalog = useOrganizationAdminCatalog();
  const orgCommands = useOrganizationCommands();

  const deptChipOptions = useMemo(() => {
    const base = lookups.data?.departments ?? [];
    const seen = new Set(base.map((d) => d.id));
    return [...base, ...locallyCreatedDepts.filter((d) => !seen.has(d.id))];
  }, [lookups.data?.departments, locallyCreatedDepts]);

  const createAndSelectDept = async () => {
    const name = newDeptName.trim();
    if (!name || creatingDept) return;
    setDeptCreateError(null);
    const existing = (lookups.data?.departments ?? []).find((d) => d.label.trim() === name);
    if (existing) {
      setSelectedDeptIds((prev) => (prev.includes(existing.id) ? prev : [...prev, existing.id]));
      if (!primaryDeptId) setPrimaryDeptId(existing.id);
      setNewDeptName('');
      return;
    }
    const entities = orgCatalog.data?.entities ?? [];
    const entityId = entities.find((e) => e.active)?.id ?? entities[0]?.id;
    if (!entityId) {
      setDeptCreateError('تعذّر إنشاء الإدارة: لا يوجد كيان قانوني متاح أو صلاحيتك لا تسمح بإدارة الهيكل التنظيمي.');
      return;
    }
    setCreatingDept(true);
    try {
      const code = `D${crypto.randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase()}`;
      const createdId = String(await orgCommands.department.mutateAsync({ entityId, code, name, active: true }));
      setLocallyCreatedDepts((prev) => [...prev, { id: createdId, label: name }]);
      setSelectedDeptIds((prev) => (prev.includes(createdId) ? prev : [...prev, createdId]));
      if (!primaryDeptId) setPrimaryDeptId(createdId);
      setNewDeptName('');
    } catch (err) {
      setDeptCreateError(safeErrorMessage(err));
    } finally {
      setCreatingDept(false);
    }
  };

  const [branchId, setBranchId] = useState(item.branchId ?? '');
  const [workSiteId, setWorkSiteId] = useState(item.workSiteId ?? '');
  // المسمى الوظيفي يُحرَّر كنص حر (مع اقتراحات datalist)؛ المطابقة/الإنشاء يتمان عند الحفظ.
  const [jobTitleText, setJobTitleText] = useState(item.jobTitle ?? '');
  const [hireDate, setHireDate] = useState(item.hireDate ?? '');

  const jobTitleOptions = useMemo(() => {
    const opts = lookups.data?.jobTitles ?? [];
    const current = item.jobTitle;
    if (current && !opts.some((o) => o.label === current)) {
      return [...opts, { id: item.jobTitleId ?? 'current-job-title', label: current }];
    }
    return opts;
  }, [lookups.data?.jobTitles, item.jobTitle, item.jobTitleId]);

  const [error, setError] = useState<string | null>(null);

  // --- كلمة المرور (قسم مستقل داخل الحوار) ---
  const passwordMutation = useSetEmployeePassword();
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPwd, setShowPwd] = useState(false);
  const [pwdError, setPwdError] = useState<string | null>(null);
  const [pwdSuccess, setPwdSuccess] = useState(false);

  const onPasswordSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setPwdError(null);
    setPwdSuccess(false);

    // SEC: سياسة مبسّطة بطلب الإدارة — 6 أحرف كحد أدنى بلا شروط تعقيد.
    // المطابق لـ validateHrIssuedPassword في admin-set-password Edge Function.
    const pwd = newPassword;
    let err: string | null = null;
    if (pwd.length < 6) {
      err = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
    } else if (pwd.length > 72) {
      err = 'كلمة المرور يجب ألا تتجاوز 72 حرفًا.';
    }
    if (err) {
      setPwdError(err);
      return;
    }
    if (newPassword !== confirmPassword) {
      setPwdError('كلمتا المرور غير متطابقتين.');
      return;
    }
    try {
      await passwordMutation.mutateAsync({ employeeId: item.id, password: newPassword });
      setPwdSuccess(true);
      setNewPassword('');
      setConfirmPassword('');
    } catch (err) {
      setPwdError(safeErrorMessage(err));
    }
  };

  // Filter child lookups by parent selection
  const workSites = useMemo(() => {
    const opts = lookups.data?.workSites ?? [];
    return branchId ? opts.filter((s) => s.parentId === branchId) : opts;
  }, [lookups.data?.workSites, branchId]);

  // Reset child when parent changes
  const onBranchChange = (value: string) => {
    setBranchId(value);
    const nextSites = (lookups.data?.workSites ?? []).filter((s) => !value || s.parentId === value);
    if (workSiteId && nextSites.every((s) => s.id !== workSiteId)) setWorkSiteId('');
  };

  // رفع صورة شخصية جديدة إلى storage ثم عرضها مؤقتاً حتى الحفظ.
  const onAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setPhotoError(null);
    try {
      setPhotoUploading(true);
      const prepared = await prepareAvatarFile(file);
      const supabase = await getSupabase();
      const path = `admin/${crypto.randomUUID()}.webp`;
      const { error } = await supabase.storage.from('employee-avatars').upload(path, prepared, { upsert: false, contentType: prepared.type });
      if (error) throw error;
      // حذف الصورة المؤقتة السابقة إن وُجدت.
      const prev = uploadedPhotoPathRef.current;
      if (prev && prev !== path) {
        void supabase.storage
          .from('employee-avatars')
          .remove([prev])
          .catch(() => undefined);
      }
      const { data } = supabase.storage.from('employee-avatars').getPublicUrl(path);
      uploadedPhotoPathRef.current = path;
      setPhotoUrl(data.publicUrl);
    } catch (err) {
      setPhotoError(safeErrorMessage(err));
    } finally {
      setPhotoUploading(false);
    }
  };

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    // Build JSONB patch — only changed fields
    const changes: Record<string, unknown> = {};
    // Basic
    if (fullNameAr.trim() !== item.fullNameAr) changes.fullNameAr = fullNameAr.trim();
    if ((photoUrl || null) !== (item.photoUrl ?? null)) changes.photoUrl = photoUrl || null;
    const phoneNext = normalizePhoneForSubmit(phoneE164);
    if (phoneNext !== (item.phoneE164 ?? '')) changes.phoneE164 = phoneNext || null;
    // Sensitive
    if (canSensitive) {
      if ((primaryDeptId || null) !== (item.departmentId ?? null)) changes.departmentId = primaryDeptId || null;
      if ((branchId || null) !== (item.branchId ?? null)) changes.branchId = branchId || null;
      if ((workSiteId || null) !== (item.workSiteId ?? null)) changes.workSiteId = workSiteId || null;
      // المسمى الوظيفي: نص حر — مطابقة مع موجود → jobTitleId؛ وإلا نص جديد → jobTitleName
      // (update_employee_admin ينشئ المسمى الجديد ويربطه تلقائياً).
      const jtText = jobTitleText.trim();
      const matchedTitle = jtText ? jobTitleOptions.find((o) => o.label.toLowerCase() === jtText.toLowerCase()) : undefined;
      if (jtText === '') {
        if (item.jobTitleId) changes.jobTitleId = null;
      } else if (matchedTitle) {
        if (matchedTitle.id !== item.jobTitleId && matchedTitle.id !== 'current-job-title') {
          changes.jobTitleId = matchedTitle.id;
        }
      } else if (jtText !== (item.jobTitle ?? '')) {
        changes.jobTitleName = jtText;
      }
      if ((hireDate || null) !== (item.hireDate ?? null)) changes.hireDate = hireDate || null;
    }

    const emailChanged = email.trim().toLowerCase() !== (item.email ?? '').toLowerCase();
    const deptsChanged =
      selectedDeptIds.length !== initialDeptIds.length ||
      selectedDeptIds.some((id) => !initialDeptIds.includes(id)) ||
      primaryDeptId !== (item.departmentId ?? '');

    if (Object.keys(changes).length === 0 && !emailChanged && !deptsChanged) {
      setError('لم يتم تغيير أي حقل.');
      return;
    }

    try {
      if (emailChanged) {
        if (!canSensitive) {
          setError('تعديل البريد الإلكتروني يتطلب صلاحية تحديث البيانات الحساسة.');
          return;
        }
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
          setError('البريد الإلكتروني المدخل غير صالح.');
          return;
        }
        await updateEmail.mutateAsync({ employeeId: item.id, email: email.trim() });
      }
      if (Object.keys(changes).length > 0) {
        await update.mutateAsync({ employeeId: item.id, changes });
      }
      if (deptsChanged && canSensitive) {
        await syncDepartments.mutateAsync({
          employeeId: item.id,
          departmentIds: selectedDeptIds,
          primaryDepartmentId: primaryDeptId || undefined,
        });
      }
      didSaveRef.current = true;
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="تعديل بيانات الموظف" onClose={onClose} maxWidth="max-w-2xl">
      <p className="muted -mt-2 mb-5 text-sm">
        {item.fullNameAr} — {item.employeeCode}
      </p>
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-6">
        {error ? <ErrorBanner message={error} /> : null}

        {/* البيانات الشخصية (update_basic) */}
        <fieldset>
          <legend className="mb-3 font-black">البيانات الشخصية</legend>
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">
                الاسم بالعربية <span className="text-[var(--danger)]">*</span>
              </span>
              <input
                type="text"
                className="input w-full"
                required
                minLength={3}
                maxLength={160}
                value={fullNameAr}
                onChange={(e) => setFullNameAr(e.target.value)}
                disabled={update.isPending}
              />
            </label>
            {/* الصورة الشخصية */}
            <div className="flex items-center gap-4 sm:col-span-2">
              <div>
                <UserAvatar displayName={fullNameAr} photoUrl={photoUrl || null} size="lg" announceName={false} />
              </div>
              <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={onAvatarChange} />
              <div className="flex flex-wrap items-center gap-2">
                <button type="button" className="btn btn-outline btn-sm" onClick={() => fileInputRef.current?.click()} disabled={photoUploading}>
                  <ImagePlus className="size-4" aria-hidden="true" />
                  {photoUploading ? 'جارٍ رفع الصورة…' : 'تغيير الصورة'}
                </button>
                {photoUrl && photoUrl !== item.photoUrl ? (
                  <button type="button" className="btn btn-ghost btn-sm" onClick={() => setPhotoUrl(item.photoUrl ?? '')} disabled={photoUploading}>
                    إلغاء الصورة الجديدة
                  </button>
                ) : null}
              </div>
            </div>
            {photoError ? <p className="mt-1 text-xs text-[var(--danger)]">{photoError}</p> : null}
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">رقم الهاتف</span>
              <input
                type="tel"
                className="input w-full max-w-44"
                value={phoneE164}
                onChange={(e) => setPhoneE164(e.target.value)}
                disabled={update.isPending}
                dir="ltr"
                maxLength={15}
                placeholder="+201XXXXXXXXX"
              />
            </label>
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">
                البريد الإلكتروني
                {canSensitive ? null : (
                  <span className="ms-2 inline-flex items-center gap-1 text-xs font-normal text-[var(--muted)]">
                    <Lock className="size-3" aria-hidden="true" /> تتطلب صلاحية حساسة
                  </span>
                )}
              </span>
              <input
                type="email"
                className="input w-full"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={update.isPending || !canSensitive}
                dir="ltr"
                maxLength={254}
                placeholder="name@example.com"
              />
            </label>
          </div>
        </fieldset>

        {/* البيانات الوظيفية (update_sensitive) */}
        {canSensitive ? (
          <fieldset>
            <legend className="mb-3 font-black">البيانات الوظيفية</legend>
            <div className="grid gap-4 sm:grid-cols-2">
              {/* الإدارات المسندة (متعددة) */}
              <div className="sm:col-span-2 space-y-2.5 p-4 rounded-2xl border border-[var(--border)] bg-[var(--surface-muted)]/40">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1">
                  <div>
                    <span className="block text-sm font-black text-[var(--text-primary)]">الإدارات التابع لها الموظف ({selectedDeptIds.length})</span>
                    <span className="block text-xs text-[var(--text-muted)] mt-0.5">
                      يمكنك تحديد أكثر من إدارة للموظف (مثل: الميديا + الموارد البشرية)، وتحديد الإدارة الأساسية.
                    </span>
                  </div>
                </div>

                <div className="flex flex-wrap gap-2 pt-1 max-h-48 overflow-y-auto pr-1">
                  {deptChipOptions.map((dept) => {
                    const isSelected = selectedDeptIds.includes(dept.id);
                    const isPrimary = primaryDeptId === dept.id;

                    return (
                      <button
                        key={dept.id}
                        type="button"
                        onClick={() => {
                          if (isSelected) {
                            const next = selectedDeptIds.filter((id) => id !== dept.id);
                            setSelectedDeptIds(next);
                            if (isPrimary) {
                              setPrimaryDeptId(next[0] ?? '');
                            }
                          } else {
                            const next = [...selectedDeptIds, dept.id];
                            setSelectedDeptIds(next);
                            if (!primaryDeptId || selectedDeptIds.length === 0) {
                              setPrimaryDeptId(dept.id);
                            }
                          }
                        }}
                        className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold border transition-all cursor-pointer ${
                          isSelected
                            ? isPrimary
                              ? 'bg-blue-600 text-white border-blue-600 shadow-xs'
                              : 'bg-indigo-500/15 text-indigo-700 dark:text-indigo-300 border-indigo-500/30'
                            : 'bg-[var(--surface)] text-[var(--text-secondary)] border-[var(--border)] hover:bg-[var(--surface-hover)]'
                        }`}
                      >
                        <span>{dept.label}</span>
                        {isSelected && isPrimary && (
                          <span className="inline-flex items-center text-[10px] bg-white/25 px-1.5 py-0.2 rounded-full font-black">أساسية ★</span>
                        )}
                        {isSelected && !isPrimary && (
                          <span
                            role="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              setPrimaryDeptId(dept.id);
                            }}
                            className="text-[10px] text-indigo-600 dark:text-indigo-400 hover:underline px-1"
                            title="تعيين كإدارة أساسية"
                          >
                            (اجعلها أساسية)
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>

                <div className="flex gap-2 pt-1">
                  <input
                    className="input flex-1 min-w-0"
                    placeholder="اكتب اسم إدارة جديدة ثم اضغط «إضافة إدارة»…"
                    aria-label="اسم إدارة جديدة"
                    value={newDeptName}
                    maxLength={160}
                    disabled={creatingDept}
                    onChange={(e) => {
                      setNewDeptName(e.target.value);
                      setDeptCreateError(null);
                    }}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        void createAndSelectDept();
                      }
                    }}
                  />
                  <button
                    type="button"
                    className="btn-secondary inline-flex items-center gap-1.5 shrink-0"
                    disabled={creatingDept || !newDeptName.trim()}
                    onClick={() => void createAndSelectDept()}
                  >
                    <Plus className="size-3.5" />
                    {creatingDept ? 'جارٍ الإنشاء…' : 'إضافة إدارة'}
                  </button>
                </div>
                {deptCreateError ? <p className="text-xs font-bold text-red-600 dark:text-red-400">{deptCreateError}</p> : null}
              </div>

              <LookupSelect label="الفرع" value={branchId} options={lookups.data?.branches ?? []} onChange={onBranchChange} disabled={update.isPending} />
              <LookupSelect label="موقع العمل" value={workSiteId} options={workSites} onChange={setWorkSiteId} disabled={update.isPending} />
              <JobTitleInput label="المسمى الوظيفي" value={jobTitleText} options={jobTitleOptions} onChange={setJobTitleText} disabled={update.isPending} />
              <label className="block">
                <span className="mb-1.5 block text-sm font-semibold">تاريخ التعيين</span>
                <input type="date" className="input w-full" value={hireDate} onChange={(e) => setHireDate(e.target.value)} disabled={update.isPending} />
              </label>
            </div>
          </fieldset>
        ) : null}

        <div className="flex justify-end gap-3 border-t border-[var(--border)] pt-4">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={update.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={update.isPending}>
            {update.isPending ? 'جارٍ الحفظ…' : 'حفظ التعديلات'}
          </button>
        </div>
      </form>

      {/* قسم كلمة المرور — نموذج منفصل عن نموذج الحفظ الرئيسي حتى لا يُغلق الحوار قبل الحفظ */}
      {canSensitive ? (
        <form onSubmit={(e) => void onPasswordSubmit(e)} className="mt-6 space-y-4 border-t border-[var(--border)] pt-5">
          <h3 className="font-black">تعيين كلمة المرور</h3>
          <p className="muted text-xs">كلمة مرور (6–72 حرفًا — بلا شروط تعقيد) — يعيّنها الإداري ويتعين على الموظف تغييرها عند أول دخول.</p>
          {pwdError ? <ErrorBanner message={pwdError} /> : null}
          {pwdSuccess ? (
            <p className="rounded-lg bg-[var(--success-soft)] px-3 py-2 text-sm text-[var(--success)]">
              تم تعيين كلمة المرور بنجاح. سيُجبر الموظف على تغييرها عند أول دخول.
            </p>
          ) : null}
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">كلمة المرور الجديدة (6–72 حرفًا)</span>
              <div className="relative">
                <input
                  className="input w-full pe-10"
                  type={showPwd ? 'text' : 'password'}
                  value={newPassword}
                  onChange={(e) => {
                    setNewPassword(e.target.value);
                    setPwdSuccess(false);
                  }}
                  autoComplete="new-password"
                  minLength={6}
                  maxLength={72}
                  disabled={passwordMutation.isPending}
                />
                <button
                  type="button"
                  className="absolute start-2 top-1/2 -translate-y-1/2 text-[var(--muted)] hover:text-[var(--text)]"
                  onClick={() => setShowPwd((v) => !v)}
                  aria-label={showPwd ? 'إخفاء' : 'إظهار'}
                >
                  {showPwd ? <EyeOff className="size-4" aria-hidden="true" /> : <Eye className="size-4" aria-hidden="true" />}
                </button>
              </div>
            </label>
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">تأكيد كلمة المرور</span>
              <input
                className="input w-full"
                type={showPwd ? 'text' : 'password'}
                value={confirmPassword}
                onChange={(e) => {
                  setConfirmPassword(e.target.value);
                  setPwdSuccess(false);
                }}
                autoComplete="new-password"
                minLength={6}
                maxLength={72}
                disabled={passwordMutation.isPending}
              />
            </label>
            <div className="sm:col-span-2">
              <button type="submit" disabled={passwordMutation.isPending || newPassword.length < 6 || newPassword !== confirmPassword} className="btn-primary">
                {passwordMutation.isPending ? 'جارٍ التعيين…' : 'تعيين كلمة المرور'}
              </button>
            </div>
          </div>
        </form>
      ) : null}
    </DialogOverlay>
  );
}

// ---------------------------------------------------------------------------
// ArchiveEmployeeDialog — أرشفة الموظف
// ---------------------------------------------------------------------------
function ArchiveEmployeeDialog({
  employeeId,
  employeeName,
  onClose,
  onSuccess,
}: {
  employeeId: string;
  employeeName: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const archive = useArchiveEmployee();
  const [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError(null);
    try {
      await archive.mutateAsync({ employeeId, reason: reason.trim() });
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };
  return (
    <DialogOverlay title="أرشفة الموظف" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(event) => void submit(event)} className="space-y-4">
        <p className="muted text-sm">سيُعطّل حساب {employeeName} وتُسحب جلساته وأجهزته، مع الاحتفاظ بالسجل التاريخي.</p>
        {error ? <ErrorBanner message={error} /> : null}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">سبب الأرشفة</span>
          <textarea className="input min-h-24 w-full" required minLength={5} value={reason} onChange={(event) => setReason(event.target.value)} />
        </label>
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" className="mt-1" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} />
          <span>أؤكد تعطيل الحساب وسحب الجلسات والأجهزة الموثوقة.</span>
        </label>
        <div className="flex justify-end gap-3">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={archive.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={archive.isPending || !confirmed || reason.trim().length < 5}>
            {archive.isPending ? 'جارٍ الأرشفة…' : 'تأكيد الأرشفة'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

// ---------------------------------------------------------------------------
// GrantRestCompDialog — منح رصيد بدل الراحة الأسبوعي يدوياً (HR/التنفيذي)
// ---------------------------------------------------------------------------
function GrantRestCompDialog({
  employeeId,
  employeeName,
  onClose,
  onSuccess,
}: {
  employeeId: string;
  employeeName: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const grant = useGrantWeeklyRestCredit();
  const [workDate, setWorkDate] = useState(cairoTodayIso());
  const [days, setDays] = useState(1);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await grant.mutateAsync({ employeeId, workDate, days });
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="منح بدل راحة أسبوعي" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-4">
        <p className="muted text-sm">
          منح رصيد بدل راحة عن عمل يوم الجمعة للموظف <strong>{employeeName}</strong> — يُضاف للرصيد دون أي خصم من رصيد الإجازات.
        </p>

        {error ? <ErrorBanner message={error} /> : null}

        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">تاريخ بداية العمل (الجمعة)</span>
          <input type="date" className="input w-full" value={workDate} onChange={(e) => setWorkDate(e.target.value)} required disabled={grant.isPending} />
        </label>

        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">عدد أيام البدل</span>
          <input
            type="number"
            className="input w-full"
            value={days}
            min={1}
            max={365}
            onChange={(e) => setDays(Number(e.target.value))}
            required
            disabled={grant.isPending}
          />
        </label>

        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={grant.isPending} className="btn-secondary">
            إلغاء
          </button>
          <button type="submit" disabled={grant.isPending || days < 1 || days > 365} className="btn-primary">
            {grant.isPending ? 'جارٍ المنح...' : 'منح الرصيد'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

// ChangeManagerDialog — تغيير المدير المباشر
// ---------------------------------------------------------------------------
function ChangeManagerDialog({
  employeeId,
  currentManagerName,
  onClose,
  onSuccess,
}: {
  employeeId: string;
  currentManagerName: string | null;
  onClose: () => void;
  onSuccess: () => void;
}) {
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

        {error ? <ErrorBanner message={error} /> : null}

        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">اختر المدير الجديد</span>
          <select className="input w-full" value={selectedManagerId} onChange={(e) => setSelectedManagerId(e.target.value)} disabled={changeManager.isPending}>
            <option value="">بدون مدير مباشر</option>
            {availableManagers.map((emp) => (
              <option key={emp.id} value={emp.id}>
                {emp.fullNameAr} ({emp.employeeCode})
              </option>
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
          <button type="button" onClick={onClose} disabled={changeManager.isPending} className="btn-secondary">
            إلغاء
          </button>
          <button type="submit" disabled={changeManager.isPending || reason.trim().length < 3} className="btn-primary">
            {changeManager.isPending ? 'جارٍ الحفظ...' : 'حفظ التغييرات'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

// ---------------------------------------------------------------------------
// DeleteEmployeeDialog — حذف الموظف نهائياً
// ---------------------------------------------------------------------------
export function DeleteEmployeeDialog({
  employeeId,
  employeeCode,
  employeeName,
  onClose,
  onSuccess,
}: {
  employeeId: string;
  employeeCode: string;
  employeeName: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const deleteEmployee = useDeleteEmployee();
  const [confirmText, setConfirmText] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const codeMatches = confirmText.trim() === employeeCode;

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await deleteEmployee.mutateAsync({ employeeId, confirmationCode: confirmText.trim(), reason: reason.trim() });
      onSuccess();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="حذف الموظف نهائياً" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={(e) => void onSubmit(e)} className="space-y-4">
        <p className="flex items-center gap-2 rounded-xl bg-[var(--danger-soft)] p-3 text-sm font-bold text-[var(--danger)]">
          <AlertTriangle className="size-4 shrink-0" aria-hidden="true" />
          سيتم حذف <strong>{employeeName}</strong> نهائياً من النظام. لا يمكن التراجع عن هذا الإجراء.
        </p>
        {error ? <ErrorBanner message={error} /> : null}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">سبب الحذف النهائي</span>
          <textarea className="input min-h-24 w-full" required minLength={10} value={reason} onChange={(e) => setReason(e.target.value)} />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">
            اكتب كود الموظف للتأكيد:{' '}
            <span dir="ltr" className="font-mono">
              {employeeCode}
            </span>
          </span>
          <input
            className="input w-full"
            value={confirmText}
            onChange={(e) => setConfirmText(e.target.value)}
            placeholder={employeeCode}
            autoComplete="off"
            disabled={deleteEmployee.isPending}
          />
        </label>
        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={deleteEmployee.isPending} className="btn-secondary">
            إلغاء
          </button>
          <button type="submit" disabled={deleteEmployee.isPending || !codeMatches || reason.trim().length < 10} className="btn-danger">
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
        {error ? <ErrorBanner message={error} /> : null}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">الإدارة</span>
          <select
            className="input w-full"
            value={departmentId}
            onChange={(e) => setDepartmentId(e.target.value)}
            required
            disabled={assignDept.isPending || lookups.isLoading}
          >
            <option value="">اختر إدارة…</option>
            {departments.map((d) => (
              <option key={d.id} value={d.id}>
                {d.label}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">المسمى الوظيفي في هذه الإدارة (اختياري)</span>
          <input
            className="input w-full"
            value={jobTitle}
            onChange={(e) => setJobTitle(e.target.value)}
            disabled={assignDept.isPending}
            placeholder="مثال: مسؤول مشتريات"
          />
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={isPrimary} onChange={(e) => setIsPrimary(e.target.checked)} disabled={assignDept.isPending} />
          <span>تعيين كإدارة أساسية</span>
        </label>
        <div className="flex justify-end gap-3">
          <button type="button" onClick={onClose} disabled={assignDept.isPending} className="btn-secondary">
            إلغاء
          </button>
          <button type="submit" disabled={assignDept.isPending || !departmentId} className="btn-primary">
            {assignDept.isPending ? 'جارٍ الإضافة...' : 'إضافة'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

// ---------------------------------------------------------------------------
// PrintableIdBadgeDialog — بطاقة الهوية الوظيفية المعتمدة
// ---------------------------------------------------------------------------
function PrintableIdBadgeDialog({ employee, onClose }: { employee: Employee360; onClose: () => void }) {
  const handlePrint = () => {
    window.print();
  };

  return (
    <DialogOverlay title="بطاقة الهوية الوظيفية المعتمدة" onClose={onClose} maxWidth="max-w-md">
      <div className="space-y-4">
        <p className="text-xs text-[var(--muted)]">معاينة بطاقة الهوية الرسمية للموظف. يمكنك طباعتها فورياً بحجم بطاقة العمل القياسية.</p>

        {/* The ID Card Preview */}
        <div
          id="printable-id-card"
          className="relative overflow-hidden rounded-2xl border-2 border-[var(--primary)] bg-gradient-to-br from-slate-900 via-indigo-950 to-blue-900 p-6 text-white shadow-xl"
        >
          {/* Top Header */}
          <div className="flex items-center justify-between border-b border-white/20 pb-3">
            <div className="flex items-center gap-2">
              <ShieldCheck className="size-6 text-emerald-400" />
              <div>
                <h4 className="text-xs font-black tracking-wider uppercase">جمعية أحلى شباب</h4>
                <p className="text-[10px] text-white/70">بطاقة هوية وظيفية معتمدة</p>
              </div>
            </div>
            <span className="rounded-full bg-emerald-500/20 px-2.5 py-0.5 text-[10px] font-bold text-emerald-300 border border-emerald-500/40">
              {employee.status === 'active' ? 'نشط ومفعل' : employee.status}
            </span>
          </div>

          {/* Body */}
          <div className="my-5 flex items-center gap-4">
            <UserAvatar displayName={employee.fullNameAr} photoUrl={employee.photoUrl} size="lg" />
            <div className="min-w-0 flex-1">
              <h3 className="text-base font-black text-white">{employee.fullNameAr}</h3>
              {employee.fullNameEn ? <p className="text-xs text-white/70">{employee.fullNameEn}</p> : null}
              <p className="mt-1 text-xs font-bold text-amber-300">{employee.jobTitle ?? 'موظف'}</p>
              <p className="text-[11px] text-white/60">
                {employee.departments && employee.departments.length > 0
                  ? employee.departments.map((d) => d.departmentName).join(' / ')
                  : (employee.department ?? 'الإدارة العامة')}
              </p>
            </div>
          </div>

          {/* Footer with Code & Verification (Clean - No QR Code, No Financials) */}
          <div className="flex items-center justify-between rounded-xl bg-black/30 p-3 backdrop-blur-sm border border-white/10">
            <div>
              <span className="block text-[10px] text-white/60">الرقم الوظيفي:</span>
              <span className="font-mono text-sm font-black tracking-widest text-emerald-400">{employee.employeeCode}</span>
            </div>
            <div className="text-center">
              <span className="block text-[10px] text-white/60">تاريخ التعيين:</span>
              <span className="font-mono text-xs text-white/90">{employee.hireDate ?? '—'}</span>
            </div>
            <div className="text-end">
              <span className="block text-[10px] text-white/60">الاعتماد:</span>
              <span className="text-[11px] font-bold text-emerald-300 flex items-center gap-1 justify-end">
                <ShieldCheck className="size-3.5 text-emerald-400" />
                موثق رسميًا
              </span>
            </div>
          </div>
        </div>

        {/* Dialog Actions */}
        <div className="flex justify-end gap-3 pt-2">
          <button type="button" onClick={onClose} className="btn-secondary">
            إغلاق
          </button>
          <button type="button" onClick={handlePrint} className="btn-primary">
            <Printer className="size-4" aria-hidden="true" />
            طباعة البطاقة
          </button>
        </div>
      </div>
    </DialogOverlay>
  );
}

// ---------------------------------------------------------------------------
// EmployeeDetailPage — Main component
// ---------------------------------------------------------------------------
type EmployeeTabId = 'overview' | 'org-hierarchy' | 'timeline' | 'leaves' | 'attendance' | 'locations' | 'tasks' | 'kpi' | 'reports' | 'recognition';

const EMPLOYEE_TABS: { id: EmployeeTabId; label: string; icon: LucideIcon }[] = [
  { id: 'overview', label: 'النبذة', icon: Eye },
  { id: 'org-hierarchy', label: 'الهيكل والتسلسل الإداري', icon: Network },
  { id: 'timeline', label: 'سجل النشاط', icon: History },
  { id: 'leaves', label: 'الإجازات', icon: CalendarDays },
  { id: 'attendance', label: 'الحضور والانصراف', icon: Clock3 },
  { id: 'locations', label: 'مواقع العمل', icon: MapPin },
  { id: 'tasks', label: 'المهام', icon: CheckSquare },
  { id: 'kpi', label: 'الأداء', icon: Gauge },
  { id: 'reports', label: 'التقارير', icon: FileText },
  { id: 'recognition', label: 'لوحة الشرف والتميز', icon: Trophy },
];

export function EmployeeDetailPage() {
  const { employeeId } = useParams();
  const auth = useAuth();
  const query = useEmployee360(employeeId);
  const activeShiftQuery = useEmployeeActiveShift(employeeId);
  const resend = useResendInvite();
  const { toast } = useToast();
  const [resendMessage, setResendMessage] = useState<string | null>(null);
  const [resendError, setResendError] = useState<string | null>(null);
  const [showManagerDialog, setShowManagerDialog] = useState(false);
  const [showArchiveDialog, setShowArchiveDialog] = useState(false);
  const [showEditDialog, setShowEditDialog] = useState(false);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const [showAddDeptDialog, setShowAddDeptDialog] = useState(false);
  const [showGrantRestDialog, setShowGrantRestDialog] = useState(false);
  const [showBadgeDialog, setShowBadgeDialog] = useState(false);
  const [showShiftDialog, setShowShiftDialog] = useState(false);
  const [searchParams, setSearchParams] = useSearchParams();
  const urlTab = searchParams.get('tab') as EmployeeTabId | null;
  const [activeTab, setActiveTabState] = useState<EmployeeTabId>(() => {
    if (urlTab && EMPLOYEE_TABS.some((t) => t.id === urlTab)) return urlTab;
    return 'overview';
  });

  const setActiveTab = (tab: EmployeeTabId) => {
    setActiveTabState(tab);
    const next = new URLSearchParams(searchParams);
    if (tab === 'overview') {
      next.delete('tab');
    } else {
      next.set('tab', tab);
    }
    setSearchParams(next, { replace: true });
  };
  const navigate = useNavigate();
  const location = useLocation();
  const hrPrefix = useHrPrefix();
  const item = query.data;

  const displayDepartments = useMemo(() => {
    if (item?.departments && item.departments.length > 0) {
      return item.departments.map((d) => d.departmentName).join(' / ');
    }
    return item?.department ?? 'بدون إدارة';
  }, [item?.departments, item?.department]);

  if (query.isError) {
    return <ErrorState title="تعذر فتح ملف الموظف" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />;
  }
  if (query.isLoading) {
    return <SkeletonCard className="h-72" />;
  }
  if (!item) {
    return <EmptyState title="تعذر فتح ملف الموظف" description="الملف غير موجود أو خارج نطاق صلاحيتك." />;
  }

  const canInvite = Boolean(auth.access && hasPermission(auth.access, 'people.employee.create'));
  const canEdit = Boolean(
    auth.access && (hasPermission(auth.access, 'people.employee.update_sensitive') || hasPermission(auth.access, 'people.employee.update_basic')),
  );
  const accountPending = PENDING_ACCOUNT_STATES.has((item.accountStatus ?? '').toLowerCase()) || PENDING_ACCOUNT_STATES.has((item.status ?? '').toLowerCase());
  const showResend = canInvite && accountPending && Boolean(employeeId);
  const canGrantRestComp = Boolean(
    auth.access && (hasPermission(auth.access, 'requests.leave.balance.adjust') || auth.access.workspaces?.includes('main_admin')),
  );

  const onResend = async () => {
    if (!employeeId) return;
    setResendMessage(null);
    setResendError(null);
    try {
      const msg = await resend.mutateAsync(employeeId);
      setResendMessage(msg);
      toast({ message: 'تم إرسال الدعوة: ' + msg, tone: 'success' });
    } catch (error) {
      const msg = safeErrorMessage(error);
      setResendError(msg);
      toast({ message: 'فشل إرسال الدعوة: ' + msg, tone: 'error' });
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="الموظفون والهيكل"
        title={`ملف الموظف: ${item.fullNameAr}`}
        description={
          item.todayStatus ? (
            <span className="flex items-center gap-2 flex-wrap text-sm">
              <span>عرض شامل للبيانات الوظيفية والتشغيلية والحضور.</span>
              <span className="inline-flex items-center gap-1 font-bold text-[var(--text)]">
                • حالة اليوم:
                <span className="font-black text-[var(--brand-primary)]">
                  {item.todayStatus.statusLabel ?? 'لم يسجل بعد'}
                  {item.todayStatus.activityTitle ? ` (${item.todayStatus.activityTitle})` : ''}
                </span>
              </span>
            </span>
          ) : (
            'عرض شامل للبيانات الوظيفية والحضور والطلبات والأداء والمستندات.'
          )
        }
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <Link to={`${hrPrefix}/employees`} className="btn-secondary">
              <ArrowRight className="size-4" aria-hidden="true" />
              عودة للموظفين
            </Link>
            {canEdit ? (
              <button type="button" className="btn-primary" onClick={() => setShowEditDialog(true)}>
                <Pencil className="size-4" aria-hidden="true" />
                تعديل البيانات
              </button>
            ) : null}
            {canEdit ? (
              <button type="button" className="btn-secondary" onClick={() => setShowShiftDialog(true)}>
                <Clock3 className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
                إسناد الوردية
              </button>
            ) : null}
            <button type="button" className="btn-secondary" onClick={() => setShowBadgeDialog(true)}>
              <CreditCard className="size-4" aria-hidden="true" />
              بطاقة الهوية الوظيفية
            </button>
            <Link
              to={location.pathname.startsWith('/admin') ? `/admin/hr/passwords?employeeId=${item.id}` : `/hr/passwords?employeeId=${item.id}`}
              className="btn-secondary"
              title="إدارة كلمة المرور وحساب الموظف"
            >
              <KeyRound className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
              كلمة المرور
            </Link>
            {canGrantRestComp ? (
              <button type="button" className="btn-secondary" onClick={() => setShowGrantRestDialog(true)}>
                <BadgeCheck className="size-4" aria-hidden="true" />
                منح بدل راحة
              </button>
            ) : null}
            {showResend ? (
              <button type="button" className="btn-secondary" disabled={resend.isPending} onClick={() => void onResend()}>
                <MailCheck className="size-4" aria-hidden="true" />
                {resend.isPending ? 'جارٍ الإرسال…' : 'إعادة إرسال دعوة التفعيل'}
              </button>
            ) : null}
            {canEdit && item.isActive ? (
              <button type="button" className="btn-secondary text-[var(--danger)] hover:bg-[var(--danger)]/10" onClick={() => setShowArchiveDialog(true)}>
                <Archive className="size-4" aria-hidden="true" />
                أرشفة الموظف
              </button>
            ) : null}
            {canEdit ? (
              <button type="button" className="btn-secondary text-[var(--danger)] hover:bg-[var(--danger)]/10" onClick={() => setShowDeleteDialog(true)}>
                <Trash2 className="size-4" aria-hidden="true" />
                حذف الموظف
              </button>
            ) : null}
          </div>
        }
      />

      {resendMessage ? (
        <div className="flex gap-2 rounded-xl border border-[var(--success)] bg-[var(--success-soft)] p-4 text-sm text-[var(--success)]">
          <MailCheck className="size-5 shrink-0" aria-hidden="true" />
          {resendMessage}
        </div>
      ) : null}
      {resendError ? <ErrorBanner message={resendError} /> : null}

      <Tabs
        tabs={EMPLOYEE_TABS.map((tab) => ({ id: tab.id, label: tab.label }))}
        activeTab={activeTab}
        onTabChange={(id) => setActiveTab(id as EmployeeTabId)}
        ariaLabel="أقسام ملف الموظف"
      >
        {activeTab === 'overview' ? (
          <div className="space-y-6">
            <section className="card flex flex-col gap-6 p-6 xl:flex-row xl:items-start xl:justify-between">
              {/* القسم الرئيسي لبيانات الموظف والهوية */}
              <div className="flex flex-col sm:flex-row items-start gap-5 flex-1 min-w-0">
                <UserAvatar displayName={item.fullNameAr} photoUrl={item.photoUrl} size="lg" eager />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-3">
                    <h2 className="text-2xl font-black">{item.fullNameAr}</h2>
                    <StatusBadge status={item.status} />
                    {/* شارة حالة اليوم التشغيلية الحية والبارزة */}
                    {item.todayStatus ? (
                      <span
                        className={`inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-black shadow-sm transition-all ${
                          item.todayStatus.status === 'present'
                            ? 'bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 border border-emerald-500/30'
                            : item.todayStatus.status === 'convoy'
                            ? 'bg-purple-500/15 text-purple-700 dark:text-purple-300 border border-purple-500/30'
                            : item.todayStatus.status === 'fundraising'
                            ? 'bg-teal-500/15 text-teal-700 dark:text-teal-300 border border-teal-500/30'
                            : item.todayStatus.status === 'mission'
                            ? 'bg-blue-500/15 text-blue-700 dark:text-blue-300 border border-blue-500/30'
                            : item.todayStatus.status === 'on_leave'
                            ? 'bg-sky-500/15 text-sky-700 dark:text-sky-300 border border-sky-500/30'
                            : item.todayStatus.status === 'late'
                            ? 'bg-amber-500/15 text-amber-700 dark:text-amber-300 border border-amber-500/30'
                            : item.todayStatus.status === 'absent'
                            ? 'bg-rose-500/15 text-rose-700 dark:text-rose-300 border border-rose-500/30'
                            : 'bg-gray-500/15 text-gray-700 dark:text-gray-300 border border-gray-500/30'
                        }`}
                      >
                        <span className="relative flex size-2">
                          {['present', 'mission', 'convoy', 'fundraising'].includes(item.todayStatus.status ?? '') && (
                            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-current opacity-75" />
                          )}
                          <span className="relative inline-flex size-2 rounded-full bg-current" />
                        </span>
                        <span>
                          حالة اليوم: {item.todayStatus.statusLabel ?? 'لم يسجل بعد'}
                          {item.todayStatus.activityTitle ? ` — ${item.todayStatus.activityTitle}` : ''}
                        </span>
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-gray-500/10 text-gray-600 border border-gray-500/20">
                        <span className="size-1.5 rounded-full bg-gray-400" />
                        حالة اليوم: لم يسجل بعد
                      </span>
                    )}
                  </div>
                  <p className="muted mt-2 flex items-center gap-2">
                    <span className="font-semibold">{item.jobTitle ?? 'بدون مسمى وظيفي'}</span>
                    {!isPhoneLikeCode(item.employeeCode, item.phoneE164) && (
                      <>
                        <span>•</span>
                        <bdi
                          dir="ltr"
                          className="font-mono text-xs px-2 py-0.5 rounded bg-[var(--surface-muted)] text-[var(--text-secondary)] border border-[var(--border)] font-bold"
                        >
                          {item.employeeCode}
                        </bdi>
                      </>
                    )}
                  </p>
                  <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2.5 text-sm">
                    <Info icon={Network} label={displayDepartments} />
                    <Info icon={Phone} label={item.phoneE164 ? renderSafeIntlPhoneText(item.phoneE164) : 'بدون هاتف'} />
                    <Info icon={Mail} label={item.email ?? 'بدون بريد'} />
                    <Info
                      icon={ShieldCheck}
                      label={`الحساب: ${ACCOUNT_STATUS_LABELS[(item.accountStatus ?? '').toLowerCase()] ?? (accountPending ? 'بانتظار التفعيل' : 'غير متاح')}`}
                    />
                  </div>
                </div>
              </div>

              {/* بطاقة العلاقة الإدارية */}
              <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-muted)] p-4 text-sm xl:w-84 xl:shrink-0">
                <div className="flex items-center justify-between border-b border-[var(--border)] pb-2.5">
                  <p className="font-black">العلاقة الإدارية</p>
                  <button
                    type="button"
                    onClick={() => setActiveTab('org-hierarchy')}
                    className="text-xs font-bold text-[var(--brand-primary)] hover:underline flex items-center gap-1"
                  >
                    <Network className="size-3.5" />
                    عرض الهيكل
                  </button>
                </div>
                <div className="mt-2.5 space-y-2 text-xs">
                  <div className="flex items-center justify-between gap-2">
                    <span className="muted">المدير المباشر:</span>
                    <div className="flex items-center gap-1.5 font-bold text-[var(--text)]">
                      <span>{item.managerName ?? 'غير معين'}</span>
                      {canEdit ? (
                        <button type="button" onClick={() => setShowManagerDialog(true)} className="text-brand font-bold text-xs hover:underline">
                          تغيير
                        </button>
                      ) : null}
                    </div>
                  </div>
                  <div className="flex items-center justify-between gap-2">
                    <span className="muted">المرؤوسون المباشرون:</span>
                    <span className="font-bold text-[var(--text)]">{item.directReports}</span>
                  </div>
                  <div className="border-t border-[var(--border)] pt-2">
                    <div className="flex items-center justify-between mb-1">
                      <span className="muted">الأدوار:</span>
                      {hasPermission(auth.access, 'access.role.read') ? (
                        <Link to="/admin/access" className="text-brand font-bold text-xs hover:underline">
                          إدارة الصلاحيات
                        </Link>
                      ) : null}
                    </div>
                    <p className="font-medium text-[var(--text-secondary)] leading-relaxed">
                      {item.roles.map((role) => role.name).join('، ') || 'لا توجد'}
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setActiveTab('org-hierarchy')}
                  className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-xl border border-[var(--brand-primary)]/30 bg-[var(--brand-primary-soft)]/20 px-3 py-2 text-xs font-bold text-[var(--brand-primary)] hover:bg-[var(--brand-primary)] hover:text-white transition"
                >
                  <Network className="size-3.5" />
                  الهيكل الإداري والمرؤوسون
                </button>
              </div>
            </section>

            {/* بطاقة الحالة التشغيلية واليومية */}
            <section className="card p-5 border-r-4 border-r-[var(--brand-primary)]">
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div className="flex items-center gap-3">
                  <div className="flex size-10 items-center justify-center rounded-xl bg-[var(--surface-muted)] text-[var(--brand-primary)]">
                    <CalendarDays className="size-5" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="font-black text-base">الحالة التشغيلية واليومية</h3>
                      {item.todayStatus ? (
                        <span className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-black ${
                          item.todayStatus.status === 'present'
                            ? 'bg-emerald-500/10 text-emerald-600 border border-emerald-500/30'
                            : item.todayStatus.status === 'convoy'
                            ? 'bg-purple-500/10 text-purple-600 border border-purple-500/30'
                            : item.todayStatus.status === 'fundraising'
                            ? 'bg-teal-500/10 text-teal-600 border border-teal-500/30'
                            : item.todayStatus.status === 'mission'
                            ? 'bg-blue-500/10 text-blue-600 border border-blue-500/30'
                            : item.todayStatus.status === 'on_leave'
                            ? 'bg-sky-500/10 text-sky-600 border border-sky-500/30'
                            : item.todayStatus.status === 'late'
                            ? 'bg-amber-500/10 text-amber-600 border border-amber-500/30'
                            : item.todayStatus.status === 'absent'
                            ? 'bg-rose-500/10 text-rose-600 border border-rose-500/30'
                            : 'bg-gray-500/10 text-gray-600 border border-gray-500/30'
                        }`}>
                          <span className="size-1.5 rounded-full bg-current" />
                          {item.todayStatus.statusLabel ?? item.todayStatus.status}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-gray-500/10 text-gray-600 border border-gray-500/30">
                          لم يسجل بعد
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-[var(--text-secondary)] mt-0.5">
                      متابعة الحالة التشغيلية والدوام لليوم الحالي
                    </p>
                  </div>
                </div>

                {item.todayStatus?.activityTitle && (
                  <div className="flex items-center gap-1.5 rounded-xl bg-[var(--brand-primary-soft)]/20 border border-[var(--brand-primary)]/20 px-3 py-1.5 text-xs font-bold text-[var(--brand-primary)]">
                    <MapPin className="size-3.5" />
                    <span>الوجهة / النشاط: {item.todayStatus.activityTitle}</span>
                  </div>
                )}
              </div>

              <div className="mt-4 grid grid-cols-2 sm:grid-cols-4 gap-3 pt-3 border-t border-[var(--border)] text-sm">
                <div>
                  <span className="text-xs text-[var(--text-secondary)] block">وقت الحضور</span>
                  <span className="font-bold">
                    {item.todayStatus?.checkInAt
                      ? new Date(item.todayStatus.checkInAt).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })
                      : '—'}
                  </span>
                </div>
                <div>
                  <span className="text-xs text-[var(--text-secondary)] block">وقت الانصراف</span>
                  <span className="font-bold">
                    {item.todayStatus?.checkOutAt
                      ? new Date(item.todayStatus.checkOutAt).toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })
                      : '—'}
                  </span>
                </div>
                <div>
                  <span className="text-xs text-[var(--text-secondary)] block">
                    {item.todayStatus?.lateMinutes && item.todayStatus.lateMinutes > 0 ? 'مدة التأخير' : 'ساعات العمل'}
                  </span>
                  <span className="font-bold">
                    {item.todayStatus?.lateMinutes && item.todayStatus.lateMinutes > 0
                      ? `${item.todayStatus.lateMinutes} دقيقة`
                      : item.todayStatus?.workMinutes && item.todayStatus.workMinutes > 0
                      ? `${(item.todayStatus.workMinutes / 60).toFixed(1)} ساعة`
                      : (item.todayStatus?.status === 'convoy' || item.todayStatus?.status === 'mission' || item.todayStatus?.status === 'fundraising')
                      ? 'مهمة عمل رسمية'
                      : '—'}
                  </span>
                </div>
                <div>
                  <span className="text-xs text-[var(--text-secondary)] block">ملاحظة اليوم</span>
                  <span className="font-bold text-xs text-[var(--text-secondary)]">
                    {!item.todayStatus
                      ? 'لم يسجل بعد'
                      : item.todayStatus.status === 'convoy'
                      ? 'مشارك في قافلة مساعدات'
                      : item.todayStatus.status === 'fundraising'
                      ? 'يوم ترفيهي للموظفين (فاندي)'
                      : item.todayStatus.status === 'mission'
                      ? 'مأمورية عمل خارجية'
                      : item.todayStatus.status === 'on_leave'
                      ? 'إجازة رسمية معتمدة'
                      : item.todayStatus.status === 'present'
                      ? 'قيد الدوام'
                      : item.todayStatus.status === 'late'
                      ? 'حضر مع تأخير'
                      : item.todayStatus.status === 'absent'
                      ? 'لم يسجل حضور'
                      : 'لم يسجل بعد'}
                  </span>
                </div>
              </div>

              {/* قسم فترة العمل (الوردية المقررة) */}
              <div className="mt-4 pt-3 border-t border-[var(--border)] flex flex-wrap items-center justify-between gap-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-xs text-[var(--text-secondary)] font-semibold flex items-center gap-1.5">
                    <Clock3 className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
                    فترة العمل المقررة:
                  </span>
                  {activeShiftQuery.isLoading ? (
                    <span className="text-xs text-[var(--text-secondary)]">جارٍ التحميل…</span>
                  ) : (
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-bold text-[var(--text)]">
                        {activeShiftQuery.data?.shiftName ?? 'الدوام الأساسي العام'}
                      </span>
                      {activeShiftQuery.data ? (
                        <span className="text-xs text-[var(--text-secondary)] font-sans">
                          ({formatShiftTiming(activeShiftQuery.data.startTime, activeShiftQuery.data.endTime, activeShiftQuery.data.graceInMinutes)})
                        </span>
                      ) : null}
                      {activeShiftQuery.data?.isAssigned ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/10 px-2 py-0.5 text-xs font-black text-emerald-600 border border-emerald-500/20">
                          معتمدة ومسندة
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-gray-500/10 px-2 py-0.5 text-xs font-semibold text-gray-600 border border-gray-500/20">
                          الافتراضية العامة
                        </span>
                      )}
                    </div>
                  )}
                </div>
                {canEdit ? (
                  <button
                    type="button"
                    onClick={() => setShowShiftDialog(true)}
                    className="btn-secondary btn-sm text-xs font-bold flex items-center gap-1.5"
                  >
                    <Pencil className="size-3.5" aria-hidden="true" />
                    تغيير الوردية
                  </button>
                ) : null}
              </div>
            </section>

            <section className="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
              <MetricCard
                label="أيام الحضور — 30 يومًا"
                value={item.attendance30.present}
                hint={`${item.attendance30.lateDays} أيام تأخير`}
                icon={BadgeCheck}
                onClick={() => document.getElementById('attendance-kpi-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              />
              <MetricCard
                label="أيام الغياب"
                value={item.attendance30.absent}
                icon={Clock3}
                onClick={() => document.getElementById('attendance-kpi-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              />
              <MetricCard
                label="الطلبات المعلقة"
                value={item.requestCounts.pending}
                hint={`${item.requestCounts.approved} معتمدة`}
                icon={FileText}
                onClick={() => document.getElementById('latest-requests')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              />
              <MetricCard
                label="أحدث تقييم"
                value={item.latestKpi?.finalScore ?? item.latestKpi?.currentStage ?? '—'}
                hint={item.latestKpi?.finalRating ?? undefined}
                icon={Gauge}
                onClick={() => document.getElementById('attendance-kpi-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              />
            </section>

            <section className="grid gap-5 xl:grid-cols-2">
              <article className="card p-5">
                <h3 className="font-black">البيانات الوظيفية</h3>
                <div className="mt-4 grid gap-3 sm:grid-cols-2">
                  <Data label="الإدارة" value={displayDepartments} />
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
                      <div>
                        <p className="font-bold">{doc.title}</p>
                        <p className="muted mt-1 text-xs">{doc.expiryDate ? `ينتهي ${dateFormatter.format(new Date(doc.expiryDate))}` : doc.type}</p>
                      </div>
                      <StatusBadge value={doc.status} />
                    </div>
                  ))}
                  {item.assets
                    .filter((asset) => !asset.returnedAt)
                    .map((asset) => (
                      <div key={asset.id} className="flex items-center justify-between rounded-xl border border-[var(--border)] p-3">
                        <div>
                          <p className="font-bold">{asset.assetName}</p>
                          <p className="muted mt-1 text-xs">{asset.serial ?? asset.assetType}</p>
                        </div>
                        <BriefcaseBusiness className="size-5 text-[var(--text-muted)]" aria-label="عهدة قيد الاستلام" />
                      </div>
                    ))}
                </div>
              </article>
            </section>

            <section className="grid gap-5 xl:grid-cols-2">
              <article id="latest-requests" className="card overflow-hidden">
                <div className="border-b border-[var(--border)] p-5">
                  <h3 className="font-black">أحدث الطلبات</h3>
                </div>
                <div className="divide-y divide-[var(--border)]">
                  {item.recentRequests.length === 0 ? (
                    <p className="muted p-5 text-sm">لا توجد طلبات.</p>
                  ) : (
                    item.recentRequests.map((request) => (
                      <div key={request.id} className="flex items-center justify-between gap-3 p-4">
                        <div>
                          <p className="font-bold">{request.title ?? request.requestType}</p>
                          <p className="muted mt-1 text-xs">
                            طلب #{request.requestNumber} • {dateFormatter.format(new Date(request.createdAt))}
                          </p>
                        </div>
                        <StatusBadge value={request.status} />
                      </div>
                    ))
                  )}
                </div>
              </article>

              <article className="card overflow-hidden">
                <div className="border-b border-[var(--border)] p-5">
                  <h3 className="font-black">أحدث المهام</h3>
                </div>
                <div className="divide-y divide-[var(--border)]">
                  {item.recentTasks.length === 0 ? (
                    <p className="muted p-5 text-sm">لا توجد مهام.</p>
                  ) : (
                    item.recentTasks.map((task) => (
                      <div key={task.id} className="flex items-center justify-between gap-3 p-4">
                        <div>
                          <p className="font-bold">{task.title}</p>
                          <p className="muted mt-1 text-xs">{task.dueDate ? `الاستحقاق ${dateFormatter.format(new Date(task.dueDate))}` : 'بدون موعد'}</p>
                        </div>
                        <StatusBadge value={task.status} />
                      </div>
                    ))
                  )}
                </div>
              </article>
            </section>

            {/* الحضور والتقييم — آخر 30 يوماً (وجهة بطاقات الملخص) */}
            <section id="attendance-kpi-section" className="card p-5">
              <h3 className="font-black">الحضور والتقييم — آخر 30 يوماً</h3>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <Data label="أيام حضور" value={String(item.attendance30.present)} />
                <Data label="أيام تأخير" value={String(item.attendance30.lateDays)} />
                <Data label="أيام غياب" value={String(item.attendance30.absent)} />
                <Data
                  label="أحدث تقييم"
                  value={
                    item.latestKpi ? [item.latestKpi.finalScore ?? item.latestKpi.currentStage, item.latestKpi.finalRating].filter(Boolean).join(' · ') : '—'
                  }
                />
              </div>
            </section>

            {/* مؤشر الاستقرار والولاء الوظيفي التنبؤي */}
            <EmployeeRetentionScoreCard employee={item} />

            {/* سجل النشاط والمحطات الإدارية */}
            <EmployeeActivityTimeline employee={item} />

            {/* إدارات الموظف — V17 multi-department */}
            {employeeId && <DepartmentsSection employeeId={employeeId} canEdit={canEdit} onAdd={() => setShowAddDeptDialog(true)} />}

            {/* آخر التعديلات الهامة على الملف */}
            {employeeId && <EmployeeEditHistory employeeId={employeeId} />}

            <p className="muted flex items-center gap-2 text-xs">
              <CalendarDays className="size-4" aria-hidden="true" />
              آخر تحديث:{' '}
              {item.lastUpdatedAt
                ? new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.lastUpdatedAt))
                : 'غير متوفر'}
            </p>
          </div>
        ) : null}

        {activeTab === 'org-hierarchy' && employeeId ? (
          <EmployeeOrgChartTab employeeId={employeeId} employee={item} onChangeManagerClick={canEdit ? () => setShowManagerDialog(true) : undefined} />
        ) : null}
        {activeTab === 'timeline' ? <EmployeeActivityTimeline employee={item} /> : null}
        {activeTab === 'leaves' && employeeId ? <EmployeeLeaveTab employeeId={employeeId} /> : null}
        {activeTab === 'attendance' && employeeId ? <MonthlyStatementSection employeeId={employeeId} /> : null}
        {activeTab === 'locations' && employeeId ? <EmployeeLocationTab employeeId={employeeId} /> : null}
        {activeTab === 'tasks' && employeeId ? <EmployeeTasksTab employeeId={employeeId} /> : null}
        {activeTab === 'kpi' && employeeId ? <EmployeeKpiTab employeeId={employeeId} /> : null}
        {activeTab === 'reports' && employeeId ? <EmployeeReportsTab employeeId={employeeId} /> : null}
        {activeTab === 'recognition' && employeeId ? <EmployeeRecognitionTab employeeId={employeeId} /> : null}
      </Tabs>

      {showManagerDialog && employeeId && (
        <ChangeManagerDialog
          employeeId={employeeId}
          currentManagerName={item.managerName}
          onClose={() => setShowManagerDialog(false)}
          onSuccess={() => {
            setShowManagerDialog(false);
            toast({ message: 'تم تغيير المدير المباشر بنجاح', tone: 'success' });
            void query.refetch();
          }}
        />
      )}
      {showArchiveDialog && employeeId && (
        <ArchiveEmployeeDialog
          employeeId={employeeId}
          employeeName={item.fullNameAr}
          onClose={() => setShowArchiveDialog(false)}
          onSuccess={() => {
            setShowArchiveDialog(false);
            void query.refetch();
          }}
        />
      )}
      {showEditDialog && employeeId && (
        <EditEmployeeDialog
          item={item}
          onClose={() => setShowEditDialog(false)}
          onSuccess={() => {
            setShowEditDialog(false);
            void query.refetch();
          }}
        />
      )}
      {showDeleteDialog && employeeId && (
        <DeleteEmployeeDialog
          employeeId={employeeId}
          employeeCode={item.employeeCode}
          employeeName={item.fullNameAr}
          onClose={() => setShowDeleteDialog(false)}
          onSuccess={() => {
            setShowDeleteDialog(false);
            void navigate('/hr/employees');
          }}
        />
      )}
      {showAddDeptDialog && employeeId && (
        <AddDepartmentDialog
          employeeId={employeeId}
          onClose={() => setShowAddDeptDialog(false)}
          onSuccess={() => {
            setShowAddDeptDialog(false);
            void query.refetch();
          }}
        />
      )}
      {showGrantRestDialog && employeeId ? (
        <GrantRestCompDialog
          employeeId={employeeId}
          employeeName={item.fullNameAr}
          onClose={() => setShowGrantRestDialog(false)}
          onSuccess={() => {
            setShowGrantRestDialog(false);
            void query.refetch();
          }}
        />
      ) : null}
      {showShiftDialog && employeeId ? (
        <AssignShiftDialog
          employeeId={employeeId}
          employeeName={item.fullNameAr}
          employeeCode={item.employeeCode}
          onClose={() => setShowShiftDialog(false)}
          onSuccess={() => {
            setShowShiftDialog(false);
            void activeShiftQuery.refetch();
            void query.refetch();
          }}
        />
      ) : null}
      {showBadgeDialog ? <PrintableIdBadgeDialog employee={item} onClose={() => setShowBadgeDialog(false)} /> : null}
    </div>
  );
}
