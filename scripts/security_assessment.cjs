// اختبارات أمنية شاملة ضد الإنتاج — منظور attacker
const https = require('https');
const fs = require('fs');

const HOST = 'ujzzvqsodyhnnnpkoaml.supabase.co';
const ANON_KEY = 'sb_publishable_Q5JTOX-mLp5Y9wmxlZyTnQ_QBu5wPC2';

const results = [];
function log(severity, category, finding, evidence, fix) {
  results.push({ severity, category, finding, evidence, fix });
}

function request(opts, body = null) {
  return new Promise((resolve) => {
    const req = https.request({
      hostname: HOST,
      ...opts,
      headers: {
        apikey: ANON_KEY,
        'Content-Type': 'application/json',
        ...(opts.headers || {}),
      },
    }, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: d }));
    });
    req.on('error', (e) => resolve({ status: 0, error: e.message }));
    if (body) req.write(typeof body === 'string' ? body : JSON.stringify(body));
    req.end();
  });
}

// ═══════════════════════════════════════════════════════════════
// A. Reconnaissance — ما المتاح بدون JWT؟
// ═══════════════════════════════════════════════════════════════
async function phaseA() {
  console.log('\n=== A. Reconnaissance ===');

  // A1. OpenAPI spec exposure
  let r = await request({ path: '/rest/v1/', method: 'GET' });
  if (r.status === 200) {
    const paths = Object.keys(JSON.parse(r.body).paths || {});
    log('INFO', 'recon', 'OpenAPI spec مكشوف', `${paths.length} endpoints مرئية`, 'Regular - قد يكون مقصود');
  } else log('PASS', 'recon', 'OpenAPI محمي', `HTTP ${r.status}`, '');

  // A2. Storage buckets listable?
  r = await request({ path: '/storage/v1/bucket', method: 'GET' });
  if (r.status === 200) {
    const buckets = JSON.parse(r.body);
    log('HIGH', 'storage', `قوائم buckets مرئية — ${buckets.length} buckets`, r.body.slice(0, 200), 'فرض RLS على storage.objects');
  } else log('PASS', 'storage', 'Bucket listing محمي', `HTTP ${r.status}`, '');

  // A3. Auth endpoints enumeration
  r = await request({ path: '/auth/v1/signup', method: 'POST' }, { email: 'nonexistent-' + Date.now() + '@test.com', password: 'x'.repeat(50) });
  log('INFO', 'auth', `Signup endpoint status: ${r.status}`, r.body.slice(0, 100), '—');

  // A4. Public tables via REST
  const publicTables = ['employees', 'departments', 'legal_entities', 'security_events', 'audit_events'];
  for (const t of publicTables) {
    r = await request({ path: `/rest/v1/${t}?select=*&limit=1`, method: 'GET' });
    if (r.status === 200) {
      const data = JSON.parse(r.body);
      if (Array.isArray(data) && data.length > 0) {
        log('CRITICAL', 'RLS-gap', `Table ${t} readable by anon!`, Object.keys(data[0]).slice(0, 8).join(','), `Enable RLS policies on ${t}`);
      } else {
        log('PASS', 'RLS-gap', `Table ${t} exists but empty for anon`, '', '');
      }
    } else if (r.status === 401) {
      log('PASS', 'RLS-gap', `Table ${t} RLS enforced`, '401', '');
    } else if (r.status === 404) {
      // Table not exposed via REST
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// B. Injection attacks — ما الذي يقبل المدخلات الضارة؟
// ═══════════════════════════════════════════════════════════════
async function phaseB() {
  console.log('\n=== B. Injection probes ===');

  // B1. SQL injection في query params (PostgREST parser)
  const sqli = [
    { name: 'OR 1=1', path: 'employees?id=eq.1%20OR%201=1', expected: [401, 403, 406] },
    { name: 'UNION SELECT', path: 'employees?id=eq.1%27%20UNION%20SELECT%20*', expected: [401, 403, 406] },
    { name: 'Comment drop', path: "employees?select=*%3B--", expected: [400, 401, 403] },
  ];
  for (const t of sqli) {
    const r = await request({ path: `/rest/v1/${t.path}`, method: 'GET' });
    const blocked = t.expected.includes(r.status);
    log(blocked ? 'PASS' : 'MEDIUM', 'sqli', `PostgREST ${t.name}`, `HTTP ${r.status}`, blocked ? '' : 'Verify PostgREST version');
  }

  // B2. XSS في inputs
  r = await request({ path: '/rest/v1/rpc/notify_employee', method: 'POST' }, {
    p_employee_id: 'a8600000-0000-4000-8000-000000000201',
    p_title: '<script>alert(1)</script>',
    p_body: '<img src=x onerror=alert(1)>',
    p_kind: 'info', p_priority: 'low', p_related_type: 'x', p_related_id: null,
  });
  // يجب أن تُرفض بنقص authentication
  log(r.status !== 200 ? 'PASS' : 'HIGH', 'xss', `notify_employee XSS payload`, `HTTP ${r.status}`, r.status !== 200 ? '' : 'Check sanitization');

  // B3. Prototype pollution
  r = await request({ path: '/rest/v1/rpc/register_my_device', method: 'POST' }, {
    p_installation_id: 'probe-test-12345678',
    p_platform: 'android', p_device_name: 'x', p_device_model: 'x',
    p_os_version: 'x', p_app_version: 'x', p_app_build: 0,
    '__proto__': { isAdmin: true }, 'constructor': { prototype: { isAdmin: true } },
  });
  log('INFO', 'proto-poll', 'prototype pollution probe', `HTTP ${r.status}`, '—');
}

// ═══════════════════════════════════════════════════════════════
// C. Authorization bypass — IDOR, privilege escalation
// ═══════════════════════════════════════════════════════════════
async function phaseC() {
  console.log('\n=== C. Authorization ===');

  // C1. IDOR — can anon access employee by ID?
  const fakeIds = [
    'a8600000-0000-4000-8000-000000000202', // our test employee (rolled back)
    '00000000-0000-0000-0000-000000000000',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
  ];
  for (const id of fakeIds) {
    const r = await request({ path: `/rest/v1/employees?id=eq.${id}`, method: 'GET' });
    log(r.status === 401 || r.status === 403 ? 'PASS' : r.status === 200 ? 'CRITICAL' : 'INFO',
      'IDOR', `employees?id=${id}`, `HTTP ${r.status}`, r.status === 200 ? 'IDOR vulnerability!' : '');
  }

  // C2. Privilege escalation via role manipulation
  const r = await request({ path: '/rest/v1/rpc/rpc_assign_role', method: 'POST' }, {
    p_user_id: 'a8600000-0000-4000-8000-000000000102',
    p_role_id: 'a8600000-0000-4000-8000-000000000001',
  });
  log(r.status === 401 || r.status === 403 ? 'PASS' : 'CRITICAL',
    'priv-esc', `rpc_assign_role by anon`, `HTTP ${r.status}`, r.status === 401 || r.status === 403 ? '' : 'privilege escalation possible');

  // C3. Cross-tenant access via predictable IDs
  const r2 = await request({ path: '/rest/v1/employee_devices?employee_id=eq.a8600000-0000-4000-8000-000000000202', method: 'GET' });
  log('INFO', 'cross-tenant', `employee_devices access`, `HTTP ${r2.status}`, '—');
}

// ═══════════════════════════════════════════════════════════════
// D. Rate limiting + DoS
// ═══════════════════════════════════════════════════════════════
async function phaseD() {
  console.log('\n=== D. Rate limiting ===');

  const start = Date.now();
  let success = 0, failed = 0;
  for (let i = 0; i < 50; i++) {
    const r = await request({ path: '/rest/v1/rpc/version', method: 'POST' }, {});
    if (r.status < 500) success++; else failed++;
  }
  const duration = (Date.now() - start) / 1000;
  log('INFO', 'rate-limit', `50 rapid requests: ${success} ok, ${failed} err, ${duration}s`,
    `~${(50 / duration).toFixed(0)} req/s`, 'Consider edge WAF rules');
}

// ═══════════════════════════════════════════════════════════════
// E. Client-side secret exposure
// ═══════════════════════════════════════════════════════════════
async function phaseE() {
  console.log('\n=== E. Client-side exposure check ===');

  // Check admin web for hardcoded secrets
  try {
    const r = await fetch('https://ahla-shabab-management-os.vercel.app/');
    const html = await r.text();
    const secretPatterns = [
      { name: 'service_role', pattern: /service_role|SUPABASE_SERVICE/ },
      { name: 'db_password', pattern: /postgres.*[:@]\w+/ },
      { name: 'access_token', pattern: /sbp_[a-f0-9]{30,}/ },
      { name: 'vercel_token', pattern: /vcp_[A-Za-z0-9]{30,}/ },
      { name: 'anon_key (ok if intended)', pattern: /sb_publishable_[A-Za-z0-9_-]+/ },
    ];
    for (const sp of secretPatterns) {
      const found = html.match(sp.pattern);
      if (found) {
        const isAnon = sp.name.includes('anon');
        log(isAnon ? 'INFO' : 'HIGH', 'secret-leak', `${sp.name} في الويب`, found[0].slice(0, 30) + '...',
          isAnon ? 'Anon key OK if RLS enforced' : 'CRITICAL: rotate secret immediately');
      }
    }
    log('INFO', 'web', 'Admin web fetched', `${html.length} bytes`, '—');
  } catch (e) {
    log('INFO', 'web', 'Could not fetch admin web', e.message, '—');
  }
}

async function main() {
  console.log(`
╔════════════════════════════════════════════╗
║  Security Assessment: HR Platform (Prod)  ║
║  Target: ${HOST.padEnd(30)} ║
╚════════════════════════════════════════════╝`);

  await phaseA();
  await phaseB();
  await phaseC();
  await phaseD();
  await phaseE();

  console.log('\n╔════════════════════════════════════════════╗');
  console.log('║           نتيجة التقييم الأمني           ║');
  console.log('╚════════════════════════════════════════════╝\n');

  const critical = results.filter(r => r.severity === 'CRITICAL');
  const high = results.filter(r => r.severity === 'HIGH');
  const medium = results.filter(r => r.severity === 'MEDIUM');
  const pass = results.filter(r => r.severity === 'PASS');

  console.log(`CRITICAL: ${critical.length}`);
  console.log(`HIGH:     ${high.length}`);
  console.log(`MEDIUM:   ${medium.length}`);
  console.log(`PASS:     ${pass.length}`);

  if (critical.length) {
    console.log('\n🚨 CRITICAL FINDINGS:');
    critical.forEach(f => console.log(`  [${f.category}] ${f.finding}: ${f.evidence} → ${f.fix}`));
  }
  if (high.length) {
    console.log('\n⚠️  HIGH FINDINGS:');
    high.forEach(f => console.log(`  [${f.category}] ${f.finding} → ${f.fix}`));
  }
  if (medium.length) {
    console.log('\n⚡ MEDIUM FINDINGS:');
    medium.forEach(f => console.log(`  [${f.category}] ${f.finding}`));
  }

  fs.writeFileSync('security_assessment_report.json', JSON.stringify(results, null, 2));
  console.log('\n📄 Full report: security_assessment_report.json');
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
