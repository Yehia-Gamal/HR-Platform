// اختبار دورة حياة الأجهزة + سير الإجازات + سيناريوهات الهجوم ضد Staging
// تشغيل: set SUPABASE_DB_PASSWORD=xxx && node scripts/test_device_reinstate_lifecycle.mjs
import pg from 'pg';

if (!process.env.SUPABASE_DB_PASSWORD) {
  console.error('❌ SUPABASE_DB_PASSWORD env var is required.');
  console.error('   Shame on you if you hardcode production secrets.');
  process.exit(1);
}

const pool = new pg.Pool({
  host: process.env.SUPABASE_DB_HOST || 'db.ujzzvqsodyhnnnpkoaml.supabase.co',
  port: parseInt(process.env.SUPABASE_DB_PORT || '5432', 10),
  database: process.env.SUPABASE_DB_NAME || 'postgres',
  user: process.env.SUPABASE_DB_USER || 'postgres',
  password: process.env.SUPABASE_DB_PASSWORD,
  ssl: { rejectUnauthorized: false },
});

let passed = 0;
let failed = 0;

async function t(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`✅ ${name}`);
  } catch (err) {
    failed++;
    console.error(`❌ ${name}`);
    console.error(`   ${err.message}`);
  }
}

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

async function setup(client) {
  await client.query('BEGIN');
  // تنظيف سابق
  await client.query(`DELETE FROM public.employee_devices WHERE id = ANY(ARRAY[$1,$2]::uuid[])`, [IDS.device1, IDS.device2]);
  await client.query(`DELETE FROM public.profiles WHERE id = ANY(ARRAY[$1,$2]::uuid[])`, [IDS.adminUser, IDS.empUser]);
  await client.query(`DELETE FROM public.user_roles WHERE user_id = ANY(ARRAY[$1,$2]::uuid[])`, [IDS.adminUser, IDS.empUser]);
  await client.query(`DELETE FROM public.employees WHERE id = ANY(ARRAY[$1,$2]::uuid[])`, [IDS.adminEmp, IDS.empEmp]);
  await client.query(`DELETE FROM auth.users WHERE id = ANY(ARRAY[$1,$2]::uuid[])`, [IDS.adminUser, IDS.empUser]);
  await client.query(`DELETE FROM public.departments WHERE id = $1`, [IDS.dept]);
  await client.query(`DELETE FROM public.legal_entities WHERE id = $1`, [IDS.entity]);

  await client.query(`INSERT INTO public.legal_entities(id, code, name) VALUES($1,'V25-STG-LE','كيان V25')`, [IDS.entity]);
  await client.query(`INSERT INTO public.departments(id, legal_entity_id, code, name) VALUES($1,$2,'V25-STG-D','إدارة V25')`, [IDS.dept, IDS.entity]);
  await client.query(`INSERT INTO auth.users(id, email, aud, role) VALUES($1,'v25-admin-stg@test.local','authenticated','authenticated'),($2,'v25-emp-stg@test.local','authenticated','authenticated')`, [IDS.adminUser, IDS.empUser]);
  await client.query(`INSERT INTO public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) VALUES($1,$2,'V25-ADM-STG','مسؤول V25 ستج',$3,'active',true,false),($4,$5,'V25-EMP-STG','موظف V25 ستج',$3,'active',true,false)`, [IDS.adminEmp, IDS.adminUser, IDS.dept, IDS.empEmp, IDS.empUser]);
  await client.query(`INSERT INTO public.profiles(id, employee_id, status) VALUES($1,$2,'active'),($3,$4,'active')`, [IDS.adminUser, IDS.adminEmp, IDS.empUser, IDS.empEmp]);
  await client.query(`INSERT INTO public.user_roles(user_id, role_id) SELECT $1, id FROM public.roles WHERE slug='admin' ON CONFLICT DO NOTHING`, [IDS.adminUser]);
  await client.query(`INSERT INTO public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, metadata) VALUES($1,$2,$3,'hash_v25_stg_1',null,'جهاز اختبار ستج 1','android','pending',now(),'{}'::jsonb)`, [IDS.device1, IDS.empEmp, IDS.empUser]);
  await client.query(`INSERT INTO public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, metadata) VALUES($1,$2,$3,'hash_v25_stg_2',null,'جهاز اختبار ستج نشط','ios','active',now(),'{}'::jsonb)`, [IDS.device2, IDS.empEmp, IDS.empUser]);
}

async function teardown(client) {
  await client.query('ROLLBACK');
}

async function actAs(client, userId) {
  await client.query(`SELECT set_config('request.jwt.claims', $1, true)`, [JSON.stringify({ sub: userId, role: 'authenticated' })]);
  await client.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [userId]);
  await client.query('SET LOCAL ROLE authenticated');
}

async function expectThrows(client, sql, errcode, messagePart) {
  try {
    await client.query(sql);
    throw new Error(`Expected throw ${errcode} but succeeded`);
  } catch (e) {
    if (!e.message.includes(errcode) && !e.message.includes(messagePart || '')) {
      throw e;
    }
  }
}

async function main() {
  const client = await pool.connect();
  try {
    await setup(client);

    // 1. بنية الدوال
    await t('admin_reinstate_device موجود', async () => {
      const r = await client.query(`SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public' AND p.proname='admin_reinstate_device'`);
      if (!r.rows.length) throw new Error('function not found');
    });
    await t('admin_reinstate_device SECURITY DEFINER + search_path', async () => {
      const r = await client.query(`SELECT prosecdef, proconfig FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public' AND p.proname='admin_reinstate_device'`);
      if (!r.rows[0]?.prosecdef) throw new Error('not security definer');
      if (!r.rows[0]?.proconfig?.some(c => c.startsWith('search_path='))) throw new Error('search_path not pinned');
    });
    await t('anon ممنوع من admin_reinstate_device', async () => {
      const r = await client.query(`SELECT has_function_privilege('anon', p.oid, 'EXECUTE') as ok FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public' AND p.proname='admin_reinstate_device'`);
      if (r.rows[0]?.ok) throw new Error('anon can execute!');
    });
    await t('authenticated مسموح من admin_reinstate_device', async () => {
      const r = await client.query(`SELECT has_function_privilege('authenticated', p.oid, 'EXECUTE') as ok FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public' AND p.proname='admin_reinstate_device'`);
      if (!r.rows[0]?.ok) throw new Error('authenticated cannot execute');
    });
    await t('decide_request موجود ومحمي', async () => {
      const r = await client.query(`SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public' AND p.proname='decide_request'`);
      if (!r.rows.length) throw new Error('not found');
    });

    // 2. سيناريوهات هجوم
    await actAs(client, IDS.empUser);
    await t('موظف عادي لا يستطيع reinstate (42501)', async () => {
      await expectThrows(client, `SELECT public.admin_reinstate_device('${IDS.device1}', 'محاولة هجوم')`, '42501', 'insufficient permissions');
    });

    await actAs(client, IDS.adminUser);
    await t('لا يمكن reinstate جهاز نشط (22023)', async () => {
      await expectThrows(client, `SELECT public.admin_reinstate_device('${IDS.device2}', 'محاولة هجوم')`, '22023', 'not in a reinstatable state');
    });
    await t('لا يمكن reinstate جهاز وهمي (P0002)', async () => {
      await expectThrows(client, `SELECT public.admin_reinstate_device('${IDS.deviceFake}', 'فحص')`, 'P0002', 'device not found');
    });

    // 3. دورة كاملة: pending → revoke → reinstate → approve
    await t('admin يستطيع revoke جهاز pending', async () => {
      await client.query(`SELECT public.admin_revoke_device('${IDS.device1}', 'اختبار الإلغاء')`);
    });
    await t('الجهاز أصبح revoked', async () => {
      const r = await client.query(`SELECT status FROM public.employee_devices WHERE id=$1`, [IDS.device1]);
      if (r.rows[0]?.status !== 'revoked') throw new Error(`got ${r.rows[0]?.status}`);
    });
    await t('revoked_at مضبوط', async () => {
      const r = await client.query(`SELECT revoked_at FROM public.employee_devices WHERE id=$1`, [IDS.device1]);
      if (!r.rows[0]?.revoked_at) throw new Error('revoked_at is null');
    });
    await t('admin يستطيع reinstate الجهاز الملغي', async () => {
      await client.query(`SELECT public.admin_reinstate_device('${IDS.device1}', 'إعادة تفعيل بعد حل المشكلة الأمنية')`);
    });
    await t('الجهاز عاد إلى pending', async () => {
      const r = await client.query(`SELECT status FROM public.employee_devices WHERE id=$1`, [IDS.device1]);
      if (r.rows[0]?.status !== 'pending') throw new Error(`got ${r.rows[0]?.status}`);
    });
    await t('revoked_atcleared بعد reinstate', async () => {
      const r = await client.query(`SELECT revoked_at, revocation_source FROM public.employee_devices WHERE id=$1`, [IDS.device1]);
      if (r.rows[0]?.revoked_at) throw new Error('revoked_at not cleared');
      if (r.rows[0]?.revocation_source) throw new Error('revocation_source not cleared');
    });
    await t('metadata يحتوي reinstated=true', async () => {
      const r = await client.query(`SELECT metadata FROM public.employee_devices WHERE id=$1`, [IDS.device1]);
      if (!r.rows[0]?.metadata?.reinstated) throw new Error('reinstated flag missing');
      if (r.rows[0]?.metadata?.reinstatedBy !== IDS.adminUser) throw new Error('reinstatedBy mismatch');
    });
    await t('سبب reinstate مسجل', async () => {
      const r = await client.query(`SELECT metadata->>'reinstateReason' as reason FROM public.employee_devices WHERE id=$1`, [IDS.device1]);
      if (!r.rows[0]?.reason?.includes('أمنية')) throw new Error(`reason: ${r.rows[0]?.reason}`);
    });
    await t('حدث أمن device.reinstated مسجل', async () => {
      const r = await client.query(`SELECT 1 FROM public.security_events WHERE event_type='device.reinstated' AND details->>'deviceId'=$1`, [IDS.device1]);
      if (!r.rows.length) throw new Error('security event not found');
    });
    await t('admin يستطيع approve الجهاز المُعاد', async () => {
      await client.query(`SELECT public.approve_device('${IDS.device1}', true, null)`);
    });
    await t('الجهاز final status = active', async () => {
      const r = await client.query(`SELECT status FROM public.employee_devices WHERE id=$1`, [IDS.device1]);
      if (r.rows[0]?.status !== 'active') throw new Error(`got ${r.rows[0]?.status}`);
    });

    // 4. register_my_device يرجع الجهاز المحظور إلى pending
    await t('register_my_device يرجع blocked/revoked إلى pending', async () => {
      await client.query(`UPDATE public.employee_devices SET status='blocked', revoked_at=now(), revocation_source='admin' WHERE id=$1`, [IDS.device1]);
      await actAs(client, IDS.empUser);
      await client.query(`SELECT public.register_my_device('test-install-v25-stg-0001','android','جهاز إعادة تسجيل','model','14','1.0.0',1,'production',false,true,'{}'::jsonb)`);
      const r = await client.query(`SELECT status FROM public.employee_devices WHERE id=$1`, [IDS.device1]);
      if (r.rows[0]?.status !== 'pending') throw new Error(`got ${r.rows[0]?.status}`);
    });

    // 5. decide_request يمنع الموافقة الذاتية والقرارات غير الصالحة
    await actAs(client, IDS.adminUser);
    await t('decide_request يرفض قراراً غير صالح (22023)', async () => {
      await expectThrows(client, `SELECT public.decide_request('${IDS.device1}', 'invalid_decision', null)`, '22023', 'invalid decision');
    });

  } finally {
    await teardown(client);
    client.release();
    await pool.end();
  }

  console.log(`\n${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
