import { CheckCircle2, Eye, EyeOff, KeyRound, Mail, ShieldCheck } from 'lucide-react';
import { type FormEvent, useEffect, useState } from 'react';
import { useNavigate } from 'react-router';
import { safeErrorMessage } from '../../core/errorMapper';
import { rpc } from '../../core/rpc';
import { getSupabase } from '../../core/supabase';
import { AppLogo } from '../../ui/AppLogo';

type RecoveryLocation = Pick<Location, 'pathname' | 'hash'> & Partial<Pick<Location, 'search'>>;
type PageState = 'checking' | 'ready' | 'invalid' | 'success';
type RecoveryLinkError = { code: string | null; description: string | null };

function recoveryParams(location: RecoveryLocation) {
  const params = new URLSearchParams(location.search ?? '');
  const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
  hash.forEach((value, key) => params.set(key, value));
  return params;
}

export function getPasswordRecoveryError(location: RecoveryLocation = window.location): RecoveryLinkError | null {
  const params = recoveryParams(location);
  const code = params.get('error_code');
  const description = params.get('error_description');
  const error = params.get('error');
  if (!code && !description && error !== 'access_denied') return null;
  return { code, description };
}

export function isPasswordRecoveryLocation(location: RecoveryLocation = window.location): boolean {
  if (location.pathname === '/auth/setup-password') return true;
  const params = recoveryParams(location);
  return params.get('type') === 'recovery' || getPasswordRecoveryError(location) !== null;
}

function clearRecoverySecretsFromAddressBar() {
  if (!window.location.hash) return;
  window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}`);
}

export function PasswordSetupPage() {
  const navigate = useNavigate();
  const [initialLinkError] = useState(() => getPasswordRecoveryError());
  const [pageState, setPageState] = useState<PageState>('checking');
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [recoveryEmail, setRecoveryEmail] = useState('');
  const [resending, setResending] = useState(false);
  const [resendSent, setResendSent] = useState(false);
  const [resendError, setResendError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    void getSupabase()
      .then(async (supabase) => {
        if (initialLinkError) {
          // قد توجد جلسة قديمة أنشأها رابط سابق؛ لا نسمح لها بالوصول إلى بوابات الويب.
          await supabase.auth.signOut({ scope: 'local' }).catch(() => undefined);
          clearRecoverySecretsFromAddressBar();
          if (active) setPageState('invalid');
          return;
        }
        const { data, error: sessionError } = await supabase.auth.getSession();
        clearRecoverySecretsFromAddressBar();
        if (!active) return;
        setPageState(sessionError || !data.session ? 'invalid' : 'ready');
      })
      .catch(() => {
        clearRecoverySecretsFromAddressBar();
        if (active) setPageState('invalid');
      });
    return () => {
      active = false;
    };
  }, [initialLinkError]);

  const resendRecoveryLink = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setResendError(null);
    setResending(true);
    try {
      const supabase = await getSupabase();
      const redirectTo = `${window.location.origin}/auth/setup-password`;
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(recoveryEmail.trim().toLowerCase(), { redirectTo });
      if (resetError) throw resetError;
      setResendSent(true);
    } catch (resetError) {
      setResendError(safeErrorMessage(resetError));
    } finally {
      setResending(false);
    }
  };

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);
    if (password.length < 8) {
      setError('كلمة المرور يجب ألا تقل عن 8 أحرف.');
      return;
    }
    if (password !== confirmation) {
      setError('كلمتا المرور غير متطابقتين.');
      return;
    }

    setSubmitting(true);
    try {
      const supabase = await getSupabase();

      // 1) التحقق من صلاحية جلسة الاسترداد
      const { data: userData, error: userError } = await supabase.auth.getUser();
      if (userError || !userData.user) {
        setError('انتهت صلاحية رابط التفعيل. اطلب رابط تفعيل جديدًا ثم حاول مرة أخرى.');
        return;
      }

      // 2) تعيين كلمة المرور الجديدة
      const { error: updateError } = await supabase.auth.updateUser({
        password,
      });
      if (updateError) {
        // رسائل خطأ محددة لسياسات كلمة المرور
        const msg = updateError.message?.toLowerCase() ?? '';
        if (msg.includes('weak') || msg.includes('strength') || msg.includes('policy') || msg.includes('short')) {
          setError('كلمة المرور ضعيفة. استخدم مزيجًا من الأحرف الكبيرة والصغيرة والأرقام، بطول لا يقل عن 8 أحرف.');
        } else if (msg.includes('same') || msg.includes('previous') || msg.includes('reuse')) {
          setError('لا يمكن إعادة استخدام نفس كلمة المرور السابقة. اختر كلمة مرور مختلفة.');
        } else if (msg.includes('session') || msg.includes('token') || msg.includes('expired')) {
          setError('انتهت صلاحية رابط التفعيل. اطلب رابط تفعيل جديدًا ثم حاول مرة أخرى.');
        } else {
          setError(safeErrorMessage(updateError));
        }
        return;
      }

      // 3) تفعيل سجل الموظف (اختياري — لا يُفشل العملية)
      let activationOk = false;
      try {
        const activationResult = await rpc<{ activated?: boolean; reason?: string } | null>('activate_employee_after_first_login');
        // نقبل: activated=true، already_active، أو no_employee_record (حساب ويب بدون سجل موظف)
        activationOk =
          activationResult?.activated === true || activationResult?.reason === 'already_active' || activationResult?.reason === 'no_employee_record';
      } catch {
        // كلمة المرور تم تعيينها بنجاح لكن التفعيل فشل — نُكمل مع تحذير
        // (لا نمنع المستخدم من إنهاء العملية)
      }
      void activationOk; // referenced for future logging

      // 4) إزالة علامة must_change_password (تكتب في app_metadata عبر SECURITY DEFINER — ثانوي)
      try {
        await rpc('clear_must_change_password');
      } catch {
        // ثانوي — كلمة المرور تم تعيينها بنجاح
      }

      await supabase.auth.signOut({ scope: 'global' });
      setPassword('');
      setConfirmation('');
      setPageState('success');
    } catch {
      setError('حدث خطأ غير متوقع. تأكد من اتصالك بالإنترنت وحاول مرة أخرى.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="grid min-h-screen place-items-center bg-[var(--app-bg)] p-4 sm:p-6">
      <div className="w-full max-w-lg">
        <div className="mb-6 flex justify-center">
          <AppLogo />
        </div>
        <section className="card overflow-hidden">
          <div className="bg-[var(--brand-gradient)] px-6 py-7 text-white sm:px-8">
            <span className="mb-4 grid size-12 place-items-center rounded-2xl bg-white/12">
              <KeyRound className="size-6" aria-hidden="true" />
            </span>
            <h1 className="text-2xl font-black">تفعيل حساب الموظف</h1>
            <p className="mt-2 text-sm leading-7 text-blue-100">أنشئ كلمة مرور جديدة لحسابك، ثم استخدمها في تطبيق جمعية خواطر أحلى شباب.</p>
          </div>

          <div className="p-6 sm:p-8">
            {pageState === 'checking' ? (
              <div className="py-8 text-center" aria-live="polite">
                <span className="mx-auto block size-9 animate-spin rounded-full border-4 border-[var(--brand-primary-soft)] border-t-[var(--brand-primary)]" />
                <p className="mt-4 text-sm font-bold text-[var(--text-muted)]">جارٍ التحقق من رابط التفعيل…</p>
              </div>
            ) : null}

            {pageState === 'invalid' ? (
              <div className="py-4 text-center" role="alert">
                <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--danger-soft)] text-[var(--danger)]">
                  <KeyRound className="size-7" aria-hidden="true" />
                </span>
                <h2 className="mt-4 text-xl font-black">الرابط غير صالح أو انتهت مدته</h2>
                <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">
                  هذا الرابط يُستخدم مرة واحدة وقد انتهت صلاحيته. اكتب بريدك لإرسال رابط جديد، ولا تشارك الرابط مع أي شخص.
                </p>
                {resendSent ? (
                  <div className="mt-5 rounded-2xl bg-[var(--success-soft)] p-4 text-sm font-bold leading-7 text-[var(--success)]" aria-live="polite">
                    إذا كان البريد مسجلًا فسيصلك رابط جديد. افتح أحدث رسالة فقط، واستخدم الرابط مرة واحدة.
                  </div>
                ) : (
                  <form className="mt-5 space-y-3 text-start" onSubmit={resendRecoveryLink}>
                    <label className="block">
                      <span className="mb-1.5 block text-sm font-bold">البريد الإلكتروني</span>
                      <span className="relative block">
                        <input
                          className="input !ps-12"
                          type="email"
                          value={recoveryEmail}
                          onChange={(event) => setRecoveryEmail(event.target.value)}
                          autoComplete="email"
                          required
                        />
                        <Mail className="pointer-events-none absolute start-4 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
                      </span>
                    </label>
                    {resendError ? (
                      <p className="rounded-xl bg-[var(--danger-soft)] p-3 text-sm font-bold text-[var(--danger)]" role="alert">
                        {resendError}
                      </p>
                    ) : null}
                    <button className="btn-primary w-full !py-3" type="submit" disabled={resending}>
                      {resending ? 'جارٍ إرسال الرابط…' : 'إرسال رابط جديد'}
                    </button>
                  </form>
                )}
                <button className="mt-4 text-sm font-bold text-[var(--brand-primary)] hover:underline" type="button" onClick={() => navigate('/')}>
                  العودة إلى تسجيل الدخول
                </button>
              </div>
            ) : null}

            {pageState === 'ready' ? (
              <form className="space-y-4" onSubmit={submit}>
                <div className="mb-5 flex items-start gap-3 rounded-2xl bg-[var(--brand-primary-soft)] p-4 text-sm text-[var(--brand-primary)]">
                  <ShieldCheck className="mt-0.5 size-5 shrink-0" />
                  <p className="leading-7 font-bold">اختر كلمة مرور قوية لا تستخدمها في حساب آخر.</p>
                </div>
                <label className="block">
                  <span className="mb-1.5 block text-sm font-bold">كلمة المرور الجديدة</span>
                  <span className="relative block">
                    <input
                      className="input !ps-12"
                      type={showPassword ? 'text' : 'password'}
                      value={password}
                      onChange={(event) => setPassword(event.target.value)}
                      autoComplete="new-password"
                      minLength={8}
                      required
                    />
                    <button
                      type="button"
                      className="absolute start-2 top-1/2 grid size-9 -translate-y-1/2 place-items-center rounded-lg text-[var(--text-muted)] hover:bg-[var(--surface-muted)]"
                      aria-label={showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'}
                      onClick={() => setShowPassword((value) => !value)}
                    >
                      {showPassword ? <EyeOff className="size-4" aria-hidden="true" /> : <Eye className="size-4" aria-hidden="true" />}
                    </button>
                  </span>
                </label>
                <label className="block">
                  <span className="mb-1.5 block text-sm font-bold">تأكيد كلمة المرور</span>
                  <input
                    className="input"
                    type={showPassword ? 'text' : 'password'}
                    value={confirmation}
                    onChange={(event) => setConfirmation(event.target.value)}
                    autoComplete="new-password"
                    minLength={8}
                    required
                  />
                </label>
                {error ? (
                  <p className="rounded-xl bg-[var(--danger-soft)] p-3 text-sm font-bold text-[var(--danger)]" role="alert">
                    {error}
                  </p>
                ) : null}
                <button className="btn-primary w-full !py-3.5" type="submit" disabled={submitting}>
                  {submitting ? 'جارٍ الحفظ…' : 'تعيين كلمة المرور وتفعيل الحساب'}
                </button>
              </form>
            ) : null}

            {pageState === 'success' ? (
              <div className="py-4 text-center">
                <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--success-soft)] text-[var(--success)]">
                  <CheckCircle2 className="size-8" aria-hidden="true" />
                </span>
                <h2 className="mt-4 text-xl font-black">تم تفعيل الحساب بنجاح</h2>
                <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">افتح تطبيق أحلى شباب وسجّل الدخول بالبريد أو رقم الهاتف أو كود الموظف وكلمة المرور الجديدة.</p>
                <button className="btn-primary mx-auto mt-5 !py-3 px-8" type="button" onClick={() => navigate('/')}>
                  تسجيل الدخول من المتصفح
                </button>
              </div>
            ) : null}
          </div>
        </section>
      </div>
    </main>
  );
}
