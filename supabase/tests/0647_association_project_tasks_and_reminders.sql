-- =====================================================================
-- 0647: مشاريع الجمعية — «مهامي» + تذكير مواعيد المهام + ترتيب الخطوات
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(22);

do $fixture$
declare
  v_jt   uuid := 'f6470000-0000-4000-8000-000000000004';
  v_role uuid;
begin
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0647', 'وظيفة 0647');
  insert into auth.users(id, email, aud, role) values
    ('f6470000-0000-4000-8000-000000000020', 'admin-0647@test.local', 'authenticated', 'authenticated'),
    ('f6470000-0000-4000-8000-000000000021', 'lead-0647@test.local',  'authenticated', 'authenticated'),
    ('f6470000-0000-4000-8000-000000000022', 'memb-0647@test.local',  'authenticated', 'authenticated'),
    ('f6470000-0000-4000-8000-000000000023', 'out-0647@test.local',   'authenticated', 'authenticated');
  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164) values
    ('f6470000-0000-4000-8000-000000000010', 'f6470000-0000-4000-8000-000000000020', 'E-0647-0', 'مدير تنفيذي 0647', null, v_jt, 'active', true, current_date - 900, '+201000006470'),
    ('f6470000-0000-4000-8000-000000000011', 'f6470000-0000-4000-8000-000000000021', 'E-0647-1', 'قائد 0647',        null, v_jt, 'active', true, current_date - 500, '+201000006471'),
    ('f6470000-0000-4000-8000-000000000012', 'f6470000-0000-4000-8000-000000000022', 'E-0647-2', 'عضو 0647',         null, v_jt, 'active', true, current_date - 400, '+201000006472'),
    ('f6470000-0000-4000-8000-000000000013', 'f6470000-0000-4000-8000-000000000023', 'E-0647-3', 'غريب 0647',        null, v_jt, 'active', true, current_date - 300, '+201000006473');
  insert into public.profiles(id, employee_id, status) values
    ('f6470000-0000-4000-8000-000000000020', 'f6470000-0000-4000-8000-000000000010', 'active'),
    ('f6470000-0000-4000-8000-000000000021', 'f6470000-0000-4000-8000-000000000011', 'active'),
    ('f6470000-0000-4000-8000-000000000022', 'f6470000-0000-4000-8000-000000000012', 'active'),
    ('f6470000-0000-4000-8000-000000000023', 'f6470000-0000-4000-8000-000000000013', 'active');
  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin-0647', 'أدمن 0647', 'Admin 0647', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0647';
  insert into public.user_roles(user_id, role_id)
    values ('f6470000-0000-4000-8000-000000000020', v_role) on conflict do nothing;
end $fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

create or replace function pg_temp.pid() returns uuid language sql stable as $f$
  select nullif(current_setting('t0647.p', true), '')::uuid
$f$;
create or replace function pg_temp.sid(p_title text) returns uuid language sql stable as $f$
  select nullif(current_setting('t0647.' || p_title, true), '')::uuid
$f$;

-- =====================================================================
-- التجهيز: المدير التنفيذي ينشئ مشروعاً معتمداً بقائد وعضو + 4 خطوات
-- =====================================================================
select pg_temp.act_as('f6470000-0000-4000-8000-000000000020');
set local role authenticated;
select set_config('t0647.p', public.save_association_project(null, 'مشروع مهام 0647', null, 'high', null, null,
  'f6470000-0000-4000-8000-000000000011', array['f6470000-0000-4000-8000-000000000012']::uuid[], '{}'::uuid[])::text, false);
select set_config('t0647.a', public.upsert_project_step_admin(pg_temp.pid(), null, 'غداً', null, null, 'pending',
  (now() at time zone 'Africa/Cairo')::date + 1, 'f6470000-0000-4000-8000-000000000012')::text, false);
select set_config('t0647.b', public.upsert_project_step_admin(pg_temp.pid(), null, 'متأخرة', null, null, 'in_progress',
  (now() at time zone 'Africa/Cairo')::date - 5, 'f6470000-0000-4000-8000-000000000012')::text, false);
select set_config('t0647.c', public.upsert_project_step_admin(pg_temp.pid(), null, 'بلا مكلف', null, null, 'pending',
  (now() at time zone 'Africa/Cairo')::date - 5, null)::text, false);
select set_config('t0647.d', public.upsert_project_step_admin(pg_temp.pid(), null, 'منجزة', null, null, 'done',
  (now() at time zone 'Africa/Cairo')::date - 5, 'f6470000-0000-4000-8000-000000000012')::text, false);
reset role;

-- =====================================================================
-- 1) الصلاحيات
-- =====================================================================
select is(has_function_privilege('authenticated', 'public.notify_project_step_deadlines()', 'EXECUTE'),
  false, 'كرون التذكير غير قابل للاستدعاء من العميل');
select is(has_function_privilege('anon', 'public.get_my_project_tasks()', 'EXECUTE'), false, 'anon لا يقرأ مهامي');
select is(has_function_privilege('authenticated', 'public.move_project_step(uuid,text)', 'EXECUTE'), true, 'authenticated يرتّب الخطوات');

-- =====================================================================
-- 2) مهامي
-- =====================================================================
select pg_temp.act_as('f6470000-0000-4000-8000-000000000022');
set local role authenticated;
select is(jsonb_array_length(public.get_my_project_tasks()), 2, 'العضو يرى مهمتيه المفتوحتين فقط (لا المنجزة)');
select is(public.get_my_project_tasks() -> 0 ->> 'title', 'متأخرة', 'الأقرب موعداً (المتأخرة) أولاً');
select is((public.get_my_project_tasks() -> 0 ->> 'isOverdue')::boolean, true, 'المتأخرة معلَّمة');
select is((public.get_my_project_tasks() -> 1 ->> 'isDueSoon')::boolean, true, 'مهمة الغد «قريبة الموعد»');
select is(public.get_my_project_tasks() -> 0 ->> 'projectName', 'مشروع مهام 0647', 'اسم المشروع مرفق');
reset role;

select pg_temp.act_as('f6470000-0000-4000-8000-000000000023');
set local role authenticated;
select is(jsonb_array_length(public.get_my_project_tasks()), 0, 'الغريب بلا مهام');
select throws_ok($$ select public.move_project_step(pg_temp.sid('a'), 'down') $$, '42501', null, 'الغريب لا يرتّب الخطوات');
reset role;

-- =====================================================================
-- 3) التذكير: مرة واحدة، والقائد أول مرة فقط، ولا يُحسب نشاطاً
-- =====================================================================
update public.association_projects set last_activity_at = now() - interval '2 days' where id = pg_temp.pid();

select is(public.notify_project_step_deadlines(), 2, 'تذكيران: مهمة الغد + المتأخرة (لا المنجزة ولا بلا مكلف)');
select ok(exists (select 1 from public.notifications
                   where recipient_user_id = 'f6470000-0000-4000-8000-000000000022' and metadata ->> 'kind' = 'project_step_due'),
  'المكلَّف يُذكَّر بموعد الغد');
select ok(exists (select 1 from public.notifications
                   where recipient_user_id = 'f6470000-0000-4000-8000-000000000022' and metadata ->> 'kind' = 'project_step_overdue'),
  'المكلَّف يُذكَّر بالمتأخرة');
select is((select count(*)::int from public.notifications
            where recipient_user_id = 'f6470000-0000-4000-8000-000000000021' and metadata ->> 'kind' = 'project_step_overdue'),
  1, 'القائد يُشعَر بالتأخر');
select is(public.notify_project_step_deadlines(), 0, 'لا تكرار في نفس اليوم');
select ok((select last_activity_at < now() - interval '1 day' from public.association_projects where id = pg_temp.pid()),
  'التذكير لا يُحسب نشاطاً ولا يُطفئ الأحمر');

update public.association_project_steps set reminded_on = (now() at time zone 'Africa/Cairo')::date - 3 where id = pg_temp.sid('b');
select is(public.notify_project_step_deadlines(), 1, 'المتأخرة يُعاد تذكيرها بعد 3 أيام');
select is((select count(*)::int from public.notifications
            where recipient_user_id = 'f6470000-0000-4000-8000-000000000021' and metadata ->> 'kind' = 'project_step_overdue'),
  1, 'القائد لا يُشعَر مرة ثانية');

-- =====================================================================
-- 4) ترتيب الخطوات
-- =====================================================================
select pg_temp.act_as('f6470000-0000-4000-8000-000000000021');
set local role authenticated;
select lives_ok($$ select public.move_project_step(pg_temp.sid('c'), 'up') $$, 'القائد يحرّك خطوة لأعلى');
select lives_ok($$ select public.move_project_step(pg_temp.sid('a'), 'up') $$, 'تحريك الأولى لأعلى لا يفعل شيئاً');
select throws_ok($$ select public.move_project_step(pg_temp.sid('a'), 'left') $$, '22023', null, 'اتجاه غير صحيح يُرفض');
reset role;

select is(
  (select string_agg(title, ',' order by sort_order) from public.association_project_steps where project_id = pg_temp.pid()),
  'غداً,بلا مكلف,متأخرة,منجزة', 'الترتيب بعد التحريك صحيح');

select * from finish();
rollback;
