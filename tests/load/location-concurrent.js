/**
 * k6 Load Test — سيناريو الموقع المتزامن (Concurrent Location Requests)
 *
 * يحاكي طلبات موقع حي متزامنة من عدة مديرين + استجابات من موظفين.
 * يفحص: زمن طلب الموقع، زمن الاستجابة، حمل الدليل، تسريب DB،
 *         duplicate request handling، RLS query load.
 *
 * Usage:
 *   k6 run tests/load/location-concurrent.js \
 *     --env BASE_URL=https://ujzzvqsodyhnnnpkoaml.supabase.co \
 *     --env ANON_KEY=<anon-key> \
 *     --env MANAGER_TOKEN=<manager-jwt> \
 *     --env EXEC_TOKEN=<executive-jwt> \
 *     --env EMPLOYEE_TOKEN=<employee-jwt>
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const directoryLatency = new Trend('directory_latency', true);
const requestLatency = new Trend('location_request_latency', true);
const responseLatency = new Trend('location_response_latency', true);
const overviewLatency = new Trend('exec_overview_latency', true);
const rlsQueryLatency = new Trend('rls_query_latency', true);
const locationErrors = new Counter('location_errors');

export const options = {
  scenarios: {
    // السيناريو ١: مديرون يفتحون دليل الموقع (RLS query load)
    directory_browse: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '20s', target: 15 },
        { duration: '2m',  target: 25 },  // 25 مدير يتصفحون بنفس الوقت
        { duration: '20s', target: 0 },
      ],
      exec: 'directoryScenario',
    },

    // السيناريو ٢: طلبات موقع متزامنة (snapshot)
    concurrent_requests: {
      executor: 'ramping-vus',
      startVUs: 0,
      startTime: '10s',
      stages: [
        { duration: '15s', target: 10 },
        { duration: '2m',  target: 20 },  // 20 طلب موقع متزامن
        { duration: '15s', target: 0 },
      ],
      exec: 'requestScenario',
    },

    // السيناريو ٣: لوحة المتابعة التنفيذية (أثقل RPC)
    executive_overview: {
      executor: 'constant-vus',
      vus: 5,
      duration: '3m',
      exec: 'executiveOverviewScenario',
    },

    // السيناريو ٤: RLS query load — استعلامات متزامنة بأدوار مختلفة
    rls_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      startTime: '30s',
      stages: [
        { duration: '15s', target: 30 },
        { duration: '1m',  target: 30 },
        { duration: '15s', target: 0 },
      ],
      exec: 'rlsQueryScenario',
    },
  },

  thresholds: {
    directory_latency: ['p(95)<2000'],
    location_request_latency: ['p(95)<3000'],
    location_response_latency: ['p(95)<2000'],
    exec_overview_latency: ['p(95)<4000'],
    rls_query_latency: ['p(95)<1500'],
    http_req_failed: ['rate<0.05'],
    location_errors: ['count<5'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:54321';
const ANON_KEY = __ENV.ANON_KEY || '';
const MANAGER_TOKEN = __ENV.MANAGER_TOKEN || '';
const EXEC_TOKEN = __ENV.EXEC_TOKEN || '';
const EMPLOYEE_TOKEN = __ENV.EMPLOYEE_TOKEN || '';

function makeHeaders(token) {
  return {
    'Content-Type': 'application/json',
    apikey: ANON_KEY,
    Authorization: `Bearer ${token}`,
  };
}

function rpc(name, payload, hdrs) {
  return http.post(
    `${BASE_URL}/rest/v1/rpc/${name}`,
    JSON.stringify(payload),
    { headers: hdrs, tags: { name } }
  );
}

// ─── عامل مساعد: UUID وهمي لاختبار الحمل ───
function fakeUUID() {
  // UUID ثابت وهمي — الطلب سيفشل بـ 404/403 لكن يقيس الحمل
  return '00000000-0000-4000-a000-' + String(__VU).padStart(12, '0');
}

/**
 * سيناريو دليل الموقع — get_location_directory
 * يحاكي مديرين يتصفحون قائمة الموظفين مع آخر مواقعهم
 */
export function directoryScenario() {
  const start = Date.now();

  const res = rpc('get_location_directory', {}, makeHeaders(MANAGER_TOKEN));

  directoryLatency.add(Date.now() - start);

  check(res, {
    'دليل: status 200': (r) => r.status === 200,
    'دليل: لا تسريب DB': (r) =>
      !r.body.includes('pg_') && !r.body.includes('SQLSTATE'),
    'دليل: لا تسريب PII خارج النطاق': (r) =>
      !r.body.includes('password') && !r.body.includes('service_role'),
  });

  sleep(3 + Math.random() * 5);
}

/**
 * سيناريو طلب الموقع — إنشاء طلب snapshot متزامن
 * يحاكي عدة مديرين يطلبون مواقع موظفين بنفس الوقت
 */
export function requestScenario() {
  const start = Date.now();

  // محاولة إنشاء طلب موقع snapshot
  const res = rpc('create_location_request', {
    p_employee_id: fakeUUID(),
    p_mode: 'snapshot',
    p_reason: 'اختبار حمل — طلب موقع متزامن',
  }, makeHeaders(MANAGER_TOKEN));

  requestLatency.add(Date.now() - start);

  const ok = check(res, {
    'طلب موقع: status 200/404/409': (r) =>
      r.status === 200 || r.status === 404 || r.status === 409,
    'طلب موقع: لا تسريب DB': (r) =>
      !r.body.includes('pg_') && !r.body.includes('SQLSTATE'),
    'طلب موقع: لا deadlock': (r) =>
      !r.body.includes('deadlock') && !r.body.includes('lock timeout'),
  });

  if (!ok) locationErrors.add(1);

  // بعض المديرين يتابعون النتيجة مباشرة
  if (Math.random() < 0.5) {
    const respStart = Date.now();
    const respRes = rpc('get_live_location_response', {
      p_request_id: fakeUUID(),
    }, makeHeaders(MANAGER_TOKEN));

    responseLatency.add(Date.now() - respStart);

    check(respRes, {
      'نتيجة موقع: status 200/404': (r) => r.status === 200 || r.status === 404,
    });
  }

  sleep(2 + Math.random() * 4);
}

/**
 * سيناريو لوحة المتابعة التنفيذية — get_executive_attendance_overview
 * أثقل RPC — يجمع حضور + مواقع كل الموظفين
 */
export function executiveOverviewScenario() {
  const start = Date.now();

  const res = rpc('get_executive_attendance_overview', {}, makeHeaders(EXEC_TOKEN));

  overviewLatency.add(Date.now() - start);

  check(res, {
    'تنفيذي: status 200': (r) => r.status === 200,
    'تنفيذي: لا تسريب DB': (r) =>
      !r.body.includes('SQLSTATE') && !r.body.includes('pg_catalog'),
    'تنفيذي: حجم استجابة معقول': (r) => r.body.length < 500_000,
  });

  sleep(10 + Math.random() * 15);
}

/**
 * سيناريو RLS query load — استعلامات متزامنة بأدوار مختلفة
 * يختبر أداء RLS تحت حمل عالٍ
 */
export function rlsQueryScenario() {
  const start = Date.now();

  // تدوير بين أدوار مختلفة
  const tokens = [MANAGER_TOKEN, EXEC_TOKEN, EMPLOYEE_TOKEN].filter(Boolean);
  const token = tokens[__VU % tokens.length] || MANAGER_TOKEN;

  // استعلامات متنوعة بنفس الوقت
  const queries = [
    () => rpc('get_location_directory', {}, makeHeaders(token)),
    () => rpc('get_my_access_context', {}, makeHeaders(token)),
    () => rpc('get_my_notifications', {}, makeHeaders(token)),
  ];

  const query = queries[__ITER % queries.length];
  const res = query();

  rlsQueryLatency.add(Date.now() - start);

  check(res, {
    'RLS: status 200': (r) => r.status === 200,
    'RLS: لا permission regression': (r) =>
      r.status !== 500 && !r.body.includes('permission denied'),
    'RLS: لا تسريب بيانات': (r) =>
      !r.body.includes('service_role') && !r.body.includes('pg_'),
  });

  sleep(1 + Math.random() * 3);
}
