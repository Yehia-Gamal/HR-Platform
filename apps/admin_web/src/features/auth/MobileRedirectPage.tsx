import { useEffect, useRef, useState } from 'react';

const APP_SCHEME = 'ahlashabab://action';
// ms to wait before concluding the app didn't open
const FALLBACK_DELAY = 2200;

function buildAppLink(): string {
  // Supabase appends the session tokens to the hash of the redirectTo URL.
  // Pass the full hash through so supabase_flutter can parse the session.
  return APP_SCHEME + (window.location.hash || '');
}

export function MobileRedirectPage() {
  const [status, setStatus] = useState<'redirecting' | 'failed'>('redirecting');
  const appLink = useRef(buildAppLink());

  useEffect(() => {
    // Attempt to open the app via custom URL scheme.
    window.location.href = appLink.current;

    // If the page is still visible after the delay the app didn't open.
    const timer = setTimeout(() => setStatus('failed'), FALLBACK_DELAY);

    // If the user navigates away (app opened), cancel the timer.
    const onBlur = () => clearTimeout(timer);
    window.addEventListener('blur', onBlur);
    return () => {
      clearTimeout(timer);
      window.removeEventListener('blur', onBlur);
    };
  }, []);

  return (
    <main className="grid min-h-screen place-items-center bg-gradient-to-br from-brand/10 to-brand/5 p-6">
      <section className="card max-w-md w-full p-8 text-center space-y-5">
        <div className="grid size-20 place-items-center rounded-3xl bg-brand/10 text-brand mx-auto">
          {status === 'redirecting' ? (
            <svg xmlns="http://www.w3.org/2000/svg" className="size-10 animate-pulse" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M10.5 1.5H8.25A2.25 2.25 0 0 0 6 3.75v16.5a2.25 2.25 0 0 0 2.25 2.25h7.5A2.25 2.25 0 0 0 18 20.25V3.75a2.25 2.25 0 0 0-2.25-2.25H13.5m-3 0V3h3V1.5m-3 0h3m-3 8.25h3m-3 3h3m-3 3h3" />
            </svg>
          ) : (
            <svg xmlns="http://www.w3.org/2000/svg" className="size-10" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" />
            </svg>
          )}
        </div>

        {status === 'redirecting' ? (
          <>
            <h1 className="text-xl font-black">جارٍ فتح تطبيق أحلى شباب…</h1>
            <p className="muted leading-7 text-sm">
              يتم توجيهك تلقائياً لتطبيق الموبايل لإكمال تعيين كلمة المرور.
            </p>
            <div className="flex justify-center">
              <span className="inline-block size-2 rounded-full bg-brand animate-bounce mx-0.5 [animation-delay:0ms]" />
              <span className="inline-block size-2 rounded-full bg-brand animate-bounce mx-0.5 [animation-delay:150ms]" />
              <span className="inline-block size-2 rounded-full bg-brand animate-bounce mx-0.5 [animation-delay:300ms]" />
            </div>
          </>
        ) : (
          <>
            <h1 className="text-xl font-black">لم يفتح التطبيق تلقائياً</h1>
            <p className="muted leading-7 text-sm">
              هذا الرابط مخصص لتطبيق <strong>أحلى شباب</strong> على الجوال. افتح هذا البريد الإلكتروني من هاتفك وتأكد من أن التطبيق مثبت.
            </p>

            <div className="rounded-2xl bg-[var(--surface-muted)] p-4 text-sm text-start space-y-2">
              <p className="font-bold">خطوات بديلة:</p>
              <ol className="muted space-y-1 list-decimal list-inside text-start">
                <li>افتح البريد الإلكتروني على هاتفك.</li>
                <li>اضغط على رابط التفعيل في رسالة الدعوة.</li>
                <li>سيفتح التطبيق مباشرة لتعيين كلمة المرور.</li>
              </ol>
            </div>

            <button
              type="button"
              className="w-full rounded-xl bg-brand px-4 py-3 font-bold text-white text-sm"
              onClick={() => { window.location.href = appLink.current; }}
            >
              حاول فتح التطبيق مجدداً
            </button>
          </>
        )}
      </section>
    </main>
  );
}
