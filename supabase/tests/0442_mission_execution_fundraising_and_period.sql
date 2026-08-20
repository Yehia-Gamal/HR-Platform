-- =====================================================================
-- 0442: إصلاحات تنفيذ المأمورية/القافلة/الفاندي
-- ---------------------------------------------------------------------
-- يثبت: (1) الفاندي يدعم التنفيذ الآن (بدء/إنهاء + إرفاق missionExecution
-- في inbox/detail — كان يرفض 22023 قبل 0442)، (2) منع البدء بعد انتهاء
-- فترة الطلب، (3) إغلاق سجل التنفيذ المفتوح عند رفض/إلغاء الطلب بعد بدئه.
-- كل شيء ضمن معاملة تُلغى (rollback).
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(15);

-- =====================================================================
-- Fixture: كيان + إدارة + مدير + موظف.
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'a4420000-0000-4000-8000-000000000001';
  v_dept uuid := 'a4420000-0000-4000-8000-000000000002';
begin
  insert into public.legal_entities(id, code, name) values(v_le, 'F-LE', 'كيان الفاندي');
  insert into public.departments(id, legal_entity_id, code, name) values(v_dept, v_le, 'F-DEPT', 'إدارة الفاندي');

  insert into auth.users(id, email, aud, role) values
    ('a4420000-0000-4000-8000-000000000004','f-mgr@test.local','authenticated','authenticated'),
    ('a4420000-0000-4000-8000-000000000005','f-emp@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
  values
    ('a4420000-0000-4000-8000-000000000011','a4420000-0000-4000-8000-000000000004','F-MGR','مدير الفاندي',v_dept,'active',true,'1980-01-01','2015-01-01'),
    ('a4420000-0000-4000-8000-000000000012','a4420000-0000-4000-8000-000000000005','F-EMP','موظف الفاندي',v_dept,'active',true,'1995-01-01','2023-01-01');

  insert into public.profiles(id, employee_id, status) values
    ('a4420000-0000-4000-8000-000000000004','a4420000-0000-4000-8000-000000000011','active'),
    ('a4420000-0000-4000-8000-000000000005','a4420000-0000-4000-8000-000000000012','active');

  insert into public.user_roles(user_id, role_id)
  select t.u, r.id from (values
    ('a4420000-0000-4000-8000-000000000004'::uuid,'employee'),
    ('a4420000-0000-4000-8000-000000000004'::uuid,'direct-manager'),
    ('a4420000-0000-4000-8000-000000000005'::uuid,'employee')
  ) as t(u,slug) join public.roles r on r.slug=t.slug;

  insert into public.manager_relations(employee_id, manager_employee_id, relation_type)
  values('a4420000-0000-4000-8000-000000000012','a4420000-0000-4000-8000-000000000011','primary');

  create temp table pg_temp.f_req_ids(request_id uuid, rtype text) on commit drop;
end $fixture$;

-- =====================================================================
-- الوجود: الدوال والـ trigger.
-- =====================================================================
select has_function('public','start_my_mission',array['uuid'],'start_my_mission(uuid) موجودة');
select has_function('public','tg_mission_execution_close_on_cancel',array[]::text[],'دالة الإغلاق عند الإنهاء السلبي موجودة');
select has_trigger('public','requests','trg_mission_execution_close_on_cancel','trigger الإغلاق مثبت على requests');

-- =====================================================================
-- 1) الفاندي: تقديم + اعتماد + بدء + إنهاء + إرفاق في inbox/detail.
-- =====================================================================
do $set_emp$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a4420000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a4420000-0000-4000-8000-000000000005', true);
end $set_emp$;

select lives_ok($$
  insert into pg_temp.f_req_ids(request_id, rtype)
  select (public.submit_my_request('fundraising','فاندي خيري','جمع تبرعات لصالح الأسر المتعففة',
    '{"startDate":"2026-09-10","endDate":"2026-09-11","location":"مقر الجمعية","startTime":"09:00"}'::jsonb)).id, 'fundraising'
$$, 'تقديم طلب فاندي ينجح');

do $approve$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a4420000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a4420000-0000-4000-8000-000000000004', true);
  perform public.decide_request((select request_id from pg_temp.f_req_ids where rtype='fundraising'), 'approve', 'موافقة الفاندي');
end $approve$;

select is(
  (select status from public.requests r join pg_temp.f_req_ids t on t.request_id=r.id where t.rtype='fundraising'),
  'approved', 'طلب الفاندي أصبح معتمدًا');

do $start$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a4420000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a4420000-0000-4000-8000-000000000005', true);
  perform public.start_my_mission((select request_id from pg_temp.f_req_ids where rtype='fundraising'));
end $start$;

select is(
  (select me.status from public.mission_executions me
   join pg_temp.f_req_ids t on t.request_id=me.request_id where t.rtype='fundraising'),
  'in_progress', 'الفاندي بدأ تنفيذه بنجاح بعد 0442');

select ok(
  (select count(*) > 0
   from public.get_request_inbox(100) b, jsonb_array_elements(b) item
   where item->>'id' = (select request_id::text from pg_temp.f_req_ids where rtype='fundraising')
     and item->'missionExecution'->>'status' = 'in_progress'),
  'get_request_inbox يرفق missionExecution لطلبات الفاندي');

select is(
  (select public.get_mobile_request_detail((select request_id from pg_temp.f_req_ids where rtype='fundraising'))
     -> 'missionExecution' ->> 'status'),
  'in_progress', 'get_mobile_request_detail يرفق missionExecution للفاندي');

do $end$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a4420000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a4420000-0000-4000-8000-000000000005', true);
  perform public.end_my_mission((select request_id from pg_temp.f_req_ids where rtype='fundraising'),
    'تم جمع التبرعات وتسليمها للمستفيدين', 'successful');
end $end$;

select is(
  (select me.status from public.mission_executions me
   join pg_temp.f_req_ids t on t.request_id=me.request_id where t.rtype='fundraising'),
  'completed', 'الفاندي اكتمل عبر نفس مسار التنفيذ');

-- =====================================================================
-- 2) منع البدء بعد انتهاء فترة الطلب (إدراج مباشر — submit يرفض الماضي).
-- =====================================================================
do $past$
begin
  insert into public.requests(id, request_type, employee_id, status, title, reason, payload)
  values('a4420000-0000-4000-8000-000000000021','mission','a4420000-0000-4000-8000-000000000012','approved',
    'مأمورية منتهية','سبب تقديم مقبول',
    '{"startDate":"2020-01-01","endDate":"2020-01-02","location":"جهة"}'::jsonb);
  insert into pg_temp.f_req_ids(request_id, rtype) values('a4420000-0000-4000-8000-000000000021','mission_past');
end $past$;

select throws_ok($$
  select public.start_my_mission((select request_id from pg_temp.f_req_ids where rtype='mission_past'))
$$, '22023', null, 'البدء بعد انتهاء مدة المأمورية مرفوض');

-- =====================================================================
-- 3) الرفض/الإلغاء بعد بدء التنفيذ يغلق سجل التنفيذ المفتوح.
-- =====================================================================
do $fr$
begin
  insert into pg_temp.f_req_ids(request_id, rtype)
  select (public.submit_my_request('convoy','قافلة إغاثية','توزيع مواد غذائية على القرى',
    '{"startDate":"2026-09-20","endDate":"2026-09-21","location":"القرى"}'::jsonb)).id, 'convoy_cancel';
end $fr$;

do $approve2$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a4420000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a4420000-0000-4000-8000-000000000004', true);
  perform public.decide_request((select request_id from pg_temp.f_req_ids where rtype='convoy_cancel'), 'approve', 'موافقة القافلة');
end $approve2$;

do $start2$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a4420000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a4420000-0000-4000-8000-000000000005', true);
  perform public.start_my_mission((select request_id from pg_temp.f_req_ids where rtype='convoy_cancel'));
end $start2$;

select is(
  (select me.status from public.mission_executions me
   join pg_temp.f_req_ids t on t.request_id=me.request_id where t.rtype='convoy_cancel'),
  'in_progress', 'تنفيذ القافلة بدأ قبل الرفض');

do $reject$
begin
  update public.requests
     set status = 'rejected'
   where id = (select request_id from pg_temp.f_req_ids where rtype='convoy_cancel');
end $reject$;

select is(
  (select me.status from public.mission_executions me
   join pg_temp.f_req_ids t on t.request_id=me.request_id where t.rtype='convoy_cancel'),
  'completed', 'رفض الطلب بعد بدء التنفيذ يُغلق سجل التنفيذ');
select ok(
  (select me.ended_at is not null from public.mission_executions me
   join pg_temp.f_req_ids t on t.request_id=me.request_id where t.rtype='convoy_cancel'),
  'ended_at حُدد عند الإغلاق');
select ok(
  (select me.report = 'أُلغي الطلب قبل إتمام التنفيذ' from public.mission_executions me
   join pg_temp.f_req_ids t on t.request_id=me.request_id where t.rtype='convoy_cancel'),
  'تقرير افتراضي يُكتب عند عدم وجود تقرير');

-- الإلغاء (cancelled) يغلق التنفيذ أيضًا.
do $fr2$
begin
  insert into pg_temp.f_req_ids(request_id, rtype)
  select (public.submit_my_request('mission','مأمورية قابلة للإلغاء','سبب مقبول',
    '{"startDate":"2026-09-25","endDate":"2026-09-25","location":"جهة"}'::jsonb)).id, 'mission_cancel';
end $fr2$;

do $approve3$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a4420000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a4420000-0000-4000-8000-000000000004', true);
  perform public.decide_request((select request_id from pg_temp.f_req_ids where rtype='mission_cancel'), 'approve', 'موافقة');
end $approve3$;

do $start3$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"a4420000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub','a4420000-0000-4000-8000-000000000005', true);
  perform public.start_my_mission((select request_id from pg_temp.f_req_ids where rtype='mission_cancel'));
end $start3$;

do $cancel$
begin
  update public.requests
     set status = 'cancelled'
   where id = (select request_id from pg_temp.f_req_ids where rtype='mission_cancel');
end $cancel$;

select is(
  (select me.status from public.mission_executions me
   join pg_temp.f_req_ids t on t.request_id=me.request_id where t.rtype='mission_cancel'),
  'completed', 'إلغاء الطلب بعد بدء التنفيذ يُغلق سجل التنفيذ');

select * from finish();
rollback;