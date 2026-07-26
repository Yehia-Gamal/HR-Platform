/**
 * k6 Load Test — سيناريو الحضور المتزامن
 *
 * يحاكي حضور 80 موظف في نفس الوقت (بداية الوردية)
 *
 * Usage:
 *   k6 run tests/load/attendance-punch.js \
 *     -e SUPABASE_URL=https://xxx.supabase.co \
 *     -e SUPABASE_ANON_KEY=eyJ... \
 *     -e TEST_TOKEN=eyJ...
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// ── مقاييس مخصصة ──
const punchSuccess = new Rate('punch_success');
const punchDuration = new Trend('punch_duration_ms');

// ── إعدادات السيناريو ──
export const options = {
  scenarios: {
    // الحمل العادي: 50 مستخدم
    normal_load: {
      executor: 'constant-vus',
      vus: 50,
      duration: '5m',
      tags: { scenario: 'normal' },
    },
    // ضعف الحمل: 100 مستخدم
    double_load: {
      executor: 'constant-vus',
      vus: 100,
      duration: '5m',
      startTime: '6m',
      tags: { scenario: '2x' },
    },
    // انفجار: 150 مستخدم لمدة دقيقتين
    burst: {
      executor: 'constant-vus',
      vus: 150,
      duration: '2m',
      startTime: '12m',
      tags: { scenario: '3x_burst' },
    },
  },

  thresholds: {
    // P0: p95 أقل من 500ms في الحمل العادي
    'punch_duration_ms{scenario:normal}': ['p(95)<500'],
    // P1: p95 أقل من 1000ms في ضعف الحمل
    'punch_duration_ms{scenario:2x}': ['p(95)<1000'],
    // P2: لا انهيار في الانفجار
    'punch_success{scenario:3x_burst}': ['rate>0.90'],
    // عام
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

// ── إحداثيات اختبارية (داخل geofence افتراضي) ──
const TEST_LOCATIONS = [
  { lat: 30.0444, lng: 31.2357 }, // القاهرة
  { lat: 30.0450, lng: 31.2360 },
  { lat: 30.0440, lng: 31.2350 },
];

export default function () {
  const location = TEST_LOCATIONS[Math.floor(Math.random() * TEST_LOCATIONS.length)];

  const payload = JSON.stringify({
    latitude: location.lat + (Math.random() - 0.5) * 0.001,
    longitude: location.lng + (Math.random() - 0.5) * 0.001,
    accuracy: 10 + Math.random() * 20,
    event_type: 'check_in',
  });

  const res = http.post(`${BASE_URL}/rest/v1/rpc/punch_attendance_local_v2`, payload, {
    headers,
    tags: { name: 'punch_attendance' },
  });

  const ok = check(res, {
    'status is 200': (r) => r.status === 200,
    'no error in body': (r) => !r.body.includes('"error"'),
    'response time < 2s': (r) => r.timings.duration < 2000,
  });

  punchSuccess.add(ok);
  punchDuration.add(res.timings.duration);

  sleep(1 + Math.random() * 2);
}

export function handleSummary(data) {
  return {
    'tests/load/results/attendance-summary.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}

function textSummary(data, opts) {
  const checks = data.metrics?.checks?.values || {};
  const duration = data.metrics?.punch_duration_ms?.values || {};
  return `
╔══════════════════════════════════════════════╗
║   نتائج اختبار الحمل — الحضور المتزامن      ║
╠══════════════════════════════════════════════╣
║ نسبة النجاح: ${(checks.rate * 100 || 0).toFixed(1)}%
║ p50: ${(duration.med || 0).toFixed(0)}ms
║ p95: ${(duration['p(95)'] || 0).toFixed(0)}ms
║ p99: ${(duration['p(99)'] || 0).toFixed(0)}ms
╚══════════════════════════════════════════════╝
`;
}
