import type { Employee360 } from '@ahla/shared-contracts';
import { ImagePlus, Lock } from 'lucide-react';
import { useEffect, useMemo, useRef, useState, type ChangeEvent, type FormEvent } from 'react';
import { safeErrorMessage } from '../../../core/errorMapper';
import { getSupabase } from '../../../core/supabase';
import { prepareAvatarFile } from '../../../ui/avatarImage';
import { DialogOverlay } from '../../../ui/DialogOverlay';
import { ErrorBanner } from '../../../ui/ErrorState';
import { fixIntlPhoneOrder } from '../../../ui/phoneDisplay';
import { UserAvatar } from '../../../ui/UserAvatar';
import { useAuth } from '../../auth/AuthProvider';
import { hasPermission } from '../../workspaces/access';
import { normalizePhoneForSubmit } from '../employeeDetailShared';
import { useSyncEmployeeDepartments, useUpdateEmployee, useUpdateEmployeeEmail } from '../useEmployees';
import { useOrganizationLookups } from '../useOrganizationLookups';
import { EditEmployeePasswordSection } from './EditEmployeePasswordSection';
import { JobTitleInput, LookupSelect } from './EmployeeDetailPrimitives';
import { MultiDepartmentPicker } from './MultiDepartmentPicker';

export function EditEmployeeDialog({ item, onClose, onSuccess }: { item: Employee360; onClose: () => void; onSuccess: () => void }) {
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

  const [branchId, setBranchId] = useState(item.branchId ?? '');
  const [workSiteId, setWorkSiteId] = useState(item.workSiteId ?? '');
  // المسمى الوظيفي يُحرَّر كنص حر (مع اقتراحات datalist)؛ المطابقة/الإنشاء يتمان عند الحفظ.
  const [jobTitleText, setJobTitleText] = useState(item.jobTitle ?? '');
  const [hireDate, setHireDate] = useState(item.hireDate ?? '');

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

  const jobTitleOptions = useMemo(() => {
    const opts = lookups.data?.jobTitles ?? [];
    const current = item.jobTitle;
    if (current && !opts.some((o) => o.label === current)) {
      return [...opts, { id: item.jobTitleId ?? 'current-job-title', label: current }];
    }
    return opts;
  }, [lookups.data?.jobTitles, item.jobTitle, item.jobTitleId]);

  const [error, setError] = useState<string | null>(null);

  // Filter child lookups by parent selection
  const workSites = useMemo(() => {
    const opts = lookups.data?.workSites ?? [];
    return branchId ? opts.filter((s) => s.parentId === branchId) : opts;
  }, [lookups.data?.workSites, branchId]);

  const onBranchChange = (value: string) => {
    setBranchId(value);
    const nextSites = (lookups.data?.workSites ?? []).filter((s) => !value || s.parentId === value);
    if (workSiteId && nextSites.every((s) => s.id !== workSiteId)) setWorkSiteId('');
  };

  // رفع صورة شخصية جديدة إلى storage ثم عرضها مؤقتاً حتى الحفظ.
  const onAvatarChange = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setPhotoError(null);
    try {
      setPhotoUploading(true);
      const prepared = await prepareAvatarFile(file);
      const supabase = await getSupabase();
      const path = `admin/${crypto.randomUUID()}.webp`;
      const { error: uploadErr } = await supabase.storage.from('employee-avatars').upload(path, prepared, { upsert: false, contentType: prepared.type });
      if (uploadErr) throw uploadErr;
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

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);

    const changes: Record<string, unknown> = {};
    if (fullNameAr.trim() !== item.fullNameAr) changes.fullNameAr = fullNameAr.trim();
    if ((photoUrl || null) !== (item.photoUrl ?? null)) changes.photoUrl = photoUrl || null;
    const phoneNext = normalizePhoneForSubmit(phoneE164);
    if (phoneNext !== (item.phoneE164 ?? '')) changes.phoneE164 = phoneNext || null;

    if (canSensitive) {
      if ((primaryDeptId || null) !== (item.departmentId ?? null)) changes.departmentId = primaryDeptId || null;
      if ((branchId || null) !== (item.branchId ?? null)) changes.branchId = branchId || null;
      if ((workSiteId || null) !== (item.workSiteId ?? null)) changes.workSiteId = workSiteId || null;
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
              <MultiDepartmentPicker
                baseDepartments={lookups.data?.departments ?? []}
                selectedDeptIds={selectedDeptIds}
                primaryDeptId={primaryDeptId}
                onSelectedChange={setSelectedDeptIds}
                onPrimaryChange={setPrimaryDeptId}
              />

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

      {canSensitive ? <EditEmployeePasswordSection employeeId={item.id} /> : null}
    </DialogOverlay>
  );
}
