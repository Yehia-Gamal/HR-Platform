import { createEmployeeInputSchema, createEmployeeResultSchema } from '@ahla/shared-contracts';
import { zodResolver } from '@hookform/resolvers/zod';
import type { z } from 'zod';
import { ArrowRight, Check, CheckCircle2, ChevronLeft, ChevronRight, Eye, EyeOff, ImagePlus, Loader2, UserPlus, X } from 'lucide-react';
import { type ReactNode, useEffect, useMemo, useRef, useState } from 'react';
import { useForm } from 'react-hook-form';
import { Link } from 'react-router';
import { getSupabase } from '../../core/supabase';
import { safeErrorMessage } from '../../core/errorMapper';
import { PageHeader } from '../../ui/PageHeader';
import { UserAvatar } from '../../ui/UserAvatar';
import { prepareAvatarFile } from '../../ui/avatarImage';
import { fixIntlPhoneOrder, sanitizePhoneInput } from '../../ui/phoneDisplay';
import { useAuth } from '../auth/AuthProvider';
import { ErrorBanner } from '../../ui/ErrorState';
import { useOrganizationLookups } from './useOrganizationLookups';

type FormInput = z.input<typeof createEmployeeInputSchema>;
const defaultValues: Partial<FormInput> = { roleSlug: 'employee', sendInvite: false, initialPassword: '' };
const uuidValue = { setValueAs: (value: string) => value || null };
const steps = ['الهوية والحساب', 'الهيكل والوظيفة', 'المراجعة والإنشاء'];

export function CreateEmployeePage() {
  const auth = useAuth();
  const lookups = useOrganizationLookups();
  const [step, setStep] = useState(0);
  const [result, setResult] = useState<string | null>(null);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const [photoUploading, setPhotoUploading] = useState(false);
  const [photoError, setPhotoError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const photoObjectUrlRef = useRef<string | null>(null);
  const uploadedPhotoPathRef = useRef<string | null>(null);
  const form = useForm<FormInput>({ resolver: zodResolver(createEmployeeInputSchema), defaultValues });
  const values = form.watch();
  const options = lookups.data;
  const [branchText, setBranchText] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const branches = useMemo(() => options?.branches ?? [], [options?.branches]);
  const matchedBranch = useMemo(() => branches.find((b) => b.label === branchText.trim()) ?? null, [branches, branchText]);
  const workSites = useMemo(() => {
    const all = options?.workSites ?? [];
    return matchedBranch ? all.filter((item) => item.parentId === matchedBranch.id) : all;
  }, [options, matchedBranch]);

  useEffect(
    () => () => {
      if (photoObjectUrlRef.current) URL.revokeObjectURL(photoObjectUrlRef.current);
      const orphanPath = uploadedPhotoPathRef.current;
      if (orphanPath && !auth.isMock) {
        void getSupabase()
          .then((supabase) => supabase.storage.from('employee-avatars').remove([orphanPath]))
          .catch(() => undefined /* best-effort cleanup */);
      }
    },
    [auth.isMock],
  );

  const clearObjectPreview = () => {
    if (photoObjectUrlRef.current) URL.revokeObjectURL(photoObjectUrlRef.current);
    photoObjectUrlRef.current = null;
  };

  const next = async () => {
    if (photoUploading) return;
    const fields: Array<keyof FormInput> = step === 0 ? ['fullNameAr', 'email', 'phoneE164', 'initialPassword'] : [];
    if (fields.length && !(await form.trigger(fields))) return;
    setStep((current) => Math.min(2, current + 1));
  };

  const onPickPhoto = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    const previousPreview = photoPreview;
    const previousUrl = form.getValues('photoUrl');
    const previousPath = uploadedPhotoPathRef.current;
    setPhotoError(null);
    setPhotoUploading(true);
    try {
      const prepared = await prepareAvatarFile(file);
      clearObjectPreview();
      photoObjectUrlRef.current = URL.createObjectURL(prepared);
      setPhotoPreview(photoObjectUrlRef.current);
      if (auth.isMock) {
        form.setValue('photoUrl', 'https://example.com/mock-avatar.webp');
        return;
      }
      const supabase = await getSupabase();
      const path = `admin/${crypto.randomUUID()}.webp`;
      const { error } = await supabase.storage.from('employee-avatars').upload(path, prepared, { upsert: false, contentType: prepared.type });
      if (error) throw error;
      const { data } = supabase.storage.from('employee-avatars').getPublicUrl(path);
      form.setValue('photoUrl', data.publicUrl, { shouldValidate: true });
      uploadedPhotoPathRef.current = path;
      clearObjectPreview();
      setPhotoPreview(data.publicUrl);
      if (previousPath && previousPath !== path) {
        await supabase.storage.from('employee-avatars').remove([previousPath]);
      }
    } catch (error) {
      clearObjectPreview();
      setPhotoPreview(previousPreview);
      form.setValue('photoUrl', previousUrl);
      // أخطاء التحقق المحلية (حجم/دقة/صيغة) من prepareAvatarFile عربية وآمنة — تُعرض مباشرة.
      // أخطاء الرفع الخادمية (storage) تحتوي خصائص status/statusCode — تُمرر عبر safeErrorMessage.
      const isLocalValidation = error instanceof Error && !('statusCode' in error) && !('status' in error);
      setPhotoError(isLocalValidation ? error.message : safeErrorMessage(error));
    } finally {
      setPhotoUploading(false);
    }
  };
  const removePhoto = async () => {
    const path = uploadedPhotoPathRef.current;
    uploadedPhotoPathRef.current = null;
    clearObjectPreview();
    setPhotoPreview(null);
    setPhotoError(null);
    form.setValue('photoUrl', undefined);
    if (path && !auth.isMock) {
      try {
        const supabase = await getSupabase();
        await supabase.storage.from('employee-avatars').remove([path]);
      } catch {
        setPhotoError('أزيلت الصورة من النموذج، وتعذر تنظيف الملف المؤقت الآن.');
      }
    }
  };

  const submit = form.handleSubmit(async (raw) => {
    // حل النص الحر → معرّف قبل التحقق
    raw.branchId = matchedBranch?.id ?? null;
    const parsedInput = createEmployeeInputSchema.parse(raw);
    setResult(null);
    setSubmitError(null);
    try {
      if (auth.isMock) {
        setResult('تم التحقق من الرحلة كاملة في وضع التطوير دون حفظ بيانات.');
        return;
      }
      const supabase = await getSupabase();
      const { data, error } = await supabase.functions.invoke('admin-create-employee', { body: parsedInput });
      if (error) throw error;
      const parsed = createEmployeeResultSchema.parse(data);
      const baseMessage =
        parsedInput.sendInvite
          ? parsed.invitationSent
            ? 'تم إنشاء الموظف والحساب وإرسال رابط التفعيل بنجاح.'
            : 'تم إنشاء الموظف والحساب، لكن تعذر إرسال رابط التفعيل.'
          : 'تم إنشاء الموظف بنجاح — نشط وجاهز للعمل فوراً.';
      const passwordMessage = parsed.temporaryPassword
        ? ` كلمة المرور المؤقتة: ${parsed.temporaryPassword} — تُعرض الآن مرة واحدة فقط.`
        : '';
      setResult(`${baseMessage}${passwordMessage} سيتحتم على الموظف تغيير كلمة المرور عند أول دخول. المعرّف: ${parsed.employeeId}`);
      uploadedPhotoPathRef.current = null;
      form.reset(defaultValues);
      setStep(0);
      clearObjectPreview();
      setPhotoPreview(null);
      setBranchText('');
    } catch (error) {
      // رسائل خطأ عربية مفهومة بدل الرسائل الإنجليزية العامة من supabase-js
      const errorMessages: Record<string, string> = {
        account_already_exists: 'يوجد حساب مسجل بهذا البريد الإلكتروني بالفعل.',
        forbidden: 'ليس لديك صلاحية إنشاء موظفين.',
        role_not_allowed: 'المنصب المختار غير مسموح به.',
        phone_already_exists: 'رقم الهاتف مسجل لموظف نشط بالفعل.',
        employee_code_already_exists: 'كود الموظف مستخدم بالفعل.',
        employee_provision_failed: 'تعذر إنشاء سجل الموظف. تحقق من البيانات وحاول مرة أخرى.',
        server_not_configured: 'الخدمة غير مهيأة. تواصل مع الدعم.',
        invalid_session: 'انتهت صلاحية الجلسة. سجّل الدخول مجددًا.',
        permission_check_failed: 'تعذر التحقق من الصلاحية.',
        validation_failed: 'بيانات النموذج غير صالحة. راجع الحقول وحاول مرة أخرى.',
        role_validation_failed: 'تعذر التحقق من المنصب المختار.',
        protected_role_not_allowed: 'لا يمكن إسناد هذا المنصب المحمي.',
        role_authorization_failed: 'تعذر التحقق من صلاحية إسناد المنصب.',
        role_assignment_forbidden: 'ليس لديك صلاحية إسناد هذا المنصب.',
        account_create_failed: 'تعذر إنشاء حساب الدخول. أعد المحاولة لاحقًا.',
        manager_not_active: 'المدير المباشر المختار غير نشط.',
        password_too_short_min_12: 'كلمة المرور يجب ألا تقل عن 12 حرفًا.',
        password_too_long_max_72: 'كلمة المرور يجب ألا تزيد عن 72 حرفًا.',
        password_needs_uppercase: 'كلمة المرور يجب أن تحتوي حرفًا كبيرًا واحدًا على الأقل.',
        password_needs_lowercase: 'كلمة المرور يجب أن تحتوي حرفًا صغيرًا واحدًا على الأقل.',
        password_needs_digit: 'كلمة المرور يجب أن تحتوي رقمًا واحدًا على الأقل.',
        password_needs_symbol: 'كلمة المرور يجب أن تحتوي رمزًا خاصًا واحدًا على الأقل (!@#$%^&*...).',
        password_keyboard_sequence: 'كلمة المرور تحتوي تسلسلًا شائعًا من لوحة المفاتيح.',
        password_contains_common_word: 'كلمة المرور تحتوي كلمة شائعة ممنوعة.',
        password_contains_identifier: 'كلمة المرور تشبه بيانات الموظف (الاسم/الهاتف/البريد/الكود).',
        password_too_repetitive: 'كلمة المرور تحتوي تكرارًا مفرطًا لنفس الحرف (5+ على التوالي).',
        weak_password: 'كلمة المرور غير آمنة. اختر كلمة مرور أقوى.',
      };
      let message = 'تعذر إنشاء الموظف.';
      if (error && typeof error === 'object' && 'context' in error && (error as { context: unknown }).context instanceof Response) {
        try {
          const body = await (error as { context: Response }).context.json();
          message = errorMessages[body?.error] ?? message;
        } catch {
          /* fallback */
        }
      } else if (error instanceof Error) {
        message = errorMessages[error.message] ?? message;
      }
      setSubmitError(message);
    }
  });

  return (
    <div>
      <PageHeader
        title="إنشاء موظف وحساب دخول"
        description="إنشاء ملف الموظف وحساب الدخول في رحلة موحدة بخطوات واضحة."
        actions={
          <Link to="/hr/employees" className="btn-secondary text-sm">
            <ArrowRight className="size-4" aria-hidden="true" />
            رجوع
          </Link>
        }
      />
      <section className="mx-auto max-w-5xl">
        <ol className="mb-5 grid grid-cols-3 gap-2">
          {steps.map((label, index) => (
            <li
              key={label}
              className={`rounded-xl border p-3 text-center text-xs font-black ${index === step ? 'border-brand bg-brand text-white' : index < step ? 'border-[var(--success)] bg-[var(--success-soft)] text-[var(--success)]' : 'border-[var(--border)] bg-[var(--surface)] muted'}`}
            >
              {index < step ? <Check className="mx-auto mb-1 size-4" aria-hidden="true" /> : <span className="mb-1 block">{index + 1}</span>}
              {label}
            </li>
          ))}
        </ol>
        <form onSubmit={submit} className="card p-5 sm:p-7">
          {result ? (
            <div className="mb-5 flex gap-2 rounded-xl border border-[var(--success)] bg-[var(--success-soft)] p-4 text-sm text-[var(--success)]">
              <CheckCircle2 className="size-5 shrink-0" aria-hidden="true" />
              {result}
            </div>
          ) : null}
          {submitError ? (
            <div className="mb-5">
              <ErrorBanner message={submitError} />
            </div>
          ) : null}
          {step === 0 ? (
            <div>
              <SectionTitle title="الهوية وحساب الدخول" description="البيانات الأساسية والصورة الشخصية ومعرف الدخول." />
              <div className="mb-6 flex items-center gap-5">
                <div className="relative size-24 shrink-0">
                  {photoPreview ? (
                    <UserAvatar
                      displayName={values.fullNameAr ?? 'صورة الموظف'}
                      photoUrl={photoPreview}
                      size="lg"
                      eager
                      announceName={false}
                      className="!size-24 !rounded-2xl"
                    />
                  ) : (
                    <div className="flex size-full items-center justify-center rounded-2xl border border-[var(--border)] bg-[var(--surface-muted)] text-[var(--text-muted)]">
                      <ImagePlus className="size-8" aria-hidden="true" />
                    </div>
                  )}
                  {photoUploading ? (
                    <div className="absolute inset-0 flex items-center justify-center bg-black/40">
                      <Loader2 className="size-6 animate-spin text-white" aria-hidden="true" />
                    </div>
                  ) : null}
                </div>
                <div>
                  <p className="mb-2 text-sm font-semibold">الصورة الشخصية</p>
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={() => fileInputRef.current?.click()}
                      disabled={photoUploading}
                      className="inline-flex min-h-11 items-center gap-2 rounded-xl border border-[var(--border)] px-3 py-2 text-sm font-semibold disabled:opacity-50"
                    >
                      <ImagePlus className="size-4" aria-hidden="true" />
                      {photoPreview ? 'تغيير الصورة' : 'رفع صورة'}
                    </button>
                    {photoPreview ? (
                      <button
                        type="button"
                        onClick={() => void removePhoto()}
                        className="inline-flex min-h-11 items-center gap-2 rounded-xl border border-[var(--danger)] px-3 py-2 text-sm font-semibold text-[var(--danger)]"
                      >
                        <X className="size-4" aria-hidden="true" />
                        إزالة
                      </button>
                    ) : null}
                  </div>
                  <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={onPickPhoto} />
                  <p className="muted mt-1.5 text-xs">JPG أو PNG أو WEBP · حتى 5 ميجابايت · 512×512 على الأقل · تُقص تلقائيًا كمربع</p>
                  {photoError ? <p className="mt-1 text-xs text-[var(--danger)]">{photoError}</p> : null}
                </div>
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="الاسم الكامل بالعربية" error={form.formState.errors.fullNameAr?.message}>
                  <input className="input" {...form.register('fullNameAr')} />
                </Field>
                <Field label="الهاتف" error={form.formState.errors.phoneE164?.message}>
                  <input
                    className="input"
                    dir="ltr"
                    inputMode="tel"
                    autoComplete="tel"
                    placeholder="01154869616"
                    maxLength={15}
                    {...form.register('phoneE164', {
                      setValueAs: (v: string) => sanitizePhoneInput(v, 15),
                    })}
                  />
                </Field>
                <Field label="البريد الإلكتروني" error={form.formState.errors.email?.message}>
                  <input type="email" className="input" dir="ltr" autoComplete="email" {...form.register('email')} />
                </Field>
                <Field
                  label="كلمة المرور الأولية"
                  error={form.formState.errors.initialPassword?.message}
                  hint="اختياري — اتركه فارغاً لتولّد الخادم كلمة مرور مؤقتة آمنة. إن أدخلتها: 12–72 حرفًا بحرف كبير وصغير ورقم ورمز خاص."
                >
                  <span className="relative block">
                    <input
                      type={showPassword ? 'text' : 'password'}
                      className="input !ps-14"
                      dir="ltr"
                      autoComplete="new-password"
                      placeholder="اختياري — تُولَّد تلقائيًا"
                      {...form.register('initialPassword', { setValueAs: (v: string) => v.trim() || undefined })}
                    />
                    <button
                      type="button"
                      className="password-visibility-button"
                      aria-label={showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'}
                      onClick={() => setShowPassword((value) => !value)}
                    >
                      {showPassword ? <EyeOff className="size-4" aria-hidden="true" /> : <Eye className="size-4" aria-hidden="true" />}
                    </button>
                  </span>
                </Field>
                <SelectField
                  label="الدور"
                  options={(options?.roles ?? []).map((r) => ({ id: r.slug, label: r.label }))}
                  register={form.register('roleSlug')}
                  placeholder="اختر دور الحساب"
                  hint="أدوار الوصول الكامل (admin) تُمنح لاحقاً يدوياً عبر صفحة الأدوار والصلاحيات — لا تُحدد عند الإنشاء."
                />
                <Field label="تاريخ التعيين" error={form.formState.errors.hireDate?.message}>
                  <input type="date" className="input" {...form.register('hireDate', { setValueAs: (v: string) => v || undefined })} />
                </Field>
                <label className="flex items-center gap-3 self-end rounded-xl bg-[var(--surface-muted)] p-3 text-sm font-semibold">
                  <input type="checkbox" className="size-4" {...form.register('sendInvite')} />
                  إرسال دعوة تفعيل عبر البريد
                </label>
              </div>
            </div>
          ) : null}
          {step === 1 ? (
            <div>
              <SectionTitle title="الهيكل والوظيفة" description="تحديد الفرع وموقع العمل والمدير المباشر والمسمى الوظيفي." />
              {lookups.isError ? (
                <div className="mb-4">
                  <ErrorBanner message={`تعذر تحميل بيانات الهيكل: ${safeErrorMessage(lookups.error)}`} />
                </div>
              ) : null}
              <div className="grid gap-4 sm:grid-cols-2">
                <label className="block">
                  <span className="mb-1.5 block text-sm font-semibold">الفرع</span>
                  <input
                    type="text"
                    className="input"
                    list="create-branches"
                    value={branchText}
                    onChange={(e) => setBranchText(e.target.value)}
                    placeholder="اكتب أو اختر الفرع…"
                  />
                  <datalist id="create-branches">
                    {branches.map((b) => (
                      <option key={b.id} value={b.label} />
                    ))}
                  </datalist>
                </label>
                <SelectField label="موقع العمل" options={workSites} register={form.register('workSiteId', uuidValue)} placeholder="اختر موقع العمل" />
                <SelectField
                  label="المدير المباشر"
                  options={options?.managers ?? []}
                  register={form.register('managerEmployeeId', uuidValue)}
                  placeholder="بدون مدير"
                />
                <JobTitleField label="المسمى الوظيفي" options={options?.jobTitles ?? []} register={form.register('jobTitleName')} />
              </div>
            </div>
          ) : null}
          {step === 2 ? (
            <div>
              <SectionTitle title="مراجعة البيانات" description="راجع البيانات قبل إنشاء ملف الموظف وحساب الدخول." />
              {photoPreview ? (
                <div className="mb-4 flex justify-center">
                  <UserAvatar
                    displayName={values.fullNameAr ?? ''}
                    photoUrl={photoPreview}
                    size="lg"
                    eager
                    announceName={false}
                    className="!size-20 !rounded-2xl"
                  />
                </div>
              ) : null}
              <div className="grid gap-3 sm:grid-cols-2">
                <Review label="الاسم" value={values.fullNameAr} />
                <Review label="الهاتف" value={values.phoneE164 ? fixIntlPhoneOrder(values.phoneE164) : undefined} />
                <Review label="البريد" value={values.email} />
                <Review label="الفرع" value={branchText || undefined} />
                <Review label="موقع العمل" value={options?.workSites.find((x) => x.id === values.workSiteId)?.label} />
                <Review label="المدير" value={options?.managers.find((x) => x.id === values.managerEmployeeId)?.label} />
                <Review label="المسمى الوظيفي" value={values.jobTitleName} />
                <Review label="الدور" value={options?.roles.find((r) => r.slug === values.roleSlug)?.label} />
                <Review label="تاريخ التعيين" value={values.hireDate as string | undefined} />
                <Review label="كلمة المرور الأولية" value={values.initialPassword ? 'أُدخلت يدويًا (لا تظهر هنا)' : 'تُولَّد تلقائيًا'} />
                <Review label="دعوة التفعيل" value={values.sendInvite ? 'نعم — سيُرسل رابط تفعيل' : 'لا'} />
              </div>
              <div className="mt-5 rounded-xl bg-[var(--surface-muted)] p-4 text-sm leading-7">
                سيتم إنشاء Auth User وEmployee وProfile وإسناد الدور والمدير داخل مسار خادمي. عند فشل أي جزء تُنفذ عملية تعويض ولا يُترك حساب يتيم. كود الموظف
                يُشتق تلقائياً من رقم الهاتف، وكلمة المرور (أو المؤقتة المولّدة) تُجبر على التغيير عند أول دخول من المتصفح أو التطبيق ولا تبقى سارية.
              </div>
            </div>
          ) : null}
          <div className="mt-7 flex items-center justify-between border-t border-[var(--border)] pt-5">
            <button type="button" className="btn-secondary" disabled={step === 0} onClick={() => setStep((current) => current - 1)}>
              <ChevronRight className="size-4" aria-hidden="true" />
              السابق
            </button>
            {step < 2 ? (
              <button type="button" className="btn-primary" onClick={() => void next()}>
                التالي
                <ChevronLeft className="size-4" aria-hidden="true" />
              </button>
            ) : (
              <button type="submit" disabled={form.formState.isSubmitting} className="btn-primary">
                <UserPlus className="size-4" aria-hidden="true" />
                {form.formState.isSubmitting ? 'جارٍ الإنشاء…' : 'إنشاء الموظف والحساب'}
              </button>
            )}
          </div>
        </form>
      </section>
    </div>
  );
}
function SectionTitle({ title, description }: { title: string; description: string }) {
  return (
    <div className="mb-6 border-b border-[var(--border)] pb-5">
      <h2 className="text-lg font-black">{title}</h2>
      <p className="muted mt-1 text-sm">{description}</p>
    </div>
  );
}
function Field({ label, error, hint, children }: { label: string; error?: string; hint?: string; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold">{label}</span>
      {children}
      {hint ? <span className="muted mt-1 block text-xs">{hint}</span> : null}
      <span className="mt-1 block min-h-4 text-xs text-[var(--danger)]">{error}</span>
    </label>
  );
}
function SelectField({
  label,
  options,
  register,
  placeholder,
  hint,
}: {
  label: string;
  options: Array<{ id: string; label: string }>;
  register: Record<string, unknown>;
  placeholder?: string;
  hint?: string;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold">{label}</span>
      <select className="input" aria-label={label} {...register}>
        <option value="">{placeholder ?? 'غير محدد'}</option>
        {options.map((item) => (
          <option key={item.id} value={item.id}>
            {item.label}
          </option>
        ))}
      </select>
      {hint ? <span className="muted mt-1 block text-xs">{hint}</span> : null}
    </label>
  );
}
// المسمى الوظيفي: إدخال حر مع اقتراحات من المسميات الموجودة (datalist).
function JobTitleField({ label, options, register }: { label: string; options: Array<{ id: string; label: string }>; register: Record<string, unknown> }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold">{label}</span>
      <input className="input" list="job-titles-list" aria-label={label} placeholder="اكتب مسمى جديد أو اختر من الموجود" {...register} />
      <datalist id="job-titles-list">
        {options.map((item) => (
          <option key={item.id} value={item.label} />
        ))}
      </datalist>
    </label>
  );
}
function Review({ label, value }: { label: string; value?: string | null }) {
  return (
    <div className="rounded-xl bg-[var(--surface-muted)] p-4">
      <p className="muted text-xs font-bold">{label}</p>
      <p className="mt-1 font-black">{value || 'غير محدد'}</p>
    </div>
  );
}
