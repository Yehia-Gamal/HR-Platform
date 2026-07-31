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

    /** إزالة بيانات التعريف الشخصية وتفاصيل الأخطاء الداخلية قبل الإرسال */
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
      if (event.request?.url) {
        event.request.url = sanitizeUrl(event.request.url);
      }
      if (event.request?.data) {
        event.request.data = sanitizeTelemetryValue(event.request.data);
      }
      if (event.extra) {
        event.extra = sanitizeTelemetryRecord(event.extra);
      }
      if (event.contexts) {
        event.contexts = sanitizeTelemetryRecord(event.contexts);
      }
      event.exception?.values?.forEach((exception) => {
        if (exception.value) exception.value = '[ERROR DETAILS REDACTED]';
      });
      event.breadcrumbs?.forEach((breadcrumb) => {
        if (breadcrumb.message) breadcrumb.message = sanitizeTelemetryText(breadcrumb.message);
        if (breadcrumb.data) breadcrumb.data = sanitizeTelemetryRecord(breadcrumb.data);
      });
      return event;
    },

    beforeBreadcrumb(breadcrumb) {
      if (breadcrumb.category === 'navigation' && breadcrumb.data?.to) {
        breadcrumb.data.to = sanitizeUrl(String(breadcrumb.data.to));
      }
      if (breadcrumb.message) breadcrumb.message = sanitizeTelemetryText(breadcrumb.message);
      if (breadcrumb.data) breadcrumb.data = sanitizeTelemetryRecord(breadcrumb.data);
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
      errorType: error instanceof Error ? error.name : 'UnknownError',
      status: readErrorStatus(error),
    });
    const status = readErrorStatus(error);
    if (![401, 403, 404, 422].includes(status)) {
      captureError(error, { queryKey: q.queryKey });
    }
  };

  queryClient.getMutationCache().config.onError = (error, variables, _context, mutation) => {
    const m = mutation as { options?: { mutationKey?: unknown[] } };
    addBreadcrumb('mutation.error', `Mutation failed: ${String(m.options?.mutationKey?.[0] ?? 'unknown')}`, {
      errorType: error instanceof Error ? error.name : 'UnknownError',
      status: readErrorStatus(error),
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

function readErrorStatus(error: unknown): number {
  const value = (error as { status?: unknown } | null)?.status;
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function sanitizeTelemetryRecord<T extends Record<string, unknown>>(value: T): T {
  return sanitizeTelemetryValue(value) as T;
}

function sanitizeTelemetryValue(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (typeof value === 'string') return sanitizeTelemetryText(value);
  if (typeof value !== 'object') return value;
  try {
    const clone = JSON.parse(JSON.stringify(value)) as unknown;
    // مفاتيح حساسة (أسرار) + مفاتيح PII (أسماء/هواتف/بريد/هوية) — تُنقّح على كل
    // مستويات التداخل، لأن بيانات الموظفين قد تمر داخل كائنات متداخلة.
    const redactKeys = [
      'password', 'token', 'secret', 'key', 'authorization', 'credential',
      'name', 'email', 'phone', 'national', 'iban', 'address',
      // حقول نصّية حرّة قد تحمل PII (ملاحظات المراجعين، أسباب القرارات...)
      'note', 'comment', 'reason', 'message', 'body', 'text',
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
      return typeof value === 'string' ? sanitizeTelemetryText(value) : value;
    };
    return scrub(clone);
  } catch {
    return '[unserializable]';
  }
}

function sanitizeVariables(vars: unknown): unknown {
  return sanitizeTelemetryValue(vars);
}

function sanitizeTelemetryText(value: string): string {
  if (/sqlstate|postgres|duplicate key|row-level security|violates .+ constraint|\b(select|insert into|update|delete from)\b/i.test(value)) {
    return '[ERROR DETAILS REDACTED]';
  }
  return value
    .replace(/\bBearer\s+\S+/gi, 'Bearer [REDACTED]')
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, '[REDACTED_TOKEN]')
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[REDACTED_EMAIL]')
    .replace(/([?&](?:token|code|state|session|password|secret)=)[^&#\s]+/gi, '$1[REDACTED]');
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
