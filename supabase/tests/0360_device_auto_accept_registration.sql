-- 0360: V36 — القبول التلقائي لتسجيل الأجهزة (register_my_device)
-- يتحقق من:
--   A. register_my_device موجود ومحمي (authenticated فقط).
--   B. تسجيل جهاز محلي جديد يُنشئ employee_devices بحالة active + approved_at.
--   C. إعادة التسجيل (upsert) تُبقي الحالة active وتحفظ approved_at.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(9);

-- ═══════════════════════════════════════════════════════════════════════════════
-- A. Structure — موجود ومحمي
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'register_my_device',
  array['text','text','text','text','text','text','integer','text','boolean','boolean','jsonb'],
  'register_my_device RPC exists'
);

select ok(
  not has_function_privilege('anon', p.oid, 'EXECUTE'),
  'anon لا يستطيع تنفيذ register_my_device'
) from pg_proc p join pg_namespace n on p.pronamespace = n.oid
 where n.nspname='public' and p.proname='register_my_device' limit 1;

select ok(
  has_function_privilege('authenticated', p.oid, 'EXECUTE'),
  'authenticated يستطيع تنفيذ register_my_device'
) from pg_proc p join pg_namespace n on p.pronamespace = n.oid
 where n.nspname='public' and p.proname='register_my_device' limit 1;

-- ═══════════════════════════════════════════════════════════════════════════════
-- B. Fixtures — كيان وإدارة وموظف
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'a9000000-0000-4000-8000-000000000001';
  v_dept   uuid := 'a9000000-0000-4000-8000-000000000010';
begin
  insert into public.legal_entities(id, code, name)
    values(v_entity, 'V36-TST-LE', 'كيان V36 تجريبي')
  on conflict (id) do nothing;

  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_entity, 'V36-TST-D', 'إدارة V36 تجريبية')
  on conflict (id) do nothing;

  insert into auth.users(id, email, aud, role) values
    ('a9000000-0000-4000-8000-000000000101', 'v36-emp@test.local', 'authenticated', 'authenticated')
  on conflict (id) do nothing;

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('a9000000-0000-4000-8000-000000000201', 'a9000000-0000-4000-8000-000000000101', 'V36-EMP', 'موظف V36', v_dept, 'active', true, false)
  on conflict (id) do nothing;

  insert into public.profiles(id, employee_id, status) values
    ('a9000000-0000-4000-8000-000000000101', 'a9000000-0000-4000-8000-000000000201', 'active')
  on conflict (id) do nothing;
end
$fixture$;

-- Helper: تبديل سياق المصادقة
create or replace function pg_temp.act_as_v36(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

select pg_temp.act_as_v36('a9000000-0000-4000-8000-000000000101');
set local role authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- C. HAPPY PATH — تسجيل جهاز جديد → active + approved_at
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$
    select public.register_my_device(
      'inst-0360-auto-accept-0001',
      'android',
      'جهاز اختبار 0360',
      'Pixel Test',
      '15',
      '0.12.2',
      16,
      'development',
      false,
      true,
      jsonb_build_object('pgTAP', true)
    )
  $live$,
  'تسجيل جهاز محلي جديد ينجح'
);

select is(
  (select status from public.employee_devices
    where employee_id = 'a9000000-0000-4000-8000-000000000201'
      and device_identifier_hash = encode(
        digest(convert_to('inst-0360-auto-accept-0001', 'UTF8'), 'sha256'), 'hex')
    limit 1),
  'active',
  'الجهاز المحلي يُقبل تلقائياً بحالة active'
);

select ok(
  (select approved_at is not null from public.employee_devices
    where employee_id = 'a9000000-0000-4000-8000-000000000201'
      and device_identifier_hash = encode(
        digest(convert_to('inst-0360-auto-accept-0001', 'UTF8'), 'sha256'), 'hex')
    limit 1),
  'approved_at مضبوط على القبول التلقائي'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- D. إعادة التسجيل (upsert) — تبقى active وتحفظ approved_at
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$
    select public.register_my_device(
      'inst-0360-auto-accept-0001',
      'android',
      'جهاز اختبار 0360 (محدّث)',
      'Pixel Test',
      '16',
      '0.12.3',
      17,
      'development',
      false,
      true,
      jsonb_build_object('pgTAP', true)
    )
  $live$,
  'إعادة تسجيل الجهاز نفسه تنجح'
);

select is(
  (select status from public.employee_devices
    where employee_id = 'a9000000-0000-4000-8000-000000000201'
      and device_identifier_hash = encode(
        digest(convert_to('inst-0360-auto-accept-0001', 'UTF8'), 'sha256'), 'hex')
    limit 1),
  'active',
  'إعادة التسجيل تُبقي الجهاز active'
);

select ok(
  (select approved_at is not null from public.employee_devices
    where employee_id = 'a9000000-0000-4000-8000-000000000201'
      and device_identifier_hash = encode(
        digest(convert_to('inst-0360-auto-accept-0001', 'UTF8'), 'sha256'), 'hex')
    limit 1),
  'إعادة التسجيل تحافظ على approved_at'
);

select finish();
rollback;
