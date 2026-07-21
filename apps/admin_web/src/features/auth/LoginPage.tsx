import { zodResolver } from '@hookform/resolvers/zod';
import { CheckCircle2, Eye, EyeOff, Fingerprint, LockKeyhole, ShieldCheck, Workflow } from 'lucide-react';
import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { AppLogo } from '../../ui/AppLogo';
import { env, hasSupabaseConfig } from '../../core/env';
import { useAuth } from './AuthProvider';

const schema = z.object({
  identifier: z.string().trim().min(2, 'أدخل البريد أو الهاتف أو كود الموظف.'),
  password: z.string().min(8, 'كلمة المرور لا تقل عن 8 أحرف.'),
});
type FormData = z.infer<typeof schema>;

export function LoginPage() {
  const auth = useAuth();
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  const [mode, setMode] = useState<'signin' | 'reset'>('signin');
  const [resetEmail, setResetEmail] = useState('');
  const [resetSent, setResetSent] = useState(false);
  const [resetError, setResetError] = useState<string | null>(null);
  const [resetBusy, setResetBusy] = useState(false);
  const form = useForm<FormData>({ resolver: zodResolver(schema) });

  const onSubmit = form.handleSubmit(async (values) => {
    try {
      setSubmitError(null);
      await auth.signIn(values.identifier, values.password);
    } catch (error) {
      setSubmitError(error instanceof Error ? error.message : 'تعذر تسجيل الدخول.');
    }
  });

  const onResetSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setResetError(null);
    const email = resetEmail.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      setResetError('أدخل بريدًا إلكترونيًا صحيحًا.');
      return;
    }
    setResetBusy(true);
    try {
      await auth.requestPasswordReset(email);
      setResetSent(true);
    } catch (error) {
      setResetError(error instanceof Error ? error.message : 'تعذر إرسال رابط الاستعادة.');
    } finally {
      setResetBusy(false);
    }
  };

  const features = [
    { icon: ShieldCheck, title: 'صلاحيات دقيقة', body: 'كل مستخدم يرى ما تسمح به وظيفته ونطاقه فقط.' },
    { icon: Fingerprint, title: 'حضور موثوق', body: 'Passkey وموقع وتدقيق خادمي دون تخزين البصمة.' },
    { icon: Workflow, title: 'إجراءات مترابطة', body: 'طلبات وقرارات وتقييمات من مصدر حقيقة واحد.' },
  ];

  return (
    <main className="login-layout">
      <section className="login-brand-panel">
        <div className="relative z-10"><AppLogo inverse /></div>
        <div className="relative z-10 max-w-2xl">
          <p className="mb-3 text-sm font-black text-[color-mix(in_srgb,var(--brand-accent),white_40%)]">منصة الإدارة والتشغيل المؤسسي</p>
          <h1 className="text-4xl font-black leading-[1.35] xl:text-5xl">قرارات أوضح، متابعة أسرع، وتجربة موحدة لكل فريق أحلى شباب.</h1>
          <p className="mt-5 max-w-xl text-sm leading-8 text-[color-mix(in_srgb,var(--brand-accent),white_55%)]">منصة عربية آمنة تجمع الموارد البشرية والحضور والأداء والقرارات والتشغيل في تجربة واحدة.</p>
          <div className="mt-8 grid gap-4 xl:grid-cols-3">
            {features.map(({ icon: Icon, title, body }) => <article key={title} className="rounded-2xl border border-white/15 bg-white/[0.08] p-4 backdrop-blur"><span className="login-feature-icon"><Icon className="size-4" /></span><h2 className="mt-3 text-sm font-black">{title}</h2><p className="mt-1 text-xs leading-6 text-[color-mix(in_srgb,var(--brand-accent),white_55%)]">{body}</p></article>)}
          </div>
        </div>
        <div className="relative z-10 flex flex-wrap items-center gap-5 text-xs text-[color-mix(in_srgb,var(--brand-accent),white_55%)]">
          <span className="login-feature"><CheckCircle2 className="size-4" />RTL كامل</span>
          <span className="login-feature"><CheckCircle2 className="size-4" />تدقيق ومراجعة</span>
          <span className="login-feature"><CheckCircle2 className="size-4" />وصول حسب الدور</span>
        </div>
      </section>

      <section className="login-form-panel">
        <div className="login-card">
          <div className="mb-7 lg:hidden"><AppLogo /></div>
          <div className="card p-6 sm:p-8">
            <div className="mb-7">
              <div className="mb-4 grid size-12 place-items-center rounded-2xl bg-[var(--brand-primary-soft)] text-[var(--brand-primary)]"><LockKeyhole className="size-5" /></div>
              <p className="text-xs font-black text-[var(--brand-primary)]">بوابة آمنة</p>
              <h2 className="mt-1 text-2xl font-black">{mode === 'reset' ? 'استعادة كلمة المرور' : 'مرحبًا بعودتك'}</h2>
              <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">{mode === 'reset' ? 'أدخل بريدك الإلكتروني وسنرسل لك رابطًا لتعيين كلمة مرور جديدة.' : 'سجل الدخول بحساب المؤسسة، وسيحدد الخادم مساحة العمل المناسبة لصلاحياتك.'}</p>
            </div>

            {auth.error || submitError ? <div role="alert" className="mb-4 rounded-xl border border-[var(--danger)]/30 bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{submitError ?? auth.error}</div> : null}

            {mode === 'reset' ? (
              resetSent ? (
                <div className="rounded-xl border border-[var(--success)] bg-[var(--success-soft)] p-4 text-sm leading-7 text-[var(--success)]">
                  <div className="flex items-center gap-2 font-black"><CheckCircle2 className="size-5" />تم إرسال الرابط</div>
                  <p className="mt-2">إن كان البريد مسجلًا لدينا فستصلك رسالة تتضمن رابط تعيين كلمة مرور جديدة. تحقق من صندوق الوارد وبريد المهملات.</p>
                  <button type="button" className="btn-secondary mt-4" onClick={() => { setMode('signin'); setResetSent(false); setResetEmail(''); }}>العودة لتسجيل الدخول</button>
                </div>
              ) : (
                <form className="space-y-4" onSubmit={onResetSubmit}>
                  {resetError ? <div role="alert" className="rounded-xl border border-[var(--danger)]/30 bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{resetError}</div> : null}
                  <label className="block"><span className="mb-1.5 block text-sm font-bold">البريد الإلكتروني</span><input className="input" type="email" autoComplete="email" dir="ltr" placeholder="name@example.com" value={resetEmail} onChange={(e) => setResetEmail(e.target.value)} /></label>
                  <button type="submit" disabled={resetBusy || !hasSupabaseConfig} className="btn-primary w-full !py-3.5">{resetBusy ? 'جارٍ الإرسال…' : 'إرسال رابط الاستعادة'}</button>
                  <button type="button" className="w-full text-center text-sm font-bold text-[var(--brand-primary)] hover:underline" onClick={() => { setMode('signin'); setResetError(null); }}>العودة لتسجيل الدخول</button>
                </form>
              )
            ) : (
              <form className="space-y-4" onSubmit={onSubmit}>
                <label className="block"><span className="mb-1.5 block text-sm font-bold">البريد أو الهاتف أو كود الموظف</span><input className="input" autoComplete="username" dir="ltr" placeholder="EMP-001 أو 010... أو البريد" {...form.register('identifier')} /><span className="mt-1 block min-h-4 text-xs text-[var(--danger)]">{form.formState.errors.identifier?.message}</span></label>
                <label className="block"><span className="mb-1.5 block text-sm font-bold">كلمة المرور</span><span className="relative block"><input type={showPassword ? 'text' : 'password'} className="input !pl-12" autoComplete="current-password" dir="ltr" placeholder="••••••••" {...form.register('password')} /><button type="button" className="absolute left-2 top-1/2 grid size-9 -translate-y-1/2 place-items-center rounded-lg text-[var(--text-muted)] hover:bg-[var(--surface-muted)]" aria-label={showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'} onClick={() => setShowPassword((value) => !value)}>{showPassword ? <EyeOff className="size-4" /> : <Eye className="size-4" />}</button></span><span className="mt-1 block min-h-4 text-xs text-[var(--danger)]">{form.formState.errors.password?.message}</span></label>
                <div className="flex justify-end"><button type="button" className="text-sm font-bold text-[var(--brand-primary)] hover:underline" onClick={() => { setMode('reset'); setSubmitError(null); }}>نسيت كلمة المرور؟</button></div>
                <button type="submit" disabled={form.formState.isSubmitting || !hasSupabaseConfig} aria-describedby={!hasSupabaseConfig ? 'login-config-hint' : undefined} className="btn-primary w-full !py-3.5">{form.formState.isSubmitting ? 'جارٍ التحقق…' : 'تسجيل الدخول بأمان'}</button>
              </form>
            )}

            {!hasSupabaseConfig ? <p id="login-config-hint" className="mt-4 rounded-xl bg-[var(--warning-soft)] p-3 text-xs font-bold text-[var(--warning)]">إعدادات Supabase غير موجودة في هذه البيئة، تسجيل الدخول معطّل حاليًا.</p> : null}

            {env.devMocksEnabled ? <div className="mt-6 border-t border-[var(--border)] pt-5"><p className="mb-3 text-xs text-[var(--text-muted)]">معاينة محلية للواجهات فقط — لا تعمل في Production.</p><div className="grid gap-2 sm:grid-cols-2"><button type="button" className="btn-secondary" onClick={() => auth.signInMock('hr')}>معاينة HR</button><button type="button" className="btn-secondary" onClick={() => auth.signInMock('admin')}>معاينة الإدارة</button></div></div> : null}
          </div>
          <p className="mt-4 text-center text-xs text-[var(--text-muted)]">باستخدام المنصة أنت ملتزم بسياسات الأمن والخصوصية المعتمدة.</p>
        </div>
      </section>
    </main>
  );
}
