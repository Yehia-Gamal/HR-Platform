-- =====================================================================
-- 0554: لوحة قرار التعليق (get_pending_suspensions / suspend_employee_for_penalty)
-- ---------------------------------------------------------------------
-- يثبت:
--   1) anon والموظف العادي محجوبان عن الدالتين
--   2) full-access يرى المستحق للتعليق
--   3) السبب إلزامي
--   4) القرار يعلّق فعلاً (الغرامة + الموظف) ويُسجَّل كقرار بشري
--   5) القائمة تفرغ بعد القرار، ولا يُعلَّق الموظف مرتين
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(12);

-- =====================================================================
-- Fixture: A = full-access، E = موظف عادي، X = مستهدف بغرامة مضاعفة متأخرة
-- =====================================================================
do $fixture$
declare
  v_le     uuid := 'f5540000-0000-4000-8000-000000000001';
  v_dept   uuid := 'f5540000-0000-4000-8000-000000000002';
  v_jt     uuid := 'f5540000-0000-4000-8000-000000000003';
  v_a      uuid := 'f5540000-0000-4000-8000-000000000011';
  v_e      uuid := 'f5540000-0000-4000-8000-000000000012';
  v_x      uuid := 'f5540000-0000-4000-8000-000000000013';
  v_user_a uuid := 'f5540000-0000-4000-8000-000000000021';
  v_user_e uuid := 'f5540000-0000-4000-8000-000000000022';
  v_role   uuid;
  v_date   date := current_date - 5;
begin
  -- الجمعة والعطلات معفاة — نختار يوم عمل مضموناً (انظر 0550)
  while extract(isodow from v_date)::integer = 5
     or exists (select 1 from public.public_holidays where holiday_date = v_date) loop
    v_date := v_date - 1;
  end loop;

  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0554', 'كيان 0554');
  insert into public.departments(id, legal_entity_id, code, name) values (v_dept, v_le, 'D-0554', 'إدارة 0554');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0554', 'وظيفة 0554');

  insert into auth.users(id, email, aud, role) values
    (v_user_a, 'admin-0554@test.local', 'authenticated', 'authenticated'),
    (v_user_e, 'emp-0554@test.local',   'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164)
  values
    (v_a, v_user_a, 'E-0554-A', 'مسؤول 0554', v_dept, v_jt, 'active', true, current_date - 500, '+201000005540'),
    (v_e, v_user_e, 'E-0554-E', 'موظف 0554',  v_dept, v_jt, 'active', true, current_date - 300, '+201000005541'),
    (v_x, null,     'E-0554-X', 'مستهدف 0554', v_dept, v_jt, 'active', true, current_date - 200, '+201000005542');

  insert into public.profiles(id, employee_id, status) values
    (v_user_a, v_a, 'active'),
    (v_user_e, v_e, 'active');

  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin-0554', 'أدمن 0554', 'Admin 0554', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0554';
  insert into public.user_roles(user_id, role_id) values (v_user_a, v_role) on conflict do nothing;

  insert into public.instant_attendance_penalties(
    id, employee_id, work_date, late_minutes, original_amount, current_amount, status, escalation_level)
  values ('f5540000-0000-4000-8000-000000000031', v_x, v_date, 20, 20.00, 500.00, 'doubled', 'doubled');
end $fixture$;

-- =====================================================================
-- 1) anon والموظف العادي محجوبان
-- =====================================================================
select is(pg_catalog.has_function_privilege('anon', 'public.get_pending_suspensions()', 'EXECUTE'), false,
  'anon محجوب: get_pending_suspensions');
select is(pg_catalog.has_function_privilege('anon', 'public.suspend_employee_for_penalty(uuid,text)', 'EXECUTE'), false,
  'anon محجوب: suspend_employee_for_penalty');

do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5540000-0000-4000-8000-000000000022","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',  'f5540000-0000-4000-8000-000000000022', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;
set local role authenticated;

select throws_ok($rt$ select public.get_pending_suspensions() $rt$, '42501',
  'الموظف العادي لا يرى قائمة المستحقين');
select throws_ok(
  $rt$ select public.suspend_employee_for_penalty('f5540000-0000-4000-8000-000000000031', 'محاولة غير مخوّلة') $rt$,
  '42501',
  'الموظف العادي لا يعلّق أحداً');

reset role;

-- =====================================================================
-- 2) full-access: يرى المستحق، والسبب إلزامي، والقرار يُنفَّذ
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5540000-0000-4000-8000-000000000021","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',  'f5540000-0000-4000-8000-000000000021', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;
set local role authenticated;

select is(
  (select count(*)::int from jsonb_array_elements(public.get_pending_suspensions()) x
    where x->>'penaltyId' = 'f5540000-0000-4000-8000-000000000031'),
  1,
  'full-access يرى الغرامة المستحقة للتعليق');

select throws_ok(
  $rt$ select public.suspend_employee_for_penalty('f5540000-0000-4000-8000-000000000031', ' ') $rt$,
  '22023',
  'السبب إلزامي');

select lives_ok(
  $rt$ select public.suspend_employee_for_penalty('f5540000-0000-4000-8000-000000000031', 'عدم سداد بعد المهلة') $rt$,
  'full-access ينفّذ قرار التعليق');

reset role;

select is(
  (select status from public.instant_attendance_penalties where id = 'f5540000-0000-4000-8000-000000000031'),
  'suspended',
  'الغرامة انتقلت إلى suspended');

select is(
  (select status from public.employees where id = 'f5540000-0000-4000-8000-000000000013'),
  'suspended',
  'الموظف عُلِّق فعلاً');

select ok(exists(
  select 1 from public.audit_events
   where event_type = 'instant_penalty.suspended'
     and target_id = 'f5540000-0000-4000-8000-000000000031'
     and (metadata->>'manualDecision')::boolean is true
     and description = 'عدم سداد بعد المهلة'),
  'سُجِّل القرار البشري مع سببه');

do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5540000-0000-4000-8000-000000000021","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',  'f5540000-0000-4000-8000-000000000021', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;
set local role authenticated;

select is(
  (select count(*)::int from jsonb_array_elements(public.get_pending_suspensions()) x
    where x->>'penaltyId' = 'f5540000-0000-4000-8000-000000000031'),
  0,
  'القائمة تفرغ بعد القرار');

select throws_ok(
  $rt$ select public.suspend_employee_for_penalty('f5540000-0000-4000-8000-000000000031', 'تكرار القرار') $rt$,
  '22023',
  'لا يُعلَّق مرتين');

reset role;

select * from finish();
rollback;
