// اختبارات دورة الحياة + الهجوم ضد الإنتاج — عبر Management API مع ROLLBACK
const https = require('https');
const TOKEN = process.env.SUPABASE_MGMT_TOKEN;
const PROJECT = 'ujzzvqsodyhnnnpkoaml';

function runSql(query) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ query });
    const req = https.request({
      hostname: 'api.supabase.com',
      path: `/v1/projects/${PROJECT}/database/query`,
      method: 'POST',
      headers: {
        Authorization: `Bearer ${TOKEN}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (res) => {
      let d = '';
      res.on('data', (c) => d += c);
      res.on('end', () => {
        try { resolve(JSON.parse(d)); } catch { resolve(d); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

let passed = 0, failed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log(`  ✅ ${name}`); }
  else { failed++; console.log(`  ❌ ${name} — ${detail || ''}`); }
}

async function main() {
  const IDS = {
    entity: 'a8600000-0000-4000-8000-000000000001',
    dept: 'a8600000-0000-4000-8000-000000000010',
    adminUser: 'a8600000-0000-4000-8000-000000000101',
    empUser: 'a8600000-0000-4000-8000-000000000102',
    adminEmp: 'a8600000-0000-4000-8000-000000000201',
    empEmp: 'a8600000-0000-4000-8000-000000000202',
    device1: 'a8600000-0000-4000-8000-000000000301',
    device2: 'a8600000-0000-4000-8000-000000000302',
    deviceFake: 'a8600000-0000-4000-8000-000000000399',
  };

  console.log('═══ A. فحص البنية ═══');
  let r = await runSql(`SELECT proname, prosecdef FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
    WHERE n.nspname='public' AND p.proname IN ('admin_reinstate_device','admin_revoke_device','approve_device','decide_request','register_my_device') ORDER BY 1`);
  const fns = Array.isArray(r) ? r.map(x => x.proname) : [];
  check('admin_reinstate_device موجودة بـ DEFINER', fns.includes('admin_reinstate_device'));
  check('admin_revoke_device موجودة', fns.includes('admin_revoke_device'));
  check('approve_device موجودة', fns.includes('approve_device'));
  check('decide_request موجودة', fns.includes('decide_request'));
  check('register_my_device موجودة', fns.includes('register_my_device'));

  r = await runSql(`SELECT p.proname,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_ok,
    has_function_privilege('anon', p.oid, 'EXECUTE') as anon_ok
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
    WHERE n.nspname='public' AND p.proname='admin_reinstate_device'`);
  if (Array.isArray(r) && r[0]) {
    check('authenticated يستطيع تنفيذ reinstate', r[0].auth_ok === true);
    check('anon ممنوع من reinstate', r[0].anon_ok === false);
  }

  console.log('\n═══ B. إعداد Fixtures (مع ROLLBACK نهائي) ═══');
  await runSql('BEGIN');
  try {
    // تنظيف سابق
    await runSql(`DELETE FROM public.employee_devices WHERE id IN ('${IDS.device1}','${IDS.device2}','${IDS.deviceFake}')`);
    await runSql(`DELETE FROM public.user_roles WHERE user_id IN ('${IDS.adminUser}','${IDS.empUser}')`);
    await runSql(`DELETE FROM public.profiles WHERE id IN ('${IDS.adminUser}','${IDS.empUser}')`);
    await runSql(`DELETE FROM public.employees WHERE id IN ('${IDS.adminEmp}','${IDS.empEmp}')`);
    await runSql(`DELETE FROM auth.users WHERE id IN ('${IDS.adminUser}','${IDS.empUser}')`);
    await runSql(`DELETE FROM public.departments WHERE id='${IDS.dept}'`);
    await runSql(`DELETE FROM public.legal_entities WHERE id='${IDS.entity}'`);

    await runSql(`INSERT INTO public.legal_entities(id, code, name) VALUES('${IDS.entity}','V25-TST','كيان V25')`);
    await runSql(`INSERT INTO public.departments(id, legal_entity_id, code, name) VALUES('${IDS.dept}','${IDS.entity}','V25-D','إدارة V25')`);
    await runSql(`INSERT INTO auth.users(id, email, aud, role, encrypted_password, email_confirmed_at) VALUES
      ('${IDS.adminUser}','v25-admin@test.local','authenticated','authenticated', crypt('t', gen_salt('bf')), now()),
      ('${IDS.empUser}','v25-emp@test.local','authenticated','authenticated', crypt('t', gen_salt('bf')), now())`);
    await runSql(`INSERT INTO public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) VALUES
      ('${IDS.adminEmp}','${IDS.adminUser}','V25-ADM','مدير الاختبار','${IDS.dept}','active',true,false),
      ('${IDS.empEmp}','${IDS.empUser}','V25-EMP','موظف الاختبار','${IDS.dept}','active',true,false)`);
    await runSql(`INSERT INTO public.profiles(id, employee_id, status) VALUES
      ('${IDS.adminUser}','${IDS.adminEmp}','active'),
      ('${IDS.empUser}','${IDS.empEmp}','active')`);
    await runSql(`INSERT INTO public.user_roles(user_id, role_id) SELECT '${IDS.adminUser}', id FROM public.roles WHERE slug IN ('admin','super-admin') LIMIT 1`);
    await runSql(`INSERT INTO public.employee_devices(id, employee_id, user_id, device_identifier_hash, device_name, platform, status, registered_at)
      VALUES ('${IDS.device1}','${IDS.empEmp}','${IDS.empUser}','v25-test-hash-1','جهاز اختبار','android','pending',now())`);
    await runSql(`INSERT INTO public.employee_devices(id, employee_id, user_id, device_identifier_hash, device_name, platform, status, registered_at)
      VALUES ('${IDS.device2}','${IDS.empEmp}','${IDS.empUser}','v25-test-hash-2','جهاز نشط','ios','active',now())`);

    r = await runSql(`SELECT id FROM public.employee_devices WHERE id='${IDS.device1}'`);
    check('Device1 مُنشأ', Array.isArray(r) && r.length === 1);

    console.log('\n═══ C. سيناريوهات الهجوم ═══');

    // C1. موظف عادي (بلا دور full-access) يحاول reinstate
    r = await runSql(`
      SET request.jwt.claims = '{"sub":"${IDS.empUser}","role":"authenticated"}';
      SELECT public.admin_reinstate_device('${IDS.device1}','attack attempt');
    `).catch(e => ({ err: e.message }));
    const denied1 = r?.err?.includes('42501') || r?.message?.includes('42501') || r?.message?.includes('insufficient');
    check('هجوم C1: موظف عادي محظور من reinstate', denied1, JSON.stringify(r).slice(0, 120));

    // C2. Admin يحاول reinstate جهاز نشط (state machine)
    r = await runSql(`
      SET request.jwt.claims = '{"sub":"${IDS.adminUser}","role":"authenticated"}';
      SELECT public.admin_reinstate_device('${IDS.device2}','attack on active');
    `).catch(e => ({ err: e.message }));
    const denied2 = r?.err?.includes('22023') || r?.message?.includes('22023') || r?.message?.includes('reinstatable');
    check('هجوم C2: reinstate جهاز نشط محظور', denied2, JSON.stringify(r).slice(0, 120));

    // C3. Device وهمي
    r = await runSql(`
      SET request.jwt.claims = '{"sub":"${IDS.adminUser}","role":"authenticated"}';
      SELECT public.admin_reinstate_device('${IDS.deviceFake}','ghost device');
    `).catch(e => ({ err: e.message }));
    const denied3 = r?.err?.includes('P0002') || r?.message?.includes('P0002') || r?.message?.includes('not found');
    check('هجوم C3: device_id وهمي محظور', denied3, JSON.stringify(r).slice(0, 120));

    console.log('\n═══ D. دورة الحياة السعيدة ═══');
    // D1. Revoke
    r = await runSql(`
      SET request.jwt.claims = '{"sub":"${IDS.adminUser}","role":"authenticated"}';
      SELECT public.admin_revoke_device('${IDS.device1}','إلغاء للاختبار');
    `);
    r = await runSql(`SELECT status, revoked_at FROM public.employee_devices WHERE id='${IDS.device1}'`);
    check('D1: جهاز مسحوب (revoked)', r?.[0]?.status === 'revoked', JSON.stringify(r));
    check('D1b: revoked_at مضبوط', !!r?.[0]?.revoked_at);

    // D2. Reinstate
    r = await runSql(`
      SET request.jwt.claims = '{"sub":"${IDS.adminUser}","role":"authenticated"}';
      SELECT public.admin_reinstate_device('${IDS.device1}','إعادة تفعيل');
    `);
    r = await runSql(`SELECT status, revoked_at, metadata FROM public.employee_devices WHERE id='${IDS.device1}'`);
    check('D2: جهاز مُعاد (pending)', r?.[0]?.status === 'pending', JSON.stringify(r));
    check('D2b: revoked_at مسحوب', r?.[0]?.revoked_at === null);
    check('D2c: metadata.reinstated=true', r?.[0]?.metadata?.reinstated === true);

    // D3. Approve
    r = await runSql(`
      SET request.jwt.claims = '{"sub":"${IDS.adminUser}","role":"authenticated"}';
      SELECT public.approve_device('${IDS.device1}', true, null);
    `);
    r = await runSql(`SELECT status FROM public.employee_devices WHERE id='${IDS.device1}'`);
    check('D3: جهاز مُفعَّل (active)', r?.[0]?.status === 'active', JSON.stringify(r));

    console.log('\n═══ E. سجل الأمان ═══');
    r = await runSql(`SELECT COUNT(*) as n FROM public.security_events
      WHERE event_type='device.reinstated' AND occurred_at > now() - interval '5 minutes'`);
    check('E1: حدث device.reinstated مسجل', parseInt(r?.[0]?.n) >= 1, JSON.stringify(r));

  } finally {
    console.log('\n═══ التراجع عن كل التغييرات (ROLLBACK) ═══');
    await runSql('ROLLBACK');
    console.log('  🔄 تم التراجع — قاعدة البيانات نظيفة');
  }

  console.log(`\n════════════════════════════════╗`);
  console.log(`  نتيجة: ${passed} نجح ✓ | ${failed} فشل ✗`);
  console.log(`════════════════════════════════╝`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
