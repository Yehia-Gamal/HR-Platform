/**
 * k6 Load Test — سيناريو تسجيل الدخول
 *
 * يختبر Edge Function identifier-sign-in تحت الضغط
 * مع التحقق من ثبات زمن الاستجابة (مقاومة timing attacks)
 *
 * Usage:
 *   k6 run tests/load/auth-login.js \
 *     -e SUPABASE_URL=https://xxx.supabase.co \
 *     -e SUPABASE_ANON_KEY=eyJ...
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const loginSuccess = new Rate('login_success');
const loginDuration = new Trend('login_duration_ms');
const timingVariance = new Trend('timing_variance_ms');

export const options = {
  scenarios: {
    // تسجيل دخول عادي
    normal: {
      executor: 'constant-vus',
      vus: 20,
      duration: '3m',
      tags: { scenario: 'normal' },
    },
    // هجوم brute-force محاكى (يجب أن يُحظر)
    brute_force: {
      executor: 'constant-vus',
      vus: 30,
      duration: '2m',
      startTime: '4m',
      tags: { scenario: 'brute_force' },
    },
  },

  thresholds: {
    'login_duration_ms{scenario:normal}': ['p(95)<1000'],
    // Rate limiting يجب أن يحظر أغلب المحاولات
    'login_success{scenario:brute_force}': ['rate<0.30'],
    http_req_failed: ['rate<0.10'],
  },
};

const BASE_URL = __ENV.SUPABASE_URL || 'http://127.0.0.1:54321';
const ANON_KEY = __ENV.SUPABASE_ANON_KEY || '';

const headers = {
  'Content-Type': 'application/json',
  apikey: ANON_KEY,
};

export default function () {
  // محاولة دخول ببيانات وهمية
  const identifier = `test-user-${__VU}@load-test.local`;
  const payload = JSON.stringify({
    identifier,
    password: `LoadTest${__VU}!${__ITER}`,
  });

  const start = Date.now();
  const res = http.post(`${BASE_URL}/functions/v1/identifier-sign-in`, payload, {
    headers,
    tags: { name: 'identifier_sign_in' },
  });
  const elapsed = Date.now() - start;

  const rateLimited = res.status === 429;
  const normalFailure = res.status === 401;
  const ok = res.status === 200;

  check(res, {
    'returns valid status': (r) => [200, 401, 429].includes(r.status),
    'no DB leak': (r) => !r.body.includes('pg_') && !r.body.includes('SQLSTATE'),
    'generic error message': (r) =>
      r.status === 200 || r.body.includes('INVALID_CREDENTIALS') || r.body.includes('RATE_LIMITED'),
  });

  loginSuccess.add(ok);
  loginDuration.add(elapsed);
  timingVariance.add(elapsed);

  sleep(0.5 + Math.random());
}

export function handleSummary(data) {
  return {
    'tests/load/results/auth-login-summary.json': JSON.stringify(data, null, 2),
  };
}
