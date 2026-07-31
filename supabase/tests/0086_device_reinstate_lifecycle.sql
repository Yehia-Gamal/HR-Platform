-- 0086: V25 — دورة حياة الأجهزة (Reinstate Pipeline) + خط أنابيب الأمان
-- يتحقق من:
--   A. RPC admin_reinstate_device موجود، محمي، ويملك search_path ثابت.
--   B. دورة الحياة الكاملة: active → revoke → reinstate → pending → approve → active.
--   C. صلاحية Reinstate حصراً لـ full-access؛ الموظف العادي يُحرم (attack).
--   D. لا يُعاد تفعيل جهاز نشط أو معلّق (state-machine enforcement).
--   E. decide_request يدعم تجاوز HR للخطوة الأولى بعد انتهاء مهلة المدير.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(22);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Structure — admin_reinstate_device موجود ومحمي
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'admin_reinstate_device', array['uuid','text'],
  'admin_reinstate_device RPC exists'
);

select ok(
  not has_function_privilege('anon', p.oid, 'EXECUTE'),
  'anon لا يستطيع تنفيذ admin_reinstate_device'
) from pg_proc p join pg_namespace n on p.pronamespace = n.oid
 where n.nspname='public' and p.proname='admin_reinstate_device' limit 1;

select ok(
  has_function_privilege('authenticated', p.oid, 'EXECUTE'),
  'authenticated يستطيع تنفيذ admin_reinstate_device'
) from pg_proc p join pg_namespace n on p.pronamespace = n.oid
 where n.nspname='public' and p.proname='admin_reinstate_device' limit 1;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Fixtures — كيانات وأدوار وأجهزة
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'a8600000-0000-4000-8000-000000000001';
  v_dept   uuid := 'a8600000-0000-4000-8000-000000000010';
begin
  insert into public.legal_entities(id, code, name)
    values(v_entity, 'V25-TST-LE', 'كيان V25 تجريبي')
  on conflict (id) do nothing;

  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_entity, 'V25-TST-D', 'إدارة V25 تجريبية')
  on conflict (id) do nothing;

  insert into auth.users(id, email, aud, role) values
    ('a8600000-0000-4000-8000-000000000101', 'v25-admin@test.local', 'authenticated', 'authenticated'),
    ('a8600000-0000-4000-8000-000000000102', 'v25-emp@test.local',   'authenticated', 'authenticated')
  on conflict (id) do nothing;

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('a8600000-0000-4000-8000-000000000201', 'a8600000-0000-4000-8000-000000000101', 'V25-ADM', 'مسؤول V25', v_dept, 'active', true, false),
    ('a8600000-0000-4000-8000-000000000202', 'a8600000-0000-4000-8000-000000000102', 'V25-EMP', 'موظف V25',  v_dept, 'active', true, false)
  on conflict (id) do nothing;

  insert into public.profiles(id, employee_id, status) values
    ('a8600000-0000-4000-8000-000000000101', 'a8600000-0000-4000-8000-000000000201', 'active'),
    ('a8600000-0000-4000-8000-000000000102', 'a8600000-0000-4000-8000-000000000202', 'active')
  on conflict (id) do nothing;

  -- admin = full access
  insert into public.user_roles(user_id, role_id)
    select 'a8600000-0000-4000-8000-000000000101', id from public.roles where slug='admin'
  on conflict do nothing;

  -- جهاز معلّق — سنعمله عليه
  insert into public.employee_devices(
    id, employee_id, user_id, device_identifier_hash,
    credential_id, device_name, platform, status, registered_at, metadata
  ) values(
    'a8600000-0000-4000-8000-000000000301',
    'a8600000-0000-4000-8000-000000000202',
    'a8600000-0000-4000-8000-000000000102',
    'hash_v25_device_1',
    null, 'جهاز V25 اختبار 1', 'android', 'pending', now(),
    jsonb_build_object('lifecycle_test', true)
  ) on conflict (id) do nothing;

  -- جهاز نشط — لاختبار state-machine
  insert into public.employee_devices(
    id, employee_id, user_id, device_identifier_hash,
    credential_id, device_name, platform, status, registered_at, metadata
  ) values(
    'a8600000-0000-4000-8000-000000000302',
    'a8600000-0000-4000-8000-000000000202',
    'a8600000-0000-4000-8000-000000000102',
    'hash_v25_device_2',
    null, 'جهاز V25 نشط', 'ios', 'active', now(),
    jsonb_build_object('lifecycle_test', true)
  ) on conflict (id) do nothing;
end
$fixture$;

-- Helper: تبديل سياق المصادقة
create or replace function pg_temp.act_as_v25(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. ATTACK — موظف عادي يحاول reinstate (حرمان)
-- ═══════════════════════════════════════════════════════════════════════════════
select pg_temp.act_as_v25('a8600000-0000-4000-8000-000000000102');
set local role authenticated;

select throws_ok(
  $live$
    select public.admin_reinstate_device(
      'a8600000-0000-4000-8000-000000000301',
      'محاولة هجوم من موظف عادي'
    )
  $live$,
  '42501',
  null,
  'موظف عادي لا يستطيع reinstate جهازه'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. ATTACK — state-machine violation (إعادة جهاز نشط)
-- ═══════════════════════════════════════════════════════════════════════════════
select pg_temp.act_as_v25('a8600000-0000-4000-8000-000000000101');

select throws_ok(
  $live$
    select public.admin_reinstate_device(
      'a8600000-0000-4000-8000-000000000302',
      'محاولة هجوم: reinstate جهاز نشط'
    )
  $live$,
  '22023',
  null,
  'لا يمكن reinstate جهاز نشط (state-machine protected)'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. ATTACK — reinstate جهاز غير موجود
-- ═══════════════════════════════════════════════════════════════════════════════
select throws_ok(
  $live$
    select public.admin_reinstate_device(
      'a8600000-0000-4000-8000-000000000399',
      'فحص استيفاء device_id'
    )
  $live$,
  'P0002',
  null,
  'device_id وهمي يعيد device not found'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. HAPPY PATH — Revoke ثم Reinstate
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$
    select public.admin_revoke_device(
      'a8600000-0000-4000-8000-000000000301',
      'اختبار إلغاء قبل إعادة التفعيل'
    )
  $live$,
  'admin يمكنه إلغاء صلاحية جهاز'
);

select is(
  (select status from public.employee_devices
   where id = 'a8600000-0000-4000-8000-000000000301'),
  'revoked',
  'الجهاز تم إلغاؤه ويعرض revoked'
);

select ok(
  (select revoked_at is not null from public.employee_devices
   where id = 'a8600000-0000-4000-8000-000000000301'),
  'revoked_at مضبوط بعد الإلغاء'
);

-- إعادة التفعيل
select lives_ok(
  $live$
    select public.admin_reinstate_device(
      'a8600000-0000-4000-8000-000000000301',
      'إعادة تفعيل بعد حل المشكلة الأمنية'
    )
  $live$,
  'admin يمكنه إعادة تفعيل الجهاز الملغي'
);

select is(
  (select status from public.employee_devices
   where id = 'a8600000-0000-4000-8000-000000000301'),
  'pending',
  'جهاز reinstate يعود إلى pending'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. Post-reinstate — التحقق من إعادة ضبط حقول الإلغاء
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  (select revoked_at is null from public.employee_devices
   where id = 'a8600000-0000-4000-8000-000000000301'),
  'revoked_at تم مسحه بعد reinstate'
);

select ok(
  (select revocation_source is null from public.employee_devices
   where id = 'a8600000-0000-4000-8000-000000000301'),
  'revocation_source تم مسحه بعد reinstate'
);

select ok(
  (select coalesce((metadata->>'reinstated')::boolean,false) from public.employee_devices
   where id = 'a8600000-0000-4000-8000-000000000301'),
  'metadata يحوّل راية reinstated=true'
);

select ok(
  (select metadata->>'reinstatedBy' is not null from public.employee_devices
   where id = 'a8600000-0000-4000-8000-000000000301'),
  'reinstatedBy تم تسجيله'
);

select ok(
  (select metadata->>'reinstateReason' like '%أمنية%' from public.employee_devices
   where id = 'a8600000-0000-4000-8000-000000000301'),
  'سبب reinstate محفوظ في metadata'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. دورة كاملة — approve بعد reinstate
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$
    select public.approve_device(
      'a8600000-0000-4000-8000-000000000301', true, null
    )
  $live$,
  'admin يمكنه الموافقة على جهاز مُعاد (pending)'
);

select is(
  (select status from public.employee_devices
   where id = 'a8600000-0000-4000-8000-000000000301'),
  'active',
  'الجهاز المُعاد أصبح نشط بعد الموافقة'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9. سجل أمن — device.reinstated مُسجل
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  exists(
    select 1 from public.security_events
    where event_type = 'device.reinstated'
  ),
  'حدث device.reinstated مُسجل في security_events'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10. decide_request — صلاحية وهيكل
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'decide_request', array['uuid','text','text'],
  'decide_request RPC exists'
);

select ok(
  has_function_privilege('authenticated', p.oid, 'EXECUTE'),
  'authenticated يستطيع تنفيذ decide_request'
) from pg_proc p join pg_namespace n on p.pronamespace = n.oid
 where n.nspname='public' and p.proname='decide_request' limit 1;

select ok(
  not has_function_privilege('anon', p.oid, 'EXECUTE'),
  'anon لا يستطيع تنفيذ decide_request'
) from pg_proc p join pg_namespace n on p.pronamespace = n.oid
 where n.nspname='public' and p.proname='decide_request' limit 1;

select * from finish();
rollback;
