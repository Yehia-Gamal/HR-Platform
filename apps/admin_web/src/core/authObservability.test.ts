import { describe, expect, it, vi, beforeEach } from 'vitest';

// ─── Initiative: Production Observability ───────────────────────────────────
// تتحقّق هذه المجموعة من عقد authObservability: ربط انتقالات حالة المصادقة بـ
// Sentry (سياق المستخدم + breadcrumbs) مع عدم تسريب userId إلى بيانات الـ
// breadcrumb (عقدة الخصوصية PII).

const sentryMock = vi.hoisted(() => ({
  addBreadcrumb: vi.fn(),
  setUserContext: vi.fn(),
  clearUserContext: vi.fn(),
}));

vi.mock('./sentry', () => ({
  addBreadcrumb: sentryMock.addBreadcrumb,
  setUserContext: sentryMock.setUserContext,
  clearUserContext: sentryMock.clearUserContext,
  // بقية دوال sentry غير مستخدمة هنا لكنها تُوفَّر لتجنّب أي استيراد جزئي
  initSentry: vi.fn(),
  captureError: vi.fn(),
  captureEvent: vi.fn(),
  attachQueryObservability: vi.fn(),
  initWebVitals: vi.fn(),
}));

import { attachAuthObservability } from './authObservability';

describe('attachAuthObservability', () => {
  beforeEach(() => {
    sentryMock.addBreadcrumb.mockClear();
    sentryMock.setUserContext.mockClear();
    sentryMock.clearUserContext.mockClear();
  });

  it('يعيد كائناً بمُعالِج onAuthChange', () => {
    const obs = attachAuthObservability();
    expect(typeof obs.onAuthChange).toBe('function');
  });

  it('عند SIGNED_IN يضع سياق المستخدم ويضيف breadcrumb', () => {
    const obs = attachAuthObservability();
    obs.onAuthChange('SIGNED_IN', 'user-123', 'admin');
    expect(sentryMock.setUserContext).toHaveBeenCalledWith('user-123', 'admin');
    expect(sentryMock.addBreadcrumb).toHaveBeenCalledWith('auth', 'Auth event: SIGNED_IN', { event: 'SIGNED_IN' });
  });

  it('عند SIGNED_IN بدون userId لا يضع سياق المستخدم', () => {
    const obs = attachAuthObservability();
    obs.onAuthChange('SIGNED_IN', null);
    expect(sentryMock.setUserContext).not.toHaveBeenCalled();
    expect(sentryMock.addBreadcrumb).toHaveBeenCalledOnce();
  });

  it('عند SIGNED_OUT يمسح سياق المستخدم', () => {
    const obs = attachAuthObservability();
    obs.onAuthChange('SIGNED_OUT', 'user-123');
    expect(sentryMock.clearUserContext).toHaveBeenCalled();
    expect(sentryMock.addBreadcrumb).toHaveBeenCalledWith('auth', 'Auth event: SIGNED_OUT', { event: 'SIGNED_OUT' });
  });

  it('الأحداث الأخرى (TOKEN_REFRESHED) تضيف breadcrumb فقط دون لمس سياق المستخدم', () => {
    const obs = attachAuthObservability();
    obs.onAuthChange('TOKEN_REFRESHED', 'user-123', 'admin');
    expect(sentryMock.setUserContext).not.toHaveBeenCalled();
    expect(sentryMock.clearUserContext).not.toHaveBeenCalled();
    expect(sentryMock.addBreadcrumb).toHaveBeenCalledWith('auth', 'Auth event: TOKEN_REFRESHED', {
      event: 'TOKEN_REFRESHED',
    });
  });

  // عقدة الخصوصية الأساسية: الهوية تُرفق عبر setUserContext فقط، ولا يُPlace
  // userId ضمن بيانات الـ breadcrumb. لو تسرب لانتهكت عقدة PII.
  it('لا يضع userId في بيانات الـ breadcrumb (عقدة PII)', () => {
    const obs = attachAuthObservability();
    obs.onAuthChange('SIGNED_IN', 'user-SECRET', 'admin');
    const dataArg = sentryMock.addBreadcrumb.mock.calls[0][2];
    expect(dataArg).toEqual({ event: 'SIGNED_IN' });
    expect(JSON.stringify(dataArg)).not.toContain('user-SECRET');
  });

  it('مفاتيح بيانات الـ breadcrumb لا تتضمّن حقول هوية حساسة', () => {
    const obs = attachAuthObservability();
    obs.onAuthChange('USER_UPDATED', 'user-SECRET');
    const dataArg = sentryMock.addBreadcrumb.mock.calls[0][2] as Record<string, unknown>;
    const keys = Object.keys(dataArg);
    expect(keys).not.toContain('userId');
    expect(keys).not.toContain('id');
    expect(keys).not.toContain('user');
  });
});
