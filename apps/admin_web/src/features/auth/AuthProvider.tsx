import type { AccessContext } from '@ahla/shared-contracts';
import type { Session } from '@supabase/supabase-js';
import {
  createContext,
  type PropsWithChildren,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react';
import { env, hasSupabaseConfig } from '../../core/env';
import { safeErrorMessage } from '../../core/errorMapper';
import { getSupabase } from '../../core/supabase';
import { loadAccessContext } from './accessService';
import { mockContexts, type MockPersona } from './mockContexts';

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

export function AuthProvider({ children }: PropsWithChildren) {
  const [status, setStatus] = useState<AuthStatus>('loading');
  const [session, setSession] = useState<Session | null>(null);
  const [access, setAccess] = useState<AccessContext | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isMock, setIsMock] = useState(false);

  const refreshAccess = useCallback(async () => {
    if (isMock) return;
    const next = await loadAccessContext();
    setAccess(next);
  }, [isMock]);

  useEffect(() => {
    if (env.devMocksEnabled && !hasSupabaseConfig) {
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

    void getSupabase().then(async (supabase) => {
      const { data, error: sessionError } = await supabase.auth.getSession();
      if (!active) return;
      if (sessionError) {
        setError(sessionError.message);
        setStatus('anonymous');
        return;
      }
      setSession(data.session);
      if (data.session) {
        try {
          setAccess(await loadAccessContext());
          setStatus('authenticated');
        } catch (accessError) {
          setError(safeErrorMessage(accessError));
          setStatus('anonymous');
        }
      } else {
        setStatus('anonymous');
      }
      if (!active) return;
      // تسجيل المستمع دائمًا — حتى لو بدأ المستخدم بدون جلسة (تسجيل دخول لاحق)
      const { data: listener } = supabase.auth.onAuthStateChange(async (event, nextSession) => {
        setSession(nextSession);
        if (!nextSession) {
          setAccess(null);
          setStatus('anonymous');
          return;
        }
        // تحديث الصلاحيات عند تجديد التوكن أو تحديث المستخدم أو تسجيل دخول خارجي
        if (event === 'TOKEN_REFRESHED' || event === 'USER_UPDATED' || event === 'SIGNED_IN') {
          try {
            const nextAccess = await loadAccessContext();
            setAccess(nextAccess);
            setStatus('authenticated');
          } catch {
            // فشل تحديث الصلاحيات — نبقي على القيم الحالية
          }
        }
      });
      unsubscribe = () => listener.subscription.unsubscribe();
    }).catch((loadError: unknown) => {
      if (!active) return;
      setError(safeErrorMessage(loadError));
      setStatus('anonymous');
    });

    return () => {
      active = false;
      unsubscribe?.();
    };
  }, []);

  const signIn = useCallback(async (identifier: string, password: string) => {
    if (!hasSupabaseConfig) throw new Error('Supabase غير مهيأ.');
    setError(null);
    const supabase = await getSupabase();
    const { data, error: invokeError } = await supabase.functions.invoke('identifier-sign-in', {
      body: { identifier: identifier.trim(), password },
    });
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
          const body = await resp.json().catch(() => null) as { error?: string } | null;
          errorCode = body?.error;
        }
      }
      const message = errorCode === 'TOO_MANY_ATTEMPTS'
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
    try {
      const nextAccess = await loadAccessContext();
      setSession(sessionData.session);
      setAccess(nextAccess);
      setStatus('authenticated');
    } catch {
      await supabase.auth.signOut({ scope: 'local' });
      setSession(null);
      setAccess(null);
      const message = 'تم تسجيل الدخول، لكن تعذر تحميل صلاحيات الحساب. حاول مرة أخرى أو تواصل مع الدعم.';
      setError(message);
      setStatus('anonymous');
      throw new Error(message);
    }
  }, []);

  const requestPasswordReset = useCallback(async (email: string) => {
    if (!hasSupabaseConfig) throw new Error('Supabase غير مهيأ.');
    const supabase = await getSupabase();
    // الرابط يفتح PasswordSetupPage التي تلتقط جلسة الاسترداد وتعيّن كلمة المرور.
    const redirectTo = typeof window !== 'undefined' ? `${window.location.origin}/auth/setup-password` : undefined;
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase(), { redirectTo });
    if (resetError) throw new Error(resetError.message);
  }, []);

  const signInMock = useCallback((persona: MockPersona) => {
    if (!env.devMocksEnabled) return;
    setIsMock(true);
    setSession(null);
    setAccess(mockContexts[persona]);
    setError(null);
    setStatus('authenticated');
  }, []);

  const signOut = useCallback(async () => {
    if (!isMock && hasSupabaseConfig) {
      const supabase = await getSupabase();
      await supabase.auth.signOut();
    }
    setIsMock(false);
    setSession(null);
    setAccess(null);
    setStatus('anonymous');
  }, [isMock]);

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
