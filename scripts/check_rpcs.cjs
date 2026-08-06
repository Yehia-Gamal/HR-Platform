// فحص وجود دوال RPC على السيرفر البعيد — يعيد EXISTS ✓ للدوال الموجودة
// (HTTP 400/401/42501 = الدالة موجودة لكن رُفض الطلب لصلاحية/وسائط)
// و MISSING ✗ لـ 404 (دالة غير موجودة أو لا تطابق الوسائط).
// يُشغّل بـ: node scripts/check_rpcs.cjs
const https = require('https');

const HOST = 'ujzzvqsodyhnnnpkoaml.supabase.co';
const KEY = 'sb_publishable_Q5JTOX-mLp5Y9wmxlZyTnQ_QBu5wPC2';

function rpc(fn, payload = {}) {
  return new Promise((resolve) => {
    const body = JSON.stringify(payload);
    const req = https.request({
      hostname: HOST,
      path: '/rest/v1/rpc/' + fn,
      method: 'POST',
      headers: {
        'apikey': KEY,
        'Authorization': 'Bearer ' + KEY,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve({ fn, status: res.statusCode, body: d.slice(0, 200) }));
    });
    req.on('error', e => resolve({ fn, status: 'ERR', body: e.message }));
    req.write(body);
    req.end();
  });
}

// لكل دالة: الوسائط المطلوبة (قيم وهمية كافية ليعثر PostgREST على الدالة)
const RPCS = [
  { fn: 'admin_reinstate_device', args: { p_device_id: '00000000-0000-0000-0000-000000000000' } },
  { fn: 'admin_revoke_device', args: { p_device_id: '00000000-0000-0000-0000-000000000000' } },
  { fn: 'approve_device', args: { p_device_id: '00000000-0000-0000-0000-000000000000', p_approved: true } },
  { fn: 'decide_request', args: { p_request_id: '00000000-0000-0000-0000-000000000000', p_decision: 'approved' } },
  { fn: 'register_my_device', args: { p_installation_id: 'test', p_platform: 'android', p_device_name: 't', p_device_model: 't', p_os_version: 't', p_app_version: 't', p_app_build: 1 } },
  // نبض اليوم — دليل الموظفين
  { fn: 'get_executive_attendance_overview', args: { p_date: '2026-08-06' } },
  { fn: 'get_live_location_response', args: { p_request_id: '00000000-0000-0000-0000-000000000000' } },
  { fn: 'request_live_location', args: { p_employee_id: '00000000-0000-0000-0000-000000000000', p_mode: 'snapshot', p_reason: 'test check' } },
  // دوال دليل الموظفين
  { fn: 'get_employees_enriched', args: { p_search: null, p_status: null, p_limit: 1 } },
  { fn: 'get_employee_360', args: { p_employee_id: '00000000-0000-0000-0000-000000000000' } },
];

(async () => {
  let ok = 0;
  let missing = 0;
  for (const { fn, args } of RPCS) {
    const r = await rpc(fn, args);
    const label = [400, 401, 42501].includes(r.status) ? 'EXISTS ✓' : r.status === 404 ? 'MISSING ✗' : `HTTP ${r.status} ?`;
    if ([400, 401, 42501].includes(r.status)) ok++;
    else if (r.status === 404) missing++;
    console.log(fn.padEnd(35), label, r.status === 404 ? '' : `| ${r.body}`);
  }
  console.log('---');
  console.log(`${ok}/${RPCS.length} موجودة، ${missing} مفقودة`);
  process.exit(missing > 0 ? 1 : 0);
})();
