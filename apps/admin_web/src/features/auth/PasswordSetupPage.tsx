import { CheckCircle2, Eye, EyeOff, KeyRound, ShieldCheck } from 'lucide-react';
import { type FormEvent, useEffect, useState } from 'react';
import { getSupabase } from '../../core/supabase';
import { AppLogo } from '../../ui/AppLogo';

type RecoveryLocation = Pick<Location, 'pathname' | 'hash'>;
type PageState = 'checking' | 'ready' | 'invalid' | 'success';

export function isPasswordRecoveryLocation(location: RecoveryLocation = window.location): boolean {
  if (location.pathname === '/auth/setup-password') return true;
  const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
  return hash.get('type') === 'recovery';
}

function clearRecoverySecretsFromAddressBar() {
  if (!window.location.hash) return;
  window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}`);
}

export function PasswordSetupPage() {
  const [pageState, setPageState] = useState<PageState>('checking');
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    void getSupabase().then(async (supabase) => {
      const { data, error: sessionError } = await supabase.auth.getSession();
      clearRecoverySecretsFromAddressBar();
      if (!active) return;
      setPageState(sessionError || !data.session ? 'invalid' : 'ready');
    }).catch(() => {
      clearRecoverySecretsFromAddressBar();
      if (active) setPageState('invalid');
    });
    return () => { active = false; };
  }, []);

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
      const { data: userData, error: userError } = await supabase.auth.getUser();
      if (userError || !userData.user) throw new Error('invalid_recovery_session');
      const { error: updateError } = await supabase.auth.updateUser({
        password,
      });
      if (updateError) throw updateError;
      const { data: activation, error: activationError } = await supabase.rpc(
        'activate_employee_after_first_login',
      );
      const activationResult = activation as { activated?: boolean; reason?: string } | null;
      if (
        activationError ||
        (activationResult?.activated !== true && activationResult?.reason !== 'already_active')
      ) {
        throw new Error('employee_activation_failed');
      }
      const { error: metadataError } = await supabase.auth.updateUser({
        data: { ...userData.user.user_metadata, must_change_password: false },
      });
      if (metadataError) throw metadataError;
      await supabase.auth.signOut({ scope: 'global' });
      setPassword('');
      setConfirmation('');
      setPageState('success');
    } catch {
      setError('تعذر حفظ كلمة المرور. اطلب رابط تفعيل جديدًا ثم حاول مرة أخرى.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="grid min-h-screen place-items-center bg-[var(--app-bg)] p-4 sm:p-6">
      <div className="w-full max-w-lg">
        <div className="mb-6 flex justify-center"><AppLogo /></div>
        <section className="card overflow-hidden">
          <div className="bg-[var(--brand-gradient)] px-6 py-7 text-white sm:px-8">
            <span className="mb-4 grid size-12 place-items-center rounded-2xl bg-white/12"><KeyRound className="size-6" /></span>
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
                <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--danger-soft)] text-[var(--danger)]"><KeyRound className="size-7" /></span>
                <h2 className="mt-4 text-xl font-black">الرابط غير صالح أو انتهت مدته</h2>
                <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">اطلب من مسؤول الموارد البشرية إرسال رابط تفعيل جديد. لا تشارك رابط التفعيل مع أي شخص.</p>
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
                    <input className="input !pl-12" type={showPassword ? 'text' : 'password'} value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="new-password" minLength={8} required />
                    <button type="button" className="absolute left-2 top-1/2 grid size-9 -translate-y-1/2 place-items-center rounded-lg text-[var(--text-muted)] hover:bg-[var(--surface-muted)]" aria-label={showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'} onClick={() => setShowPassword((value) => !value)}>{showPassword ? <EyeOff className="size-4" /> : <Eye className="size-4" />}</button>
                  </span>
                </label>
                <label className="block">
                  <span className="mb-1.5 block text-sm font-bold">تأكيد كلمة المرور</span>
                  <input className="input" type={showPassword ? 'text' : 'password'} value={confirmation} onChange={(event) => setConfirmation(event.target.value)} autoComplete="new-password" minLength={8} required />
                </label>
                {error ? <p className="rounded-xl bg-[var(--danger-soft)] p-3 text-sm font-bold text-[var(--danger)]" role="alert">{error}</p> : null}
                <button className="btn-primary w-full !py-3.5" type="submit" disabled={submitting}>{submitting ? 'جارٍ الحفظ…' : 'تعيين كلمة المرور وتفعيل الحساب'}</button>
              </form>
            ) : null}

            {pageState === 'success' ? (
              <div className="py-4 text-center">
                <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--success-soft)] text-[var(--success)]"><CheckCircle2 className="size-8" /></span>
                <h2 className="mt-4 text-xl font-black">تم تفعيل الحساب بنجاح</h2>
                <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">افتح تطبيق أحلى شباب وسجّل الدخول بالبريد أو كود الموظف وكلمة المرور الجديدة.</p>
              </div>
            ) : null}
          </div>
        </section>
      </div>
    </main>
  );
}
