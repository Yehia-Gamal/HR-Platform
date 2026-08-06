import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';

// ─── Initiative: Production Observability ───────────────────────────────────
// تتحقّق هذه المجموعة من وحدة sentry.ts بأكملها:
//  1) سلوك no-op عند غياب VITE_SENTRY_DSN.
//  2) تهيئة صحيحة مع DSN + عقد idempotent.
//  3) عقد الخصوصية (PII scrubbing) في beforeSend / beforeBreadcrumb.
//  4) ربط TanStack Query (breadcrumbs + captureError مع كتم 4xx).
//  5) مراقبة Web Vitals.

const sentryMock = vi.hoisted(() => ({
  init: vi.fn(),
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
  setUser: vi.fn(),
  browserTracingIntegration: vi.fn(() => ({ _name: 'browserTracing' })),
  replayIntegration: vi.fn(() => ({ _name: 'replay' })),
}));

vi.mock('@sentry/react', () => ({
  init: sentryMock.init,
  captureException: sentryMock.captureException,
  addBreadcrumb: sentryMock.addBreadcrumb,
  captureMessage: sentryMock.captureMessage,
  setUser: sentryMock.setUser,
  browserTracingIntegration: sentryMock.browserTracingIntegration,
  replayIntegration: sentryMock.replayIntegration,
}));

// نوفّر mock ثابتاً لـ web-vitals لتفعيل اختبار initWebVitals دون اعتماد على
// توقيت المتصفح. onCLS يستدعي الـ callback بقيمة ضعيفة (CLS=0.5 > 0.25).
const webVitalsMock = vi.hoisted(() => ({
  onCLS: vi.fn((cb: (m: { name: string; value: number; delta: number }) => void) =>
    cb({ name: 'CLS', value: 0.5, delta: 0.5 }),
  ),
  onINP: vi.fn(),
  onLCP: vi.fn(),
  onTTFB: vi.fn(),
}));

vi.mock('web-vitals', () => ({
  onCLS: webVitalsMock.onCLS,
  onINP: webVitalsMock.onINP,
  onLCP: webVitalsMock.onLCP,
  onTTFB: webVitalsMock.onTTFB,
}));

function resetMocks() {
  sentryMock.init.mockClear();
  sentryMock.captureException.mockClear();
  sentryMock.addBreadcrumb.mockClear();
  sentryMock.captureMessage.mockClear();
  sentryMock.setUser.mockClear();
  sentryMock.browserTracingIntegration.mockClear();
  sentryMock.replayIntegration.mockClear();
}

/**
 * تُعيد وحدة sentry مُحمّلة ببيئة محدّدة. تعتمد على vi.resetModules لإعادة
 * تقييم الـ module-level consts (dsn/release/isProduction) بقيم البيئة الجديدة.
 */
async function loadSentry(opts: { dsn?: string; version?: string } = {}) {
  // نمسح أي stubs سابقة أولاً لئلا تتسرّب قيم من اختبار سابق (خصوصاً
  // VITE_APP_VERSION الذي يُقرأ على مستوى الوحدة عند استيرادها من جديد).
  vi.unstubAllEnvs();
  vi.stubEnv('VITE_SENTRY_DSN', opts.dsn ?? '');
  if (opts.version !== undefined) {
    vi.stubEnv('VITE_APP_VERSION', opts.version);
  }
  vi.resetModules();
  return await import('./sentry');
}

afterEach(() => {
  vi.unstubAllEnvs();
});

// ─── بدون DSN: كل الدوال بلا تأثير ─────────────────────────────────────────
describe('sentry بدون VITE_SENTRY_DSN (no-op)', () => {
  let sentry: typeof import('./sentry');

  beforeEach(async () => {
    resetMocks();
    sentry = await loadSentry({ dsn: '' });
    sentry.initSentry();
  });

  it('لا يستدعي Sentry.init', () => {
    expect(sentryMock.init).not.toHaveBeenCalled();
  });

  it('captureError بلا تأثير', () => {
    sentry.captureError(new Error('boom'), { ctx: 1 });
    expect(sentryMock.captureException).not.toHaveBeenCalled();
  });

  it('addBreadcrumb بلا تأثير', () => {
    sentry.addBreadcrumb('ui', 'click', { x: 1 });
    expect(sentryMock.addBreadcrumb).not.toHaveBeenCalled();
  });

  it('captureEvent بلا تأثير', () => {
    sentry.captureEvent('msg', 'warning', { k: 'v' });
    expect(sentryMock.captureMessage).not.toHaveBeenCalled();
  });

  it('setUserContext / clearUserContext بلا تأثير', () => {
    sentry.setUserContext('u1', 'admin');
    sentry.clearUserContext();
    expect(sentryMock.setUser).not.toHaveBeenCalled();
  });

  it('attachQueryObservability بلا تأثير (لا يربط onError)', () => {
    const queryCache = { config: {} };
    const mutationCache = { config: {} };
    const qc = { getQueryCache: () => queryCache, getMutationCache: () => mutationCache };
    sentry.attachQueryObservability(qc as never);
    expect(queryCache.config.onError).toBeUndefined();
    expect(mutationCache.config.onError).toBeUndefined();
  });

  it('initWebVitals بلا تأثير', async () => {
    await sentry.initWebVitals();
    expect(webVitalsMock.onCLS).not.toHaveBeenCalled();
    expect(sentryMock.captureMessage).not.toHaveBeenCalled();
  });
});

// ─── مع DSN: تهيئة وعقد PII ─────────────────────────────────────────────────
describe('sentry مع VITE_SENTRY_DSN', () => {
  let sentry: typeof import('./sentry');

  beforeEach(async () => {
    resetMocks();
    sentry = await loadSentry({ dsn: 'https://abc@example.io/1', version: '1.2.3' });
    sentry.initSentry();
  });

  it('يستدعي Sentry.init مرة واحدة بالإعدادات الصحيحة', () => {
    expect(sentryMock.init).toHaveBeenCalledOnce();
    const config = sentryMock.init.mock.calls[0][0];
    expect(config.dsn).toBe('https://abc@example.io/1');
    expect(config.environment).toBe('test');
    expect(config.release).toBe('admin-web@1.2.3');
    expect(config.tracesSampleRate).toBe(1.0); // غير إنتاجي → 1.0
    expect(config.replaysSessionSampleRate).toBe(0.05);
    expect(config.replaysOnErrorSampleRate).toBe(1.0);
    expect(config.maxBreadcrumbs).toBe(100);
    expect(config.integrations).toHaveLength(2);
    expect(sentryMock.browserTracingIntegration).toHaveBeenCalledOnce();
    expect(sentryMock.replayIntegration).toHaveBeenCalledOnce();
    expect(config.ignoreErrors).toHaveLength(5);
    expect(typeof config.beforeSend).toBe('function');
    expect(typeof config.beforeBreadcrumb).toBe('function');
  });

  it('release يستخدم القيمة الافتراضية 0.10.0 عند غياب VITE_APP_VERSION', async () => {
    const s2 = await loadSentry({ dsn: 'https://abc@example.io/1' });
    s2.initSentry();
    const last = sentryMock.init.mock.calls.at(-1)![0];
    expect(last.release).toBe('admin-web@0.10.0');
  });

  it('initSentry idempotent — لا يستدعي init مرتين', () => {
    sentry.initSentry();
    expect(sentryMock.init).toHaveBeenCalledOnce();
  });

  it('captureError يمرر السياق عبر extra', () => {
    sentry.captureError(new Error('boom'), { foo: 1 });
    expect(sentryMock.captureException).toHaveBeenCalledWith(expect.any(Error), { extra: { foo: 1 } });
  });

  it('captureError بدون سياق يمرر undefined', () => {
    sentry.captureError(new Error('boom'));
    expect(sentryMock.captureException).toHaveBeenCalledWith(expect.any(Error), undefined);
  });

  it('addBreadcrumb يبني الحشوة القياسية (level=info)', () => {
    sentry.addBreadcrumb('ui', 'clicked', { x: 1 });
    expect(sentryMock.addBreadcrumb).toHaveBeenCalledWith({
      category: 'ui',
      message: 'clicked',
      data: { x: 1 },
      level: 'info',
    });
  });

  it('captureEvent يستخدم المستوى الافتراضي info', () => {
    sentry.captureEvent('hello');
    expect(sentryMock.captureMessage).toHaveBeenCalledWith('hello', { level: 'info', extra: undefined });
  });

  it('captureEvent يحترم المستوى والإضافة', () => {
    sentry.captureEvent('warn', 'warning', { k: 'v' });
    expect(sentryMock.captureMessage).toHaveBeenCalledWith('warn', { level: 'warning', extra: { k: 'v' } });
  });

  it('setUserContext يضع id و role', () => {
    sentry.setUserContext('u1', 'admin');
    expect(sentryMock.setUser).toHaveBeenCalledWith({ id: 'u1', role: 'admin' });
  });

  it('clearUserContext يضع null', () => {
    sentry.clearUserContext();
    expect(sentryMock.setUser).toHaveBeenCalledWith(null);
  });

  // ── عقد PII في beforeSend ──────────────────────────────────────────────
  function config() {
    return sentryMock.init.mock.calls[0][0];
  }

  it('beforeSend يزيل email و ip_address من المستخدم ويُبقي id', () => {
    const out = config().beforeSend({ user: { email: 'a@b.com', ip_address: '1.2.3.4', id: 'u1' } });
    expect(out.user.email).toBeUndefined();
    expect(out.user.ip_address).toBeUndefined();
    expect(out.user.id).toBe('u1');
  });

  it('beforeSend يزيل headers المصادقة ويُبقي غيرها', () => {
    const out = config().beforeSend({
      request: {
        headers: {
          Authorization: 'Bearer x',
          authorization: 'y',
          'x-supabase-auth': 'z',
          'content-type': 'application/json',
        },
      },
    });
    expect(out.request.headers.Authorization).toBeUndefined();
    expect(out.request.headers.authorization).toBeUndefined();
    expect(out.request.headers['x-supabase-auth']).toBeUndefined();
    expect(out.request.headers['content-type']).toBe('application/json');
  });

  it('beforeSend ينقّي URL من معاملات حساسة ويُبقي غيرها', () => {
    const out = config().beforeSend({ request: { url: 'https://app.com/x?token=secret&code=abc&state=zz&keep=1' } });
    expect(out.request.url).not.toContain('token');
    expect(out.request.url).not.toContain('code');
    expect(out.request.url).not.toContain('state');
    expect(out.request.url).toContain('keep=1');
  });

  it('beforeSend يحوّل قيم الاستثناءات إلى [ERROR DETAILS REDACTED]', () => {
    const out = config().beforeSend({
      exception: { values: [{ value: 'row-level security violation: select * from employees' }] },
    });
    expect(out.exception.values[0].value).toBe('[ERROR DETAILS REDACTED]');
  });

  it('beforeSend ينقّي رسائل breadcrumbs من JWT/Bearer/البريد', () => {
    const out = config().beforeSend({
      breadcrumbs: [{ message: 'user a@b.com logged in with Bearer eyJabc.def.ghi' }],
    });
    expect(out.breadcrumbs[0].message).not.toContain('a@b.com');
    expect(out.breadcrumbs[0].message).not.toContain('Bearer ');
    expect(out.breadcrumbs[0].message).not.toContain('eyJabc.def.ghi');
  });

  it('beforeSend ينقّي بيانات breadcrumbs (مفاتيح حساسة)', () => {
    const out = config().beforeSend({
      breadcrumbs: [{ data: { password: 'pw', token: 'tk', email: 'a@b.com', keep: 1 } }],
    });
    expect(out.breadcrumbs[0].data.password).toBe('[REDACTED]');
    expect(out.breadcrumbs[0].data.token).toBe('[REDACTED]');
    expect(out.breadcrumbs[0].data.email).toBe('[REDACTED]');
    expect(out.breadcrumbs[0].data.keep).toBe(1);
  });

  it('beforeSend ينقّي البيانات المتداخلة في extra (name/email/phone/iban/...)', () => {
    const out = config().beforeSend({
      extra: {
        user: { name: 'Ahmed', email: 'a@b.com', phone: '0100', national: '123', iban: 'EG00' },
        nested: { token: 'x', reason: 'some reason', safe: { keep: 1 } },
      },
    });
    expect(out.extra.user.name).toBe('[REDACTED]');
    expect(out.extra.user.email).toBe('[REDACTED]');
    expect(out.extra.user.phone).toBe('[REDACTED]');
    expect(out.extra.user.national).toBe('[REDACTED]');
    expect(out.extra.user.iban).toBe('[REDACTED]');
    expect(out.extra.nested.token).toBe('[REDACTED]');
    expect(out.extra.nested.reason).toBe('[REDACTED]');
    expect(out.extra.nested.safe.keep).toBe(1);
  });

  it('beforeSend ينقّي رسائل SQL الداخلية في breadcrumbs', () => {
    const out = config().beforeSend({ breadcrumbs: [{ message: 'duplicate key violates unique constraint' }] });
    expect(out.breadcrumbs[0].message).toBe('[ERROR DETAILS REDACTED]');
  });

  it('beforeSend يتعامل مع بيانات غير قابلة للتسلسل دون رمي', () => {
    const circular: Record<string, unknown> = {};
    circular.self = circular;
    const out = config().beforeSend({ extra: circular });
    expect(out.extra).toBe('[unserializable]');
  });

  // ── beforeBreadcrumb ────────────────────────────────────────────────────
  it('beforeBreadcrumb ينقّي url التنقل من معاملات حساسة', () => {
    const out = config().beforeBreadcrumb({
      category: 'navigation',
      data: { to: 'https://app.com/p?token=secret&state=zz&keep=1' },
    });
    expect(out.data.to).not.toContain('token');
    expect(out.data.to).not.toContain('state');
    expect(out.data.to).toContain('keep=1');
  });

  it('beforeBreadcrumb ينقّي الرسالة والبيانات', () => {
    const out = config().beforeBreadcrumb({ message: 'mail a@b.com', data: { password: 'pw' } });
    expect(out.message).not.toContain('a@b.com');
    expect(out.data.password).toBe('[REDACTED]');
  });

  // ── ربط TanStack Query ─────────────────────────────────────────────────
  function makeQueryClient() {
    const queryCache = { config: {} as { onError?: (e: Error, q: unknown) => void } };
    const mutationCache = { config: {} as { onError?: (e: Error, v: unknown, c: unknown, m: unknown) => void } };
    return {
      getQueryCache: () => queryCache,
      getMutationCache: () => mutationCache,
    };
  }

  it('attachQueryObservability يربط onError للـ query و mutation caches', () => {
    const qc = makeQueryClient();
    sentry.attachQueryObservability(qc as never);
    expect(typeof qc.getQueryCache().config.onError).toBe('function');
    expect(typeof qc.getMutationCache().config.onError).toBe('function');
  });

  it('query error غير 4xx ينشّط breadcrumb + captureError', () => {
    const qc = makeQueryClient();
    sentry.attachQueryObservability(qc as never);
    qc.getQueryCache().config.onError!(new Error('boom'), { queryHash: 'h1', queryKey: ['q'] });
    expect(sentryMock.addBreadcrumb).toHaveBeenCalled();
    expect(sentryMock.captureException).toHaveBeenCalled();
  });

  it.each([401, 403, 404, 422] as const)('query error بحالة %i ينشّط breadcrumb فقط دون captureError', (status) => {
    resetMocks();
    sentry.initSentry(); // إعادة تفعيل _enabled بعد resetMocks (لا يؤثر init إذ idempotent)
    const qc = makeQueryClient();
    sentry.attachQueryObservability(qc as never);
    const err = Object.assign(new Error('client error'), { status });
    qc.getQueryCache().config.onError!(err, { queryHash: 'h', queryKey: ['q'] });
    expect(sentryMock.addBreadcrumb).toHaveBeenCalled();
    expect(sentryMock.captureException).not.toHaveBeenCalled();
  });

  it('mutation error ينشّط breadcrumb + captureError', () => {
    const qc = makeQueryClient();
    sentry.attachQueryObservability(qc as never);
    qc.getMutationCache().config.onError!(new Error('mfail'), null, undefined, {
      options: { mutationKey: ['mut'] },
    });
    expect(sentryMock.addBreadcrumb).toHaveBeenCalled();
    expect(sentryMock.captureException).toHaveBeenCalled();
  });

  it('breadcrumb الـ query error يخفي نوع المتغيرات خلف sanitize', () => {
    const qc = makeQueryClient();
    sentry.attachQueryObservability(qc as never);
    qc.getQueryCache().config.onError!(new Error('boom'), { queryHash: 'h1', queryKey: ['q'] });
    const dataArg = sentryMock.addBreadcrumb.mock.calls[0][2] as Record<string, unknown>;
    expect(dataArg.errorType).toBe('Error');
    expect(dataArg.status).toBe(0);
    expect(JSON.stringify(dataArg)).not.toContain('queryKey');
  });

  // ── Web Vitals ──────────────────────────────────────────────────────────
  it('initWebVitals يلتقط القياسات الضعيفة ويبثّ breadcrumb + captureMessage', async () => {
    await sentry.initWebVitals();
    expect(webVitalsMock.onCLS).toHaveBeenCalledOnce();
    expect(sentryMock.addBreadcrumb).toHaveBeenCalled();
    expect(sentryMock.captureMessage).toHaveBeenCalled();
    const args = sentryMock.captureMessage.mock.calls[0];
    expect(args[0]).toContain('Poor CLS');
    expect(args[1].level).toBe('warning');
  });
});
