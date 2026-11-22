import type { AccessContext } from '@ahla/shared-contracts';
import type { Session } from '@supabase/supabase-js';
import { createContext, type PropsWithChildren, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { attachAuthObservability } from '../../core/authObservability';
import { env, hasSupabaseConfig } from '../../core/env';
import { safeErrorMessage } from '../../core/errorMapper';
import { getSupabase } from '../../core/supabase';
import { loadAccessContext } from './accessService';
import { mockContexts, type MockPersona } from './mockContexts';

const authObservability = attachAuthObservability();

type AuthStatus = 'loading' | 'anonymous' | 'authenticated';

interface AuthContextValue {
  status: AuthStatus;
  session: Session | null;
  access: AccessContext | null;
  error: string | null;
  isMock: boolean;
  signIn(identifier: string, password: string): Promise<void>;
  signInMock(persona: MockPersona): void;
  signOut(): Promise<void>;
  refreshAccess(): Promise<void>;
  // إرسال رابط استعادة كلمة المرور عبر البريد؛ تعيين كلمة المرور نفسه يتم في
  // PasswordSetupPage التي يفتحها الرابط.
  requestPasswordReset(email: string): Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

// SEC: rate limit للـ password reset من جهة العميل (نافذة ساعة). ثوابت موديول
// كي لا تظهر كمحددات مفقودة في useCallback، ولأنها لا تتغير عبر العرض.
const PASSWORD_RESET_LIMIT = 3;
const PASSWORD_RESET_WINDOW_MS = 60 * 60 * 1000;
const PASSWORD_RESET_KEY = 'ahla.passwordReset.attempts';

export function AuthProvider({ children, clearSessionData }: PropsWithChildren<{ clearSessionData?: () => void }>) {
  const [status, setStatus] = useState<AuthStatus>('loading');
  const [session, setSession] = useState<Session | null>(null);
  const [access, setAccess] = useState<AccessContext | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isMock, setIsMock] = useState(false);
  const currentUserId = useRef<string | null>(null);
  const sessionVersion = useRef(0);

  const observeSession = useCallback(
    (nextSession: Session | null) => {
      const nextUserId = nextSession?.user.id ?? null;
      if (currentUserId.current !== nextUserId) {
        currentUserId.current = nextUserId;
        sessionVersion.current += 1;
        clearSessionData?.();
        setAccess(null);
        setStatus(nextSession ? 'loading' : 'anonymous');
      }
      setSession(nextSession);
      return sessionVersion.current;
    },
    [clearSessionData],
  );

  const refreshAccess = useCallback(async () => {
    if (isMock) return;
    const version = sessionVersion.current;
    const next = await loadAccessContext();
    if (version === sessionVersion.current) setAccess(next);
  }, [isMock]);

  useEffect(() => {
    // Local preview/E2E must stay deterministic even when a developer has a
    // real Supabase `.env.local`. Otherwise startup waits on getSession() and
    // the login screen intermittently remains behind the loading splash.
    if (env.devMocksEnabled) {
      setStatus('anonymous');
      return;
    }
    if (!hasSupabaseConfig) {
      setError('إعدادات Supabase غير موجودة. أضف ملف .env.local أو فعّل وضع التطوير المحلي.');
      setStatus('anonymous');
      return;
    }

    let active = true;
    let unsubscribe: (() => void) | undefined;

    void getSupabase()
      .then(async (supabase) => {
        // تسجيل المستمع أولاً — يجب أن يكون نشطاً دائماً بغض النظر عن وجود جلسة أولية
        if (!active) return;
        const initialVersion = sessionVersion.current;
        const { data: listener } = supabase.auth.onAuthStateChange((event, nextSession) => {
          if (!active || event === 'INITIAL_SESSION') return;
          authObservability.onAuthChange(event, nextSession?.user.id ?? null);
          const version = observeSession(nextSession);
          if (!nextSession) {
            setAccess(null);
            setStatus('anonymous');
            return;
          }
          // تحديث الصلاحيات عند تجديد التوكن أو تحديث المستخدم أو تسجيل دخول خارجي
          if (event === 'TOKEN_REFRESHED' || event === 'USER_UPDATED' || event === 'SIGNED_IN' || event === 'PASSWORD_RECOVERY') {
            // Start RPCs after the auth callback releases the Supabase session lock.
            window.setTimeout(() => {
              if (!active || version !== sessionVersion.current) return;
              void loadAccessContext()
                .then((nextAccess) => {
                  if (!active || version !== sessionVersion.current) return;
                  setAccess(nextAccess);
                  setStatus('authenticated');
                })
                .catch(() => {
                  if (active && version === sessionVersion.current) {
                    setStatus((current) => (current === 'loading' ? 'anonymous' : current));
                  }
                });
            }, 0);
          }
        });
        unsubscribe = () => listener.subscription.unsubscribe();

        const { data, error: sessionError } = await supabase.auth.getSession();
        if (!active || initialVersion !== sessionVersion.current) return;
        if (sessionError) {
          setError(safeErrorMessage(sessionError));
          setStatus('anonymous');
          return;
        }
        const version = observeSession(data.session);
        if (!data.session) {
          setStatus('anonymous');
          return;
        }
        try {
          const nextAccess = await loadAccessContext();
          if (!active || version !== sessionVersion.current) return;
          setAccess(nextAccess);
          setStatus('authenticated');
        } catch (accessError) {
          if (!active || version !== sessionVersion.current) return;
          setError(safeErrorMessage(accessError));
          setStatus('anonymous');
        }
      })
      .catch((loadError: unknown) => {
        if (!active) return;
        setError(safeErrorMessage(loadError));
        setStatus('anonymous');
      });

    return () => {
      active = false;
      unsubscribe?.();
    };
  }, [observeSession]);

  const signIn = useCallback(
    async (identifier: string, password: string) => {
      if (!hasSupabaseConfig) throw new Error('Supabase غير مهيأ.');
      const initialVersion = sessionVersion.current;
      setError(null);
      const supabase = await getSupabase();
      const { data, error: invokeError } = await supabase.functions.invoke('identifier-sign-in', {
        body: { identifier: identifier.trim(), password },
      });
      if (initialVersion !== sessionVersion.current) return;
      const payload = data as {
        access_token?: string;
        refresh_token?: string;
        error?: string;
      } | null;
      if (invokeError || !payload?.access_token || !payload.refresh_token) {
        // FunctionsHttpError: data يكون null — نستخرج كود الخطأ من جسم الاستجابة
        let errorCode = payload?.error;
        if (!errorCode && invokeError) {
          const resp = (invokeError as Record<string, unknown>).context;
          if (resp instanceof Response) {
            const body = (await resp.json().catch(() => null)) as { error?: string } | null;
            errorCode = body?.error;
          }
        }
        if (initialVersion !== sessionVersion.current) return;
        const message =
          errorCode === 'TOO_MANY_ATTEMPTS'
            ? 'محاولات كثيرة. انتظر قليلًا ثم حاول مرة أخرى.'
            : errorCode === 'SERVER_CONFIGURATION'
              ? 'الخدمة غير مهيأة. تواصل مع الدعم.'
              : 'بيانات الدخول غير صحيحة أو الحساب غير متاح.';
        setError(message);
        setStatus('anonymous');
        throw new Error(message);
      }
      const { data: sessionData, error: sessionError } = await supabase.auth.setSession({
        access_token: payload.access_token,
        refresh_token: payload.refresh_token,
      });
      if (sessionError || !sessionData.session) {
        const message = 'تعذر إنشاء جلسة آمنة. حاول مرة أخرى.';
        setError(message);
        setStatus('anonymous');
        throw new Error(message);
      }
      const version = observeSession(sessionData.session);
      try {
        const nextAccess = await loadAccessContext();
        if (version !== sessionVersion.current) return;
        setAccess(nextAccess);
        setStatus('authenticated');
      } catch {
        if (version !== sessionVersion.current) return;
        await supabase.auth.signOut({ scope: 'local' });
        if (version !== sessionVersion.current && currentUserId.current !== null) return;
        observeSession(null);
        setAccess(null);
        const message = 'تم تسجيل الدخول، لكن تعذر تحميل صلاحيات الحساب. حاول مرة أخرى أو تواصل مع الدعم.';
        setError(message);
        setStatus('anonymous');
        throw new Error(message);
      }
    },
    [observeSession],
  );

  // SEC: rate limit للـ password reset من جهة العميل — نتتبع الطلبات في
  // localStorage (نافذة ساعة). الحماية الحقيقية يجب أن تكون في الخادم/Supabase،
  // لكن هذا يمنع spam بسيط من نفس المتصفح. Obfuscation: نُرجع دائماً نفس
  // الرسالة العامة حتى لا نكشف إن كان البريد مسجلاً. الثوابت في نطاق الموديول.

  const requestPasswordReset = useCallback(async (email: string) => {
    if (!hasSupabaseConfig) throw new Error('Supabase غير مهيأ.');
    const normalizedEmail = email.trim().toLowerCase();
    const now = Date.now();

    // ─── Rate limit (client-side best-effort) ───
    const attempts: number[] = (() => {
      try {
        const raw = typeof window !== 'undefined' ? window.localStorage.getItem(PASSWORD_RESET_KEY) : null;
        const parsed = raw ? (JSON.parse(raw) as number[]) : [];
        return parsed.filter((ts) => typeof ts === 'number' && now - ts < PASSWORD_RESET_WINDOW_MS);
      } catch {
        return [];
      }
    })();
    if (attempts.length >= PASSWORD_RESET_LIMIT) {
      throw new Error('عدد كبير من المحاولات. انتظر ساعة ثم أعد المحاولة.');
    }

    const supabase = await getSupabase();
    const redirectTo = typeof window !== 'undefined' ? `${window.location.origin}/auth/setup-password` : undefined;
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(normalizedEmail, { redirectTo });

    // سجّل المحاولة بعد الوصول إلى الخادم — يمنع enumeration السريع.
    attempts.push(now);
    try {
      if (typeof window !== 'undefined') window.localStorage.setItem(PASSWORD_RESET_KEY, JSON.stringify(attempts));
    } catch {
      /* best-effort */
    }

    // SEC: لا نكشف ما إذا كان البريد موجوداً — نفس رسالة عامة دائماً.
    if (resetError && import.meta.env.DEV) {
      console.warn('[auth] password reset error (hidden from user):', resetError.message);
    }
  }, []);

  const signInMock = useCallback(
    (persona: MockPersona) => {
      clearSessionData?.();
      if (!env.devMocksEnabled) return;
      setIsMock(true);
      setSession(null);
      setAccess(mockContexts[persona]);
      setError(null);
      setStatus('authenticated');
    },
    [clearSessionData],
  );

  const signOut = useCallback(async () => {
    const version = sessionVersion.current;
    if (!isMock && hasSupabaseConfig) {
      const supabase = await getSupabase();
      await supabase.auth.signOut();
    }
    if (version !== sessionVersion.current && currentUserId.current !== null) return;
    if (isMock) clearSessionData?.();
    setIsMock(false);
    observeSession(null);
    setAccess(null);
    setStatus('anonymous');
  }, [clearSessionData, isMock, observeSession]);

  const value = useMemo<AuthContextValue>(
    () => ({
      status,
      session,
      access,
      error,
      isMock,
      signIn,
      signInMock,
      signOut,
      refreshAccess,
      requestPasswordReset,
    }),
    [status, session, access, error, isMock, signIn, signInMock, signOut, refreshAccess, requestPasswordReset],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error('useAuth must be used inside AuthProvider');
  return value;
}
