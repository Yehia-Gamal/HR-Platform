/**
 * وحدة تهيئة Sentry — رصد الأخطاء وتتبع الأداء.
 *
 * إذا لم يُضبط VITE_SENTRY_DSN تصبح جميع الدوال بلا تأثير (no-op).
 *
 * الخصوصية: يُزال البريد وعنوان IP من كل حدث قبل إرساله (beforeSend).
 */

import * as Sentry from '@sentry/react';

const dsn = (import.meta.env.VITE_SENTRY_DSN as string | undefined)?.trim();
const isProduction = import.meta.env.MODE === 'production';
const RELEASE = (import.meta.env.VITE_APP_VERSION as string | undefined) ?? '0.10.0';

let _initialized = false;
let _enabled = false;

/**
 * تهيئة Sentry — تُستدعى مرة واحدة عند بدء التطبيق.
 * لا تفعل شيئاً إذا لم يُضبط DSN.
 */
export function initSentry(): void {
  if (_initialized || !dsn) {
    _initialized = true;
    return;
  }

  Sentry.init({
    dsn,
    environment: import.meta.env.MODE,
    release: `admin-web@${RELEASE}`,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({ maskAllText: true, blockAllMedia: true }),
    ],
    tracesSampleRate: isProduction ? 0.15 : 1.0,
    replaysSessionSampleRate: 0.05,
    replaysOnErrorSampleRate: 1.0,
    maxBreadcrumbs: 100,

    /** إزالة بيانات التعريف الشخصية قبل الإرسال */
    beforeSend(event) {
      if (event.user) {
        delete event.user.email;
        delete event.user.ip_address;
      }
      if (event.request?.headers) {
        delete event.request.headers['Authorization'];
        delete event.request.headers['authorization'];
        delete event.request.headers['x-supabase-auth'];
      }
      return event;
    },

    beforeBreadcrumb(breadcrumb) {
      if (breadcrumb.category === 'navigation' && breadcrumb.data?.to) {
        breadcrumb.data.to = sanitizeUrl(String(breadcrumb.data.to));
      }
      return breadcrumb;
    },

    ignoreErrors: [
      /chrome-extension:\/\//,
      /moz-extension:\/\//,
      'NetworkError when attempting to fetch resource',
      'Failed to fetch',
      'Load failed',
      'AbortError',
    ],
  });

  _initialized = true;
  _enabled = true;
}

/**
 * تسجيل خطأ في Sentry مع سياق إضافي اختياري.
 */
export function captureError(
  error: unknown,
  context?: Record<string, unknown>,
): void {
  if (!_enabled) return;
  Sentry.captureException(error, context ? { extra: context } : undefined);
}

/**
 * إضافة فتات خبز لتتبع مسار المستخدم قبل وقوع الخطأ.
 */
export function addBreadcrumb(
  category: string,
  message: string,
  data?: Record<string, unknown>,
): void {
  if (!_enabled) return;
  Sentry.addBreadcrumb({ category, message, data, level: 'info' });
}

/**
 * تسجيل رسالة حدث.
 */
export function captureEvent(
  message: string,
  level: 'debug' | 'info' | 'warning' | 'error' = 'info',
  extra?: Record<string, unknown>,
): void {
  if (!_enabled) return;
  Sentry.captureMessage(message, { level, extra });
}

/** تعيين سياق المستخدم */
export function setUserContext(userId: string, role?: string): void {
  if (!_enabled) return;
  Sentry.setUser({ id: userId, role });
}

/** إزالة سياق المستخدم */
export function clearUserContext(): void {
  if (!_enabled) return;
  Sentry.setUser(null);
}

/** ربط TanStack Query بـ Sentry breadcrumbs */
export function attachQueryObservability(queryClient: {
  getQueryCache(): { config: { onError?: (err: Error, q: unknown) => void } };
  getMutationCache(): { config: { onError?: (err: Error, v: unknown, c: unknown, m: unknown) => void } };
}): void {
  if (!_enabled) return;

  queryClient.getQueryCache().config.onError = (error, query) => {
    const q = query as { queryHash?: string; queryKey?: unknown[] };
    addBreadcrumb('query.error', `Query failed: ${q.queryHash ?? 'unknown'}`, {
      queryKey: JSON.stringify(q.queryKey ?? []),
      errorMessage: error instanceof Error ? error.message : String(error),
    });
    const status = (error as { status?: number })?.status ?? 0;
    if (![401, 403, 404, 422].includes(status)) {
      captureError(error, { queryKey: q.queryKey });
    }
  };

  queryClient.getMutationCache().config.onError = (error, variables, _context, mutation) => {
    const m = mutation as { options?: { mutationKey?: unknown[] } };
    addBreadcrumb('mutation.error', `Mutation failed: ${String(m.options?.mutationKey?.[0] ?? 'unknown')}`, {
      errorMessage: error instanceof Error ? error.message : String(error),
      variables: sanitizeVariables(variables),
    });
    captureError(error, { mutationKey: m.options?.mutationKey });
  };
}

/** Web Vitals monitoring */
export async function initWebVitals(): Promise<void> {
  if (!_enabled || typeof window === 'undefined') return;
  try {
    const { onCLS, onINP, onLCP, onTTFB } = await import('web-vitals');
    const report = (metric: { name: string; value: number; delta: number }) => {
      const thresholds: Record<string, number> = { CLS: 0.25, FID: 300, INP: 500, LCP: 4000, TTFB: 1800 };
      const isPoor = metric.value > (thresholds[metric.name] ?? Infinity);
      addBreadcrumb('web-vital', `${metric.name}: ${metric.value.toFixed(2)}`, {
        name: metric.name,
        value: metric.value,
        rating: isPoor ? 'poor' : 'ok',
      });
      if (isPoor) {
        captureEvent(`Poor ${metric.name}: ${metric.value.toFixed(2)}`, 'warning', {
          metric: metric.name,
          value: metric.value,
          delta: metric.delta,
          url: window.location.pathname,
        });
      }
    };
    onCLS(report);
    onINP(report);
    onLCP(report);
    onTTFB(report);
  } catch {
    // web-vitals not installed — skip silently
  }
}

// ─── Utilities ───────────────────────────────────────────────────────────────

function sanitizeVariables(vars: unknown): unknown {
  if (vars === null || vars === undefined || typeof vars !== 'object') return vars;
  try {
    const clone = JSON.parse(JSON.stringify(vars)) as unknown;
    // مفاتيح حساسة (أسرار) + مفاتيح PII (أسماء/هواتف/بريد/هوية) — تُنقّح على كل
    // مستويات التداخل، لأن طفرات الموظفين تمرّر PII داخل كائن changes متداخل.
    const redactKeys = [
      'password', 'token', 'secret', 'key', 'authorization', 'credential',
      'name', 'email', 'phone', 'national', 'iban', 'address',
    ];
    const scrub = (value: unknown): unknown => {
      if (Array.isArray(value)) return value.map(scrub);
      if (value !== null && typeof value === 'object') {
        const obj = value as Record<string, unknown>;
        for (const key of Object.keys(obj)) {
          if (redactKeys.some(s => key.toLowerCase().includes(s))) {
            obj[key] = '[REDACTED]';
          } else {
            obj[key] = scrub(obj[key]);
          }
        }
        return obj;
      }
      return value;
    };
    return scrub(clone);
  } catch {
    return '[unserializable]';
  }
}

function sanitizeUrl(url: string): string {
  try {
    const u = new URL(url, window.location.origin);
    const sensitive = ['token', 'code', 'state', 'session', 'password', 'secret'];
    sensitive.forEach(key => u.searchParams.delete(key));
    return u.pathname + u.search;
  } catch {
    return url;
  }
}
