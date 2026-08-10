-- =====================================================================
-- 0091: clear_must_change_password (migration 0228)
-- التحقق من أن الدالة تمحو must_change_password من app_metadata فقط
-- للمستخدم نفسه، وأن الأنون يُرفض، وأن الحقول الأخرى محفوظة.
-- 8 assertions
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(8);

-- =====================================================================
-- Fixture (superuser — قبل أي تبديل دور)
-- =====================================================================
do $fixture$
declare
  v_user_a uuid := 'c09a0000-0000-4000-8000-000000000001'; -- موظف بـ must_change_password
  v_user_b uuid := 'c09a0000-0000-4000-8000-000000000002'; -- موظف بدون must_change_password
begin
  insert into auth.users (id, email, aud, role, raw_app_meta_data) values
    (v_user_a, 'c09a-emp-a@test.local', 'authenticated', 'authenticated',
      '{"must_change_password": true, "provider": "email"}'::jsonb),
    (v_user_b, 'c09a-emp-b@test.local', 'authenticated', 'authenticated',
      '{"provider": "email"}'::jsonb);
end
$fixture$;

-- =====================================================================
-- الفئة 1: التحقق من وجود الدالة وأن anon يُرفض
-- =====================================================================

-- 1.1: الدالة موجودة
select has_function(
  'public', 'clear_must_change_password', ARRAY[]::text[],
  '1.1 الدالة clear_must_change_password موجودة'
);

-- 1.2: الأنون (auth.uid()=null) يُرفض بـ 28000
select throws_ok(
  $$select public.clear_must_change_password()$$,
  '28000', null,
  '1.2 الأنون (auth.uid()=null) يُرفض بـ 28000'
);

-- =====================================================================
-- الفئة 2: المستخدم A — يحمل must_change_password=true
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"c09a0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'c09a0000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

-- 2.1: الاستدعاء ينجح
select lives_ok(
  $$select public.clear_must_change_password()$$,
  '2.1 المستخدم المصادَق ينفّذ clear_must_change_password بنجاح'
);

-- التحقق من النتيجة (superuser)
reset role;

-- 2.2: must_change_password اختفت من app_metadata
select is(
  (select raw_app_meta_data ? 'must_change_password'
   from auth.users where id = 'c09a0000-0000-4000-8000-000000000001'),
  false,
  '2.2 مفتاح must_change_password محذوف من raw_app_meta_data'
);

-- 2.3: الحقول الأخرى محفوظة
select is(
  (select raw_app_meta_data ->> 'provider'
   from auth.users where id = 'c09a0000-0000-4000-8000-000000000001'),
  'email',
  '2.3 الحقول الأخرى في app_metadata محفوظة بعد الحذف'
);

-- =====================================================================
-- الفئة 3: idempotency — الاستدعاء مرة ثانية لا يُسبب خطأ
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"c09a0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'c09a0000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.clear_must_change_password()$$,
  '3.1 الاستدعاء الثاني idempotent — لا خطأ عند غياب المفتاح'
);

-- =====================================================================
-- الفئة 4: scope — لا يؤثر على مستخدم آخر
-- =====================================================================
reset role;

-- 4.1: المستخدم B لا يزال بدون must_change_password
select is(
  (select raw_app_meta_data ? 'must_change_password'
   from auth.users where id = 'c09a0000-0000-4000-8000-000000000002'),
  false,
  '4.1 raw_app_meta_data للمستخدم B لم يتغير'
);

-- =====================================================================
-- الفئة 5: المستخدم B — flag غائبة مسبقاً، idempotent
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"c09a0000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'c09a0000-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.clear_must_change_password()$$,
  '5.1 المستخدم بدون flag ينفّذ بنجاح (idempotent)'
);

reset role;
select * from finish();
rollback;
