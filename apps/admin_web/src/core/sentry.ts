/**
 * وحدة تهيئة Sentry — رصد الأخطاء وتتبع الأداء.
 *
 * إذا لم يُضبط VITE_SENTRY_DSN تصبح جميع الدوال بلا تأثير (no-op)
 * ولا يُحمَّل SDK أصلاً — لتجنب زيادة حجم الحزمة في البيئات المحلية.
 *
 * الخصوصية: يُزال البريد وعنوان IP من كل حدث قبل إرساله (beforeSend).
 */

import type * as SentryTypes from '@sentry/react';

const dsn = (import.meta.env.VITE_SENTRY_DSN as string | undefined)?.trim();
const isProduction = import.meta.env.MODE === 'production';

/** مرجع داخلي لـ SDK بعد التحميل الديناميكي */
let _sentry: typeof SentryTypes | null = null;

// ─── دالة مساعدة: تحميل SDK مرة واحدة ──────────────────────────────────────
let _loadPromise: Promise<typeof SentryTypes> | null = null;

function loadSdk(): Promise<typeof SentryTypes> {
  _loadPromise ??= import('@sentry/react');
  return _loadPromise;
}

// ─── التهيئة ─────────────────────────────────────────────────────────────────

/**
 * تهيئة Sentry — تُستدعى مرة واحدة عند بدء التطبيق.
 * لا تفعل شيئاً إذا لم يُضبط DSN.
 */
export async function initSentry(): Promise<void> {
  if (!dsn) return;

  const Sentry = await loadSdk();

  Sentry.init({
    dsn,
    environment: import.meta.env.MODE,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({ maskAllText: true, blockAllMedia: true }),
    ],
    tracesSampleRate: isProduction ? 0.2 : 1.0,
    replaysSessionSampleRate: 0.1,
    replaysOnErrorSampleRate: 1.0,

    /** إزالة بيانات التعريف الشخصية قبل الإرسال */
    beforeSend(event) {
      if (event.user) {
        delete event.user.email;
        delete event.user.ip_address;
      }
      return event;
    },
  });

  _sentry = Sentry;
}

// ─── التقاط الأخطاء ─────────────────────────────────────────────────────────

/**
 * تسجيل خطأ في Sentry مع سياق إضافي اختياري.
 * لا تفعل شيئاً إذا لم يُهيَّأ Sentry.
 */
export function captureError(
  error: unknown,
  context?: Record<string, unknown>,
): void {
  if (!_sentry) return;

  _sentry.captureException(error, context ? { extra: context } : undefined);
}

// ─── فتات الخبز (Breadcrumbs) ────────────────────────────────────────────────

/**
 * إضافة فتات خبز لتتبع مسار المستخدم قبل وقوع الخطأ.
 * لا تفعل شيئاً إذا لم يُهيَّأ Sentry.
 */
export function addBreadcrumb(
  category: string,
  message: string,
  data?: Record<string, unknown>,
): void {
  if (!_sentry) return;

  _sentry.addBreadcrumb({
    category,
    message,
    data,
    level: 'info',
  });
}
