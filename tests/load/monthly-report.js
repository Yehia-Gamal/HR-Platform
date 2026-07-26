/**
 * k6 Load Test — سيناريو التقرير الشهري
 *
 * يحاكي طلب تقرير الحضور الشهري من عدة مستخدمين
 *
 * Usage:
 *   k6 run tests/load/monthly-report.js \
 *     -e SUPABASE_URL=https://xxx.supabase.co \
 *     -e SUPABASE_ANON_KEY=eyJ... \
 *     -e TEST_TOKEN=eyJ...
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';

const reportDuration = new Trend('report_duration_ms');

export const options = {
  scenarios: {
    report_generation: {
      executor: 'constant-vus',
      vus: 20,
      duration: '3m',
    },
  },
  thresholds: {
    report_duration_ms: ['p(95)<3000'],
    http_req_failed: ['rate<0.05'],
  },
};

const BASE_URL = __ENV.SUPABASE_URL || 'http://127.0.0.1:54321';
const ANON_KEY = __ENV.SUPABASE_ANON_KEY || '';
const TEST_TOKEN = __ENV.TEST_TOKEN || '';

const headers = {
  'Content-Type': 'application/json',
  Authorization: `Bearer ${TEST_TOKEN}`,
  apikey: ANON_KEY,
};

export default function () {
  // طلب كشف الحضور الشهري
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth(); // الشهر السابق
  const payload = JSON.stringify({
    p_year: year,
    p_month: month || 12,
  });

  const res = http.post(
    `${BASE_URL}/rest/v1/rpc/get_my_monthly_attendance_statement`,
    payload,
    { headers, tags: { name: 'monthly_report' } }
  );

  check(res, {
    'status 200': (r) => r.status === 200,
    'response < 5s': (r) => r.timings.duration < 5000,
  });

  reportDuration.add(res.timings.duration);
  sleep(2 + Math.random() * 3);
}
