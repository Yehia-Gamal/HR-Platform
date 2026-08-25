-- =====================================================================
-- 0472: عزل الإدارة الطبية — مصفوفة الرؤية والمسار الطبي
-- ---------------------------------------------------------------------
-- يثبت: علم العزل على القسم، المساعدات المركزية، الدليل المتبادل
-- (الموظف العادي لا يرى الطاقم الطبي والطاقم يرى قسمه ومديره فقط)،
-- قوائم ولوحة الحضور المخفاية، وتحوّل طلبات المعزولين إلى مسار
-- medical_leave_v1 أحادي الخطوة بينما العام يسير في مساره الاعتيادي.
-- كل شيء ضمن معاملة تُلغى (rollback).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(15);

-- =====================================================================
-- Fixture: كيان + قسمان (عادي / معزول) + موظفون وأدوار.
-- =====================================================================
do $fixture$
declare
  v_le   uuid := 'd4720000-0000-4000-8000-000000000001';
  v_dnrm uuid := 'd4720000-0000-4000-8000-000000000002';
  v_dmed uuid := 'd4720000-0000-4000-8000-000000000003';
begin
  insert into public.legal_entities(id, code, name) values(v_le, 'ISO-LE', 'كيان العزل');
  insert into public.departments(id, legal_entity_id, code, name, is_isolated) values
    (v_dnrm, v_le, 'ISO-NRM', 'إدارة عادية', false),
    (v_dmed, v_le, 'ISO-MED', 'الإدارة الطبية', true);

  insert into auth.users(id, email, aud, role) values
    ('d4720000-0000-4000-8000-000000000101','iso-e@test.local','authenticated','authenticated'),
    ('d4720000-0000-4000-8000-000000000102','iso-n@test.local','authenticated','authenticated'),
    ('d4720000-0000-4000-8000-000000000103','iso-m@test.local','authenticated','authenticated'),
    ('d4720000-0000-4000-8000-000000000104','iso-s@test.local','authenticated','authenticated'),
    ('d4720000-0000-4000-8000-000000000105','iso-s2@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,hire_date) values
    ('d4720000-0000-4000-8000-000000000201','d4720000-0000-4000-8000-000000000101','ISO-E','موظف عادي',v_dnrm,'active',true,current_date - 900),
    ('d4720000-0000-4000-8000-000000000202','d4720000-0000-4000-8000-000000000102','ISO-N','زميل عادي',v_dnrm,'active',true,current_date - 800),
    ('d4720000-0000-4000-8000-000000000203','d4720000-0000-4000-8000-000000000103','ISO-M','مصطفى أحمد',v_dmed,'active',true,current_date - 700),
    ('d4720000-0000-4000-8000-000000000204','d4720000-0000-4000-8000-000000000104','ISO-S','طبيب العيادة',v_dmed,'active',true,current_date - 600),
    ('d4720000-0000-4000-8000-000000000205','d4720000-0000-4000-8000-000000000105','ISO-S2','ممرض العيادة',v_dmed,'active',true,current_date - 500);

  insert into public.profiles(id, employee_id, status)
    select u, e, 'active' from (values
      ('d4720000-0000-4000-8000-000000000101'::uuid,'d4720000-0000-4000-8000-000000000201'::uuid),
      ('d4720000-0000-4000-8000-000000000102'::uuid,'d4720000-0000-4000-8000-000000000202'::uuid),
      ('d4720000-0000-4000-8000-000000000103'::uuid,'d4720000-0000-4000-8000-000000000203'::uuid),
      ('d4720000-0000-4000-8000-000000000104'::uuid,'d4720000-0000-4000-8000-000000000204'::uuid),
      ('d4720000-0000-4000-8000-000000000105'::uuid,'d4720000-0000-4000-8000-000000000205'::uuid)
    ) t(u,e);

  -- الإشراف الطبي: مصطفى مسؤول عن طاقم العيادات
  insert into public.manager_relations(employee_id, manager_employee_id, relation_type, effective_from) values
    ('d4720000-0000-4000-8000-000000000204','d4720000-0000-4000-8000-000000000203','primary',current_date),
    ('d4720000-0000-4000-8000-000000000205','d4720000-0000-4000-8000-000000000203','primary',current_date);

  insert into public.user_roles(user_id, role_id, effective_from)
    select t.u, r.id, now() - interval '1 year'
    from (values
      ('d4720000-0000-4000-8000-000000000101'::uuid,'employee'),
      ('d4720000-0000-4000-8000-000000000102'::uuid,'employee'),
      ('d4720000-0000-4000-8000-000000000103'::uuid,'clinics-manager'),
      ('d4720000-0000-4000-8000-000000000104'::uuid,'clinic-staff'),
      ('d4720000-0000-4000-8000-000000000105'::uuid,'clinic-staff')
    ) t(u,slug) join public.roles r on r.slug=t.slug;
end $fixture$;

create or replace function pg_temp.act_as_0472(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

create temp table pg_temp.t472(kind text primary key, id uuid) on commit drop;

-- =====================================================================
-- 1) البنية والمساعدات.
-- =====================================================================
select is(
  (select is_isolated from public.departments where code='ISO-MED'),
  true, 'قسم الإدارة الطبية معزول');
select is(
  (select public.is_employee_isolated('d4720000-0000-4000-8000-000000000204'::uuid)),
  true, 'طبيب العيادة معزول');
select is(
  (select public.is_employee_isolated('d4720000-0000-4000-8000-000000000201'::uuid)),
  false, 'موظف الإدارة العادية غير معزول');
select ok(
  (select count(*) from public.role_permissions rp join public.roles r on r.id=rp.role_id where r.slug='clinics-manager') > 0
  and (select count(*) from public.role_permissions rp join public.roles r on r.id=rp.role_id where r.slug='clinic-staff') > 0,
  'الدوران الجديدان ورثا صلاحياتهما');
select is(
  (select count(*)::int from public.workflow_steps ws
    join public.workflow_definitions d on d.id=ws.definition_id
   where d.code='medical_leave_v1' and ws.is_active=true),
  1, 'المسار الطبي بخطوة اعتماد واحدة فعّالة');

-- رؤية المعزول: المدير وزميل القسم فقط
select pg_temp.act_as_0472('d4720000-0000-4000-8000-000000000203');
select is(
  (select public.can_view_isolated_employee('d4720000-0000-4000-8000-000000000204'::uuid)),
  true, 'مسؤول العيادات يرى طاقمه المعزول');
select pg_temp.act_as_0472('d4720000-0000-4000-8000-000000000201');
select is(
  (select public.can_view_isolated_employee('d4720000-0000-4000-8000-000000000204'::uuid)),
  false, 'موظف خارجي لا يرى المعزولين');

-- =====================================================================
-- 2) الدليل المتبادل.
-- =====================================================================
select pg_temp.act_as_0472('d4720000-0000-4000-8000-000000000201'); -- موظف عادي
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_mobile_employee_directory(null,100)) x
     where x->>'id' in ('d4720000-0000-4000-8000-000000000203',
                        'd4720000-0000-4000-8000-000000000204',
                        'd4720000-0000-4000-8000-000000000205')
  ),
  'الدليل لا يعرض الإدارة الطبية للموظف العادي');

select pg_temp.act_as_0472('d4720000-0000-4000-8000-000000000104'); -- طبيب
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_mobile_employee_directory(null,100)) x
     where x->>'id' in ('d4720000-0000-4000-8000-000000000201',
                        'd4720000-0000-4000-8000-000000000202')
  ) and exists (
    select 1 from jsonb_array_elements(public.get_mobile_employee_directory(null,100)) x
     where x->>'id' = 'd4720000-0000-4000-8000-000000000203'
  ),
  'الطاقم الطبي يرى مديره ولا يرى عام الفريق');

-- =====================================================================
-- 3) قائمة ولوحة الحضور مخفيان عن الخارجيين.
-- =====================================================================
insert into public.attendance_daily(employee_id, work_date, status, is_finalized) values
  ('d4720000-0000-4000-8000-000000000201', (now() at time zone 'Africa/Cairo')::date, 'present', true),
  ('d4720000-0000-4000-8000-000000000204', (now() at time zone 'Africa/Cairo')::date, 'present', true);

select pg_temp.act_as_0472('d4720000-0000-4000-8000-000000000201');
select is(
  (select total from (
     select public.get_attendance_day_roster(
       (now() at time zone 'Africa/Cairo')::date, 'present', null,
       'd4720000-0000-4000-8000-000000000002') j
   ) x, jsonb_to_record(j) as t(total int) limit 1),
  1, 'قائمة حضور القسم العادي لا تتضمن الطاقم الطبي');

select is(
  (select public.get_attendance_dashboard(
     (now() at time zone 'Africa/Cairo')::date,
     'd4720000-0000-4000-8000-000000000002')->>'present')::int,
  1, 'لوحة الحضور للقسم العادي تحسب الموظف العادي فقط');

-- =====================================================================
-- 4) المسار: طلبات المعزول ← medical_leave_v1؛ والعادي ← مساره.
-- =====================================================================
select pg_temp.act_as_0472('d4720000-0000-4000-8000-000000000104');
set local role authenticated;
do $sub$
declare v_req public.requests;
begin
  v_req := public.submit_request('leave', null,
    'd4720000-0000-4000-8000-000000000203',
    'إجازة طبيب العيادة', 'اختبار المسار الطبي',
    jsonb_build_object('leaveType','annual'));
  insert into pg_temp.t472(kind, id) values('med', v_req.id);
end $sub$;

select is(
  (select d.code from public.requests r
    join public.workflow_definitions d on d.id=r.workflow_definition_id
   where r.id=(select id from pg_temp.t472 where kind='med')),
  'medical_leave_v1', 'طلب المعزول يسير بالمسار الطبي');
select is(
  (select count(*)::int from public.request_steps
   where request_id=(select id from pg_temp.t472 where kind='med')
     and status='active'),
  1, 'المسار الطبي خطوة نشطة واحدة');
select is(
  (select ws.approver_type from public.request_steps ws
   where ws.request_id=(select id from pg_temp.t472 where kind='med')),
  'direct_manager', 'خطوة المسار الطبي لمديره المباشر (مسؤول العيادات)');

reset role;
select pg_temp.act_as_0472('d4720000-0000-4000-8000-000000000201');
set local role authenticated;
do $sub2$
declare v_req public.requests;
begin
  v_req := public.submit_request('leave', null,
    'd4720000-0000-4000-8000-000000000202',
    'إجازة موظف عادي', 'اختبار المسار الاعتيادي',
    jsonb_build_object('leaveType','annual'));
  insert into pg_temp.t472(kind, id) values('nrm', v_req.id);
end $sub2$;

select is(
  (select count(*)::int from public.request_steps
   where request_id=(select id from pg_temp.t472 where kind='nrm')),
  2, 'الموظف العادي يسير في مساره الاعتيادي (خطوتان)');

reset role;
select * from finish();
rollback;