import type { Employee360 } from '@ahla/shared-contracts';
import type { LucideIcon } from 'lucide-react';
import {
  ArrowRight,
  BadgeCheck,
  BriefcaseBusiness,
  Building2,
  CalendarDays,
  Clock3,
  FileText,
  Archive,
  Eye,
  EyeOff,
  Gauge,
  ImagePlus,
  Lock,
  Mail,
  MailCheck,
  Network,
  Pencil,
  Phone,
  Plus,
  ShieldCheck,
  Star,
  Trash2,
  X,
} from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { Link, useNavigate, useParams } from 'react-router';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { getSupabase } from '../../core/supabase';
import { prepareAvatarFile } from '../../ui/avatarImage';
import { fixIntlPhoneOrder, renderSafeIntlPhoneText } from '../../ui/phoneDisplay';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
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
  useDeleteEmployee,
  useSetEmployeePassword,
  useUpdateEmployeeEmail,
} from './useEmployees';
import { normalizePhoneForSubmit, EmployeeEditHistory } from './employeeDetailShared';
import { safeErrorMessage } from '../../core/errorMapper';
import { useToast } from '../../ui/Toast';
import { useOrganizationLookups } from './useOrganizationLookups';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

// Accounts that have not finished activation can still be re-invited.
const PENDING_ACCOUNT_STATES = new Set(['invited', 'onboarding', 'pending', 'draft']);

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
  const [departmentId, setDepartmentId] = useState(item.departmentId ?? '');
  const [branchId, setBranchId] = useState(item.branchId ?? '');
  const [workSiteId, setWorkSiteId] = useState(item.workSiteId ?? '');
  const [jobTitleId, setJobTitleId] = useState(item.jobTitleId ?? '');
  const [hireDate, setHireDate] = useState(item.hireDate ?? '');

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

    // SEC: فحص قوة كلمة المرور على الواجهة — مطابق لـ validateHrIssuedPassword
    // في admin-set-password Edge Function. رسائل عربية واضحة لكل قاعدة.
    const pwd = newPassword;
    let err: string | null = null;
    if (pwd.length < 12) {
      err = 'كلمة المرور يجب أن تكون 12 حرفًا على الأقل.';
    } else if (pwd.length > 72) {
      err = 'كلمة المرور يجب ألا تتجاوز 72 حرفًا.';
    } else if (!/[A-Z]/.test(pwd)) {
      err = 'كلمة المرور يجب أن تحتوي حرفًا كبيرًا واحدًا على الأقل (A-Z).';
    } else if (!/[a-z]/.test(pwd)) {
      err = 'كلمة المرور يجب أن تحتوي حرفًا صغيرًا واحدًا على الأقل (a-z).';
    } else if (!/\d/.test(pwd)) {
      err = 'كلمة المرور يجب أن تحتوي رقمًا واحدًا على الأقل (0-9).';
    } else if (!/[!@#$%^&*()_\-+=[\]{};':"\\|,.<>/?`~]/.test(pwd)) {
      err = 'كلمة المرور يجب أن تحتوي رمزًا خاصًا واحدًا على الأقل (!@#$...).';
    } else if (/(.)\1{4,}/.test(pwd)) {
      err = 'كلمة المرور تحتوي تكرارًا مفرطًا لنفس الحرف (5+ على التوالي).';
    } else {
      const sequences = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm', 'abcdefghijklmnopqrstuvwxyz', '0123456789'];
      const lower = pwd.toLowerCase();
      for (const seq of sequences) {
        for (let i = 0; i + 4 <= seq.length; i++) {
          if (lower.includes(seq.slice(i, i + 4))) {
            err = 'كلمة المرور تحتوي تسلسلًا مألوفًا من لوحة المفاتيح أو أرقام.';
            break;
          }
        }
        if (err) break;
      }
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
        void supabase.storage.from('employee-avatars').remove([prev]).catch(() => undefined);
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
      if ((departmentId || null) !== (item.departmentId ?? null)) changes.departmentId = departmentId || null;
      if ((branchId || null) !== (item.branchId ?? null)) changes.branchId = branchId || null;
      if ((workSiteId || null) !== (item.workSiteId ?? null)) changes.workSiteId = workSiteId || null;
      if ((jobTitleId || null) !== (item.jobTitleId ?? null)) changes.jobTitleId = jobTitleId || null;
      if ((hireDate || null) !== (item.hireDate ?? null)) changes.hireDate = hireDate || null;
    }

    const emailChanged = email.trim().toLowerCase() !== (item.email ?? '').toLowerCase();

    if (Object.keys(changes).length === 0 && !emailChanged) {
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
              {photoUrl ? (
                <img
                  src={photoUrl}
                  alt="الصورة الشخصية"
                  className="size-16 rounded-full border object-cover"
                />
              ) : (
                <div className="grid size-16 place-items-center rounded-full bg-[var(--surface)] text-lg font-black text-[var(--muted)]">
                  {item.fullNameAr.charAt(0)}
                </div>
              )}
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={onAvatarChange}
              />
              <div className="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  className="btn btn-outline btn-sm"
                  onClick={() => fileInputRef.current?.click()}
                  disabled={photoUploading}
                >
                  <ImagePlus className="size-4" aria-hidden="true" />
                  {photoUploading ? 'جارٍ رفع الصورة…' : 'تغيير الصورة'}
                </button>
                {photoUrl && photoUrl !== item.photoUrl ? (
                  <button
                    type="button"
                    className="btn btn-ghost btn-sm"
                    onClick={() => setPhotoUrl(item.photoUrl ?? '')}
                    disabled={photoUploading}
                  >
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
              <LookupSelect
                label="الإدارة"
                value={departmentId}
                options={lookups.data?.departments ?? []}
                onChange={setDepartmentId}
                disabled={update.isPending}
              />
              <LookupSelect label="الفرع" value={branchId} options={lookups.data?.branches ?? []} onChange={onBranchChange} disabled={update.isPending} />
              <LookupSelect label="موقع العمل" value={workSiteId} options={workSites} onChange={setWorkSiteId} disabled={update.isPending} />
              <LookupSelect
                label="المسمى الوظيفي"
                value={jobTitleId}
                options={lookups.data?.jobTitles ?? []}
                onChange={setJobTitleId}
                disabled={update.isPending}
              />
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
          <p className="muted text-xs">كلمة مرور قوية (12+ حرف، أحرف كبيرة وصغيرة ورقم ورمز) — يعيّنها الإداري ويتعين على الموظف تغييرها عند أول دخول.</p>
          {pwdError ? <ErrorBanner message={pwdError} /> : null}
          {pwdSuccess ? (
            <p className="rounded-lg bg-[var(--success-soft)] px-3 py-2 text-sm text-[var(--success)]">تم تعيين كلمة المرور بنجاح. سيُجبر الموظف على تغييرها عند أول دخول.</p>
          ) : null}
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">كلمة المرور الجديدة (12–72 حرفًا)</span>
              <div className="relative">
                <input
                  className="input w-full pl-10"
                  type={showPwd ? 'text' : 'password'}
                  value={newPassword}
                  onChange={(e) => { setNewPassword(e.target.value); setPwdSuccess(false); }}
                  autoComplete="new-password"
                  minLength={12}
                  maxLength={72}
                  disabled={passwordMutation.isPending}
                />
                <button
                  type="button"
                  className="absolute left-2 top-1/2 -translate-y-1/2 text-[var(--muted)] hover:text-[var(--text)]"
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
                onChange={(e) => { setConfirmPassword(e.target.value); setPwdSuccess(false); }}
                autoComplete="new-password"
                minLength={12}
                maxLength={72}
                disabled={passwordMutation.isPending}
              />
            </label>
            <div className="sm:col-span-2">
              <button
                type="submit"
                disabled={passwordMutation.isPending || newPassword.length < 12 || newPassword !== confirmPassword}
                className="btn-primary"
              >
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
  return createPortal(
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <form onSubmit={(event) => void submit(event)} className="card w-full max-w-md p-6" role="dialog" aria-modal="true">
        <h2 className="text-lg font-black">أرشفة الموظف</h2>
        <p className="muted mt-2 text-sm">سيُعطّل حساب {employeeName} وتُسحب جلساته وأجهزته، مع الاحتفاظ بالسجل التاريخي.</p>
        {error ? (
          <div className="mt-4">
            <ErrorBanner message={error} />
          </div>
        ) : null}
        <label className="mt-4 block">
          <span className="mb-1.5 block text-sm font-semibold">سبب الأرشفة</span>
          <textarea className="input min-h-24 w-full" required minLength={5} value={reason} onChange={(event) => setReason(event.target.value)} />
        </label>
        <label className="mt-4 flex items-start gap-2 text-sm">
          <input type="checkbox" className="mt-1" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} />
          <span>أؤكد تعطيل الحساب وسحب الجلسات والأجهزة الموثوقة.</span>
        </label>
        <div className="mt-6 flex justify-end gap-3">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={archive.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={archive.isPending || !confirmed || reason.trim().length < 5}>
            {archive.isPending ? 'جارٍ الأرشفة…' : 'تأكيد الأرشفة'}
          </button>
        </div>
      </form>
    </div>,
    document.body,
  );
}

// ---------------------------------------------------------------------------
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

  return createPortal(
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <form onSubmit={(e) => void onSubmit(e)} className="card w-full max-w-md p-6" role="dialog" aria-modal="true">
        <h2 className="text-lg font-black">تغيير المدير المباشر</h2>
        <p className="muted mt-2 text-sm">المدير الحالي: {currentManagerName ?? 'غير معين'}</p>

        {error ? (
          <div className="mt-4">
            <ErrorBanner message={error} />
          </div>
        ) : null}

        <label className="mt-4 block">
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
          <button type="button" onClick={onClose} disabled={changeManager.isPending} className="btn-secondary">
            إلغاء
          </button>
          <button type="submit" disabled={changeManager.isPending || reason.trim().length < 3} className="btn-primary">
            {changeManager.isPending ? 'جارٍ الحفظ...' : 'حفظ التغييرات'}
          </button>
        </div>
      </form>
    </div>,
    document.body,
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

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <form onSubmit={(e) => void onSubmit(e)} className="card w-full max-w-md space-y-4 p-6" role="dialog" aria-modal="true">
        <h2 className="text-lg font-black text-[var(--danger)]">⚠️ حذف الموظف نهائياً</h2>
        <p className="text-sm">
          سيتم حذف <strong>{employeeName}</strong> نهائياً من النظام. لا يمكن التراجع عن هذا الإجراء.
        </p>
        {error ? <ErrorBanner message={error} /> : null}
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">سبب الحذف النهائي</span>
          <textarea className="input min-h-24 w-full" required minLength={10} value={reason} onChange={(e) => setReason(e.target.value)} />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold">
            اكتب كود الموظف للتأكيد: <span dir="ltr" className="font-mono">{employeeCode}</span>
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
          <button
            type="submit"
            disabled={deleteEmployee.isPending || !codeMatches || reason.trim().length < 10}
            className="btn-primary bg-[var(--danger)] hover:bg-[var(--danger)]"
          >
            {deleteEmployee.isPending ? 'جارٍ الحذف...' : 'حذف نهائي'}
          </button>
        </div>
      </form>
    </div>,
    document.body,
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

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <form onSubmit={(e) => void onSubmit(e)} className="card w-full max-w-md space-y-4 p-6" role="dialog" aria-modal="true">
        <h2 className="text-lg font-black">إضافة إدارة للموظف</h2>
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
    </div>,
    document.body,
  );
}

// ---------------------------------------------------------------------------
// EmployeeDetailPage — Main component
// ---------------------------------------------------------------------------
export function EmployeeDetailPage() {
  const { employeeId } = useParams();
  const auth = useAuth();
  const query = useEmployee360(employeeId);
  const resend = useResendInvite();
  const { toast } = useToast();
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
        title="ملف الموظف"
        description="عرض شامل للبيانات الوظيفية والحضور والطلبات والأداء والمستندات."
        actions={
          <div className="flex flex-wrap gap-2">
            {showResend ? (
              <button type="button" className="btn-secondary" disabled={resend.isPending} onClick={() => void onResend()}>
                <MailCheck className="size-4" aria-hidden="true" />
                {resend.isPending ? 'جارٍ الإرسال…' : 'إعادة إرسال دعوة التفعيل'}
              </button>
            ) : null}
            {canEdit ? (
              <button type="button" className="btn-primary" onClick={() => setShowEditDialog(true)}>
                <Pencil className="size-4" aria-hidden="true" />
                تعديل البيانات
              </button>
            ) : null}
            {canEdit && item.isActive ? (
              <button type="button" className="btn-secondary text-[var(--danger)]" onClick={() => setShowArchiveDialog(true)}>
                <Archive className="size-4" aria-hidden="true" />
                أرشفة الموظف
              </button>
            ) : null}
            {canEdit ? (
              <button type="button" className="btn-secondary text-[var(--danger)]" onClick={() => setShowDeleteDialog(true)}>
                <Trash2 className="size-4" aria-hidden="true" />
                حذف الموظف
              </button>
            ) : null}
            <Link to="/hr/employees" className="btn-secondary">
              <ArrowRight className="size-4" aria-hidden="true" />
              عودة للموظفين
            </Link>
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

      <section className="card flex flex-col gap-5 p-5 lg:flex-row lg:items-center">
        <UserAvatar displayName={item.fullNameAr} photoUrl={item.photoUrl} size="lg" eager />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-3">
            <h2 className="text-2xl font-black">{item.fullNameAr}</h2>
            <StatusBadge status={item.status} />
          </div>
          <p className="muted mt-1">
            {item.jobTitle ?? 'بدون مسمى وظيفي'} • {item.employeeCode}
          </p>
          <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-sm">
            <Info icon={Network} label={item.department ?? 'بدون إدارة'} />
            <Info icon={Phone} label={item.phoneE164 ? renderSafeIntlPhoneText(item.phoneE164) : 'بدون هاتف'} />
            <Info icon={Mail} label={item.email ?? 'بدون بريد'} />
            <Info icon={ShieldCheck} label={`الحساب: ${item.accountStatus ?? 'غير مرتبط'}`} />
          </div>
        </div>
        <div className="rounded-2xl bg-[var(--surface-muted)] p-4 text-sm lg:min-w-64">
          <p className="font-black">العلاقة الإدارية</p>
          <div className="mt-2 flex items-center justify-between gap-2">
            <p className="muted">
              المدير المباشر: <span className="font-bold text-[var(--text)]">{item.managerName ?? 'غير معين'}</span>
            </p>
            {canEdit ? (
              <button type="button" onClick={() => setShowManagerDialog(true)} className="text-brand font-bold text-xs">
                تغيير
              </button>
            ) : null}
          </div>
          <p className="muted mt-1">المرؤوسون المباشرون: {item.directReports}</p>
          <div className="mt-1 flex items-center justify-between gap-2">
            <p className="muted">الأدوار: {item.roles.map((role) => role.name).join('، ') || 'لا توجد'}</p>
            {hasPermission(auth.access, 'access.role.read') ? (
              <Link to="/admin/access" className="text-brand font-bold text-xs">
                إدارة الصلاحيات
              </Link>
            ) : null}
          </div>
        </div>
      </section>

      <section className="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="أيام الحضور — 30 يومًا" value={item.attendance30.present} hint={`${item.attendance30.lateDays} أيام تأخير`} icon={BadgeCheck} />
        <MetricCard label="أيام الغياب" value={item.attendance30.absent} icon={Clock3} />
        <MetricCard label="الطلبات المعلقة" value={item.requestCounts.pending} hint={`${item.requestCounts.approved} معتمدة`} icon={FileText} />
        <MetricCard
          label="أحدث تقييم"
          value={item.latestKpi?.finalScore ?? item.latestKpi?.currentStage ?? '—'}
          hint={item.latestKpi?.finalRating ?? undefined}
          icon={Gauge}
        />
      </section>

      <section className="grid gap-5 xl:grid-cols-2">
        <article className="card p-5">
          <h3 className="font-black">البيانات الوظيفية</h3>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <Data label="الإدارة" value={item.department} />
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
        <article className="card overflow-hidden">
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

      {/* إدارات الموظف — V17 multi-department */}
      {employeeId && <DepartmentsSection employeeId={employeeId} canEdit={canEdit} onAdd={() => setShowAddDeptDialog(true)} />}

      {/* كشف الحضور والانصراف الشهري (V12 §18) */}
      {employeeId && <MonthlyStatementSection employeeId={employeeId} />}

      {/* آخر التعديلات الهامة على الملف */}
      {employeeId && <EmployeeEditHistory employeeId={employeeId} />}

      <p className="muted flex items-center gap-2 text-xs">
        <CalendarDays className="size-4" aria-hidden="true" />
        آخر تحديث: {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.lastUpdatedAt))}
      </p>

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
    </div>
  );
}
