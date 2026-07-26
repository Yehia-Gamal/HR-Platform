/**
 * k6 Load Test — سيناريو التقارير والـ RPCs الثقيلة
 *
 * Usage:
 *   k6 run tests/load/reports-heavy-rpcs.js \
 *     --env BASE_URL=https://ujzzvqsodyhnnnpkoaml.supabase.co \
 *     --env ANON_KEY=<anon-key> \
 *     --env AUTH_TOKEN=<jwt>
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';

const dashboardLatency = new Trend('dashboard_latency', true);
const reportLatency = new Trend('report_latency', true);

export const options = {
  scenarios: {
    dashboard_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 20 },
        { duration: '2m', target: 20 },
        { duration: '30s', target: 0 },
      ],
      exec: 'dashboardScenario',
    },

    report_generation: {
      executor: 'ramping-vus',
      startVUs: 0,
      startTime: '4m',
      stages: [
        { duration: '30s', target: 10 },
        { duration: '2m', target: 10 },
        { duration: '30s', target: 0 },
      ],
      exec: 'reportScenario',
    },
  },

  thresholds: {
    dashboard_latency: ['p(95)<2000'],
    report_latency: ['p(95)<5000'],
    http_req_failed: ['rate<0.05'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:54321';
const ANON_KEY = __ENV.ANON_KEY || '';
const AUTH_TOKEN = __ENV.AUTH_TOKEN || '';

const headers = {
  'Content-Type': 'application/json',
  apikey: ANON_KEY,
  Authorization: `Bearer ${AUTH_TOKEN}`,
};

function rpc(name, payload = {}) {
  return http.post(
    `${BASE_URL}/rest/v1/rpc/${name}`,
    JSON.stringify(payload),
    { headers, tags: { name } }
  );
}

/**
 * سيناريو لوحة المعلومات — يحاكي فتح الصفحة الرئيسية
 */
export function dashboardScenario() {
  const start = Date.now();

  // RPCs التي تُستدعى عند فتح لوحة المعلومات
  const responses = [
    rpc('get_my_access_context'),
    rpc('get_dashboard_overview'),
    rpc('get_my_notifications'),
  ];

  dashboardLatency.add(Date.now() - start);

  responses.forEach((res, i) => {
    check(res, {
      [`dashboard RPC ${i}: status 200`]: (r) => r.status === 200,
    });
  });

  sleep(5 + Math.random() * 10);
}

/**
 * سيناريو التقرير الشهري — أثقل RPC
 */
export function reportScenario() {
  const start = Date.now();

  const res = rpc('get_employee_monthly_attendance_statement', {
    p_employee_id: null, // سيستخدم الموظف الحالي
    p_year: 2026,
    p_month: 7,
  });

  reportLatency.add(Date.now() - start);

  check(res, {
    'تقرير شهري: status 200 or 404': (r) =>
      r.status === 200 || r.status === 404,
    'تقرير شهري: لا تسريب DB': (r) =>
      !r.body.includes('pg_') && !r.body.includes('SQLSTATE'),
  });

  sleep(10 + Math.random() * 20);
}
