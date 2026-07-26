/**
 * k6 Load Test — سيناريو الحضور المتزامن
 * أهم سيناريو للحمل: موظفون متعددون يسجلون الحضور في نفس اللحظة
 *
 * Usage:
 *   k6 run tests/load/attendance-concurrent.js \
 *     --env BASE_URL=https://ujzzvqsodyhnnnpkoaml.supabase.co \
 *     --env ANON_KEY=<anon-key> \
 *     --env AUTH_TOKEN=<jwt>
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// ━━━ مؤشرات مخصصة ━━━
const attendanceErrors = new Counter('attendance_errors');
const attendanceLatency = new Trend('attendance_latency', true);

// ━━━ سيناريوهات الحمل ━━━
export const options = {
  scenarios: {
    // الحمل العادي: 50 موظف يسجلون حضور خلال 5 دقائق
    normal_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 50 },   // صعود تدريجي
        { duration: '3m', target: 50 },   // ثبات
        { duration: '1m', target: 0 },    // هبوط
      ],
      exec: 'attendancePunch',
      tags: { scenario: 'normal' },
    },

    // انفجار: 150 موظف دفعة واحدة (بداية الدوام)
    burst: {
      executor: 'ramping-vus',
      startVUs: 0,
      startTime: '6m',
      stages: [
        { duration: '15s', target: 150 }, // صعود سريع
        { duration: '2m', target: 150 },  // ضغط مستمر
        { duration: '15s', target: 0 },   // هبوط
      ],
      exec: 'attendancePunch',
      tags: { scenario: 'burst' },
    },
  },

  thresholds: {
    // P0: p95 < 800ms للحضور العادي
    'attendance_latency{scenario:normal}': ['p(95)<800'],
    // P1: p95 < 2000ms حتى في الانفجار
    'attendance_latency{scenario:burst}': ['p(95)<2000'],
    // معدل الأخطاء < 1%
    'attendance_errors': ['count<10'],
    // HTTP failures < 5%
    'http_req_failed': ['rate<0.05'],
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

/**
 * سيناريو تسجيل الحضور
 * يحاكي: موظف يفتح التطبيق → يحمل حالة الحضور → يسجل الحضور
 */
export function attendancePunch() {
  // 1. جلب حالة الحضور الحالية
  const stateRes = http.post(
    `${BASE_URL}/rest/v1/rpc/get_my_attendance_state`,
    '{}',
    { headers, tags: { name: 'get_attendance_state' } }
  );
  check(stateRes, {
    'حالة الحضور: status 200': (r) => r.status === 200,
    'حالة الحضور: رد JSON': (r) => {
      try { JSON.parse(r.body); return true; } catch { return false; }
    },
  });

  sleep(1 + Math.random() * 2); // تأخير واقعي

  // 2. تسجيل الحضور
  const punchPayload = JSON.stringify({
    p_latitude: 30.0444 + (Math.random() - 0.5) * 0.001,
    p_longitude: 31.2357 + (Math.random() - 0.5) * 0.001,
    p_event_type: 'check_in',
    p_accuracy_meters: 10 + Math.random() * 20,
  });

  const start = Date.now();
  const punchRes = http.post(
    `${BASE_URL}/rest/v1/rpc/record_attendance_event`,
    punchPayload,
    { headers, tags: { name: 'record_attendance' } }
  );
  const elapsed = Date.now() - start;

  attendanceLatency.add(elapsed);

  const punchOk = check(punchRes, {
    'تسجيل الحضور: status 200': (r) => r.status === 200,
    'تسجيل الحضور: لا تسريب DB': (r) =>
      !r.body.includes('pg_') && !r.body.includes('SQLSTATE'),
  });

  if (!punchOk) {
    attendanceErrors.add(1);
  }

  sleep(2 + Math.random() * 3);
}

/**
 * سيناريو قراءة التقرير الشهري
 */
export function monthlyReport() {
  const res = http.post(
    `${BASE_URL}/rest/v1/rpc/get_my_monthly_attendance_statement`,
    JSON.stringify({ p_year: 2026, p_month: 7 }),
    { headers, tags: { name: 'monthly_report' } }
  );

  check(res, {
    'التقرير الشهري: status 200': (r) => r.status === 200,
  });

  sleep(5);
}
