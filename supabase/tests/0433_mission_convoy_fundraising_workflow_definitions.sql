-- =====================================================================
-- 0433: استعادة تعريفات سير الاعتماد المفقودة (migration 0433)
-- ---------------------------------------------------------------------
-- يثبت:
--   1. تعريفات mission/convoy/fundraising/late_permit/early_permit موجودة
--      (is_default + is_active) بنسق two-tier.
--   2. كل تعريف له خطوتان نشطتان: مدير مباشر ثم مشرف عمليات 1.
--   3. تقديم مأمورية عبر submit_my_request ينشئ خطوات السير فعلياً
--      (الخطوة 1 نشطة بمعيّن = المدير، الخطوة 2 معلقة بدور العمليات)
--      + مثيل سير running — أي لا تعلق الطلبات بعد الآن.
--   4. نفس الشيء لإذن الحضور (late_permit).
-- كل شيء ضمن معاملة تُلغى (rollback).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(11);

-- =====================================================================
-- 1) التعريفات موجودة للأنواع الخمسة
-- =====================================================================
select results_eq(
  $$ select count(*) from public.workflow_definitions
     where request_type in ('mission','convoy','fundraising','late_permit','early_permit')
       and is_default and is_active $$,
  $$ values (5::bigint) $$,
  '1. تعريفات الأنواع الخمسة موجودة ونشطة وافتراضية'
);

-- 2) كل تعريف له خطوتان نشطتان (مدير مباشر ثم عمليات)
select results_eq(
  $$ select count(*) from public.workflow_steps ws
     join public.workflow_definitions d on d.id = ws.definition_id
     where d.request_type in ('mission','convoy','fundraising','late_permit','early_permit')
       and d.is_default and d.is_active and ws.is_active $$,
  $$ values (10::bigint) $$,
  '2. كل تعريف له خطوتان نشطتان (10 خطوات إجمالاً)'
);

-- 3) الخطوة 1 في كل تعريف: المدير المباشر
select results_eq(
  $$ select count(distinct ws.definition_id) from public.workflow_steps ws
     join public.workflow_definitions d on d.id = ws.definition_id
     where d.request_type in ('mission','convoy','fundraising','late_permit','early_permit')
       and d.is_default and d.is_active and ws.is_active
       and ws.step_order = 1 and ws.approver_type = 'direct_manager' $$,
  $$ values (5::bigint) $$,
  '3. الخطوة الأولى في كل التعريفات هي موافقة المدير المباشر'
);

-- 4) الخطوة 2 في كل تعريف: مشرف العمليات 1
select results_eq(
  $$ select count(distinct ws.definition_id) from public.workflow_steps ws
     join public.workflow_definitions d on d.id = ws.definition_id
     where d.request_type in ('mission','convoy','fundraising','late_permit','early_permit')
       and d.is_default and d.is_active and ws.is_active
       and ws.step_order = 2 and ws.approver_role_slug = 'operations-manager-1' $$,
  $$ values (5::bigint) $$,
  '4. الخطوة الثانية في كل التعريفات هي موافقة مشرف العمليات 1'
);

-- =====================================================================
-- 5) Fixture: كيان + إدارة + مدير + موظف + مستخدمان (بنمط 0108)
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'b4330000-0000-4000-8000-000000000001';
  v_dept uuid := 'b4330000-0000-4000-8000-000000000002';
begin
  insert into public.legal_entities(id, code, name) values(v_le, '433-LE', 'كيان تعريفات 0433');
  insert into public.departments(id, legal_entity_id, code, name) values
    (v_dept, v_le, '433-D', 'إدارة 0433');

  insert into auth.users(id, email, aud, role) values
    ('b4330000-0000-4000-8000-000000000003','t433-mgr@test.local','authenticated','authenticated'),
    ('b4330000-0000-4000-8000-000000000004','t433-emp@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
  values
    ('b4330000-0000-4000-8000-000000000011','b4330000-0000-4000-8000-000000000003','T433-MGR','مدير 0433',v_dept,'active',true,'1980-01-01','2015-01-01'),
    ('b4330000-0000-4000-8000-000000000012','b4330000-0000-4000-8000-000000000004','T433-EMP','موظف 0433',v_dept,'active',true,'1995-01-01','2023-01-01');

  insert into public.profiles(id, employee_id, status) values
    ('b4330000-0000-4000-8000-000000000003','b4330000-0000-4000-8000-000000000011','active'),
    ('b4330000-0000-4000-8000-000000000004','b4330000-0000-4000-8000-000000000012','active');

  insert into public.user_roles(user_id, role_id)
  select t.u, r.id from (values
    ('b4330000-0000-4000-8000-000000000003'::uuid,'employee'),
    ('b4330000-0000-4000-8000-000000000003'::uuid,'direct-manager'),
    ('b4330000-0000-4000-8000-000000000004'::uuid,'employee')
  ) as t(u,slug) join public.roles r on r.slug=t.slug;

  insert into public.manager_relations(employee_id, manager_employee_id, relation_type)
  values('b4330000-0000-4000-8000-000000000012','b4330000-0000-4000-8000-000000000011','primary');
end $fixture$;

do $set_emp$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"b4330000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','b4330000-0000-4000-8000-000000000004', true);
end $set_emp$;

-- =====================================================================
-- 6) تقديم مأمورية → تنشأ خطوات السير (لا تعلق)
-- =====================================================================
select lives_ok($$
  select public.submit_my_request('mission','مأمورية اختبار 0433','تسليم مستندات رسمية',
    jsonb_build_object(
      'startDate', to_char(current_date + 10, 'YYYY-MM-DD'),
      'endDate',   to_char(current_date + 10, 'YYYY-MM-DD'),
      'location',  'مقر الجهة المستلمة'))
$$, '6. تقديم مأمورية عبر submit_my_request ينجح');

select results_eq(
  $$ select count(*) from public.request_steps s
     join public.requests r on r.id = s.request_id
     where r.employee_id = 'b4330000-0000-4000-8000-000000000012'
       and r.request_type = 'mission' $$,
  $$ values (2::bigint) $$,
  '7. المأمورية الجديدة لها خطوتا سير'
);

select results_eq(
  $$ select s.status, s.assignee_employee_id is not null
     from public.request_steps s
     join public.requests r on r.id = s.request_id
     where r.employee_id = 'b4330000-0000-4000-8000-000000000012'
       and r.request_type = 'mission' and s.step_order = 1 $$,
  $$ values ('active'::text, true) $$,
  '8. الخطوة الأولى نشطة ومعيّن لها المدير'
);

select results_eq(
  $$ select s.status, s.assignee_role_slug
     from public.request_steps s
     join public.requests r on r.id = s.request_id
     where r.employee_id = 'b4330000-0000-4000-8000-000000000012'
       and r.request_type = 'mission' and s.step_order = 2 $$,
  $$ values ('pending'::text, 'operations-manager-1') $$,
  '9. الخطوة الثانية معلقة بدور مشرف العمليات 1'
);

select results_eq(
  $$ select w.status from public.workflow_instances w
     join public.requests r on r.id = w.request_id
     where r.employee_id = 'b4330000-0000-4000-8000-000000000012'
       and r.request_type = 'mission' $$,
  $$ values ('running'::text) $$,
  '10. مثيل السير قيد التشغيل (running)'
);

-- =====================================================================
-- 11) تقديم إذن حضور → تنشأ خطوات السير أيضاً
-- =====================================================================
select lives_ok($$
  select public.submit_my_request('late_permit','إذن حضور 0433','تأخر مواصلات',
    jsonb_build_object(
      'permitDate', to_char(current_date + 3, 'YYYY-MM-DD'),
      'minutes', 60))
$$, '11. تقديم late_permit عبر submit_my_request ينجح');

select results_eq(
  $$ select count(*) from public.request_steps s
     join public.requests r on r.id = s.request_id
     where r.employee_id = 'b4330000-0000-4000-8000-000000000012'
       and r.request_type = 'late_permit' $$,
  $$ values (2::bigint) $$,
  '12. طلب late_permit الجديد له خطوتا سير'
);

rollback;
