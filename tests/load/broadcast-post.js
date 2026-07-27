/**
 * k6 Load Test — سيناريو منشور للجميع (Broadcast Post)
 *
 * يحاكي نشر إعلان لجميع الموظفين + قراءة متزامنة من عدة مستخدمين.
 * يفحص: زمن النشر، زمن القراءة، تحميل الإشعارات، تسريب DB.
 *
 * Usage:
 *   k6 run tests/load/broadcast-post.js \
 *     --env BASE_URL=https://ujzzvqsodyhnnnpkoaml.supabase.co \
 *     --env ANON_KEY=<anon-key> \
 *     --env ADMIN_TOKEN=<admin-jwt> \
 *     --env READER_TOKEN=<employee-jwt>
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const publishLatency = new Trend('publish_latency', true);
const feedLatency = new Trend('feed_latency', true);
const notificationLatency = new Trend('notification_latency', true);
const publishErrors = new Counter('publish_errors');

export const options = {
  scenarios: {
    // السيناريو ١: الأدمن ينشر إعلانات متتالية
    admin_publish: {
      executor: 'constant-arrival-rate',
      rate: 2,              // منشوران في الدقيقة
      timeUnit: '1m',
      duration: '3m',
      preAllocatedVUs: 3,
      maxVUs: 5,
      exec: 'publishScenario',
    },

    // السيناريو ٢: موظفون يقرأون الـ feed بشكل متزامن
    employees_read: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 30 },
        { duration: '2m',  target: 50 },  // ذروة — كل الموظفين يفتحون الإعلانات
        { duration: '30s', target: 0 },
      ],
      exec: 'readFeedScenario',
    },

    // السيناريو ٣: تحميل الإشعارات المرتبط بالنشر
    notification_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      startTime: '30s',
      stages: [
        { duration: '20s', target: 40 },
        { duration: '2m',  target: 40 },
        { duration: '20s', target: 0 },
      ],
      exec: 'notificationScenario',
    },
  },

  thresholds: {
    publish_latency: ['p(95)<3000'],
    feed_latency: ['p(95)<1500'],
    notification_latency: ['p(95)<2000'],
    http_req_failed: ['rate<0.05'],
    publish_errors: ['count<3'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:54321';
const ANON_KEY = __ENV.ANON_KEY || '';
const ADMIN_TOKEN = __ENV.ADMIN_TOKEN || '';
const READER_TOKEN = __ENV.READER_TOKEN || '';

function adminHeaders() {
  return {
    'Content-Type': 'application/json',
    apikey: ANON_KEY,
    Authorization: `Bearer ${ADMIN_TOKEN}`,
  };
}

function readerHeaders() {
  return {
    'Content-Type': 'application/json',
    apikey: ANON_KEY,
    Authorization: `Bearer ${READER_TOKEN}`,
  };
}

function rpc(name, payload, hdrs) {
  return http.post(
    `${BASE_URL}/rest/v1/rpc/${name}`,
    JSON.stringify(payload),
    { headers: hdrs, tags: { name } }
  );
}

const POST_TYPES = ['announcement', 'decision', 'alert', 'attendance_notice'];

/**
 * سيناريو النشر — أدمن ينشر إعلان لجميع الموظفين
 */
export function publishScenario() {
  const start = Date.now();
  const postType = POST_TYPES[Math.floor(Math.random() * POST_TYPES.length)];

  const res = rpc('create_official_post', {
    p_type: postType,
    p_title: `إعلان اختبار حمل — ${postType} — ${__VU}`,
    p_body: 'هذا منشور اختبار حمل. يُحذف بعد الاختبار. '.repeat(5),
    p_requires_acknowledgement: postType === 'decision',
  }, adminHeaders());

  publishLatency.add(Date.now() - start);

  const ok = check(res, {
    'نشر: status 200 أو 201': (r) => r.status === 200 || r.status === 201,
    'نشر: لا تسريب DB': (r) =>
      !r.body.includes('pg_') && !r.body.includes('SQLSTATE'),
    'نشر: لا أسرار مكشوفة': (r) =>
      !r.body.includes('service_role') && !r.body.includes('secret'),
  });

  if (!ok) publishErrors.add(1);

  sleep(2 + Math.random() * 3);
}

/**
 * سيناريو القراءة — موظفون يفتحون صفحة الإعلانات
 */
export function readFeedScenario() {
  const start = Date.now();

  const res = rpc('get_official_feed', {
    p_page: 1,
    p_per_page: 20,
  }, readerHeaders());

  feedLatency.add(Date.now() - start);

  check(res, {
    'قراءة feed: status 200': (r) => r.status === 200,
    'قراءة feed: لا تسريب بيانات حساسة': (r) =>
      !r.body.includes('service_role') && !r.body.includes('pg_catalog'),
    'قراءة feed: يحتوي بيانات': (r) => {
      try { return Array.isArray(JSON.parse(r.body)) || typeof JSON.parse(r.body) === 'object'; }
      catch { return false; }
    },
  });

  // محاكاة تصفح — بعض الموظفين يقرأون الصفحة الثانية
  if (Math.random() < 0.3) {
    rpc('get_official_feed', { p_page: 2, p_per_page: 20 }, readerHeaders());
  }

  sleep(3 + Math.random() * 7);
}

/**
 * سيناريو الإشعارات — تحميل إشعارات مرتبط بالمنشورات
 */
export function notificationScenario() {
  const start = Date.now();

  const res = rpc('get_my_notifications', {}, readerHeaders());

  notificationLatency.add(Date.now() - start);

  check(res, {
    'إشعارات: status 200': (r) => r.status === 200,
    'إشعارات: لا تسريب DB': (r) =>
      !r.body.includes('SQLSTATE') && !r.body.includes('pg_'),
  });

  sleep(5 + Math.random() * 10);
}
