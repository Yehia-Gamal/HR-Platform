-- V10 six-role runtime acceptance. Every persona uses a real auth user,
-- employee/profile link, active role assignment and RLS/RPC execution context.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,storage,pg_temp;
select plan(47);

do $fixture$
declare v_le uuid:='93000000-0000-4000-8000-000000000000'; v_dept uuid:='93000000-0000-4000-8000-000000000001';
begin
 insert into public.legal_entities(id,code,name) values(v_le,'V10-ACT','كيان قبول V10');
 insert into public.departments(id,legal_entity_id,code,name) values(v_dept,v_le,'V10-D','إدارة قبول V10');
 insert into auth.users(id,email,aud,role) values
  ('91000000-0000-4000-8000-000000000001','v10-employee@test.local','authenticated','authenticated'),
  ('91000000-0000-4000-8000-000000000002','v10-manager@test.local','authenticated','authenticated'),
  ('91000000-0000-4000-8000-000000000003','v10-operations@test.local','authenticated','authenticated'),
  ('91000000-0000-4000-8000-000000000004','v10-executive@test.local','authenticated','authenticated'),
  ('91000000-0000-4000-8000-000000000005','v10-hr@test.local','authenticated','authenticated'),
  ('91000000-0000-4000-8000-000000000006','v10-secretary@test.local','authenticated','authenticated');
 insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,hire_date) values
  ('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','V10-EMP','موظف قبول V10',v_dept,'active',true,current_date-1000),
  ('92000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000002','V10-MGR','مدير قبول V10',v_dept,'active',true,current_date-1500),
  ('92000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000003','V10-OPS','مسؤول Operations الفعلي',v_dept,'active',true,current_date-1200),
  ('92000000-0000-4000-8000-000000000004','91000000-0000-4000-8000-000000000004','V10-EXEC','المدير التنفيذي للاختبار',v_dept,'active',true,current_date-3000),
  ('92000000-0000-4000-8000-000000000005','91000000-0000-4000-8000-000000000005','V10-HR','مسؤول HR للاختبار',v_dept,'active',true,current_date-900),
  ('92000000-0000-4000-8000-000000000006','91000000-0000-4000-8000-000000000006','V10-SEC','السكرتير التنفيذي للاختبار',v_dept,'active',true,current_date-2000);
 insert into public.profiles(id,employee_id,status)
 select user_id,id,'active' from public.employees where employee_code like 'V10-%';

 insert into public.roles(slug,name_ar,is_system,is_full_access)
 values('v10-acceptance-operations-target','Operations target for V10',true,false);
 insert into public.user_roles(user_id,role_id,effective_from)
 select x.user_id,r.id,x.effective_from
 from (values
  ('91000000-0000-4000-8000-000000000001'::uuid,'employee',now()),
  ('91000000-0000-4000-8000-000000000002'::uuid,'employee',now()),
  ('91000000-0000-4000-8000-000000000002'::uuid,'direct-manager',now()),
  ('91000000-0000-4000-8000-000000000003'::uuid,'employee',now()),
  ('91000000-0000-4000-8000-000000000003'::uuid,'direct-manager',now()),
  ('91000000-0000-4000-8000-000000000003'::uuid,'operations-officer',now()-interval '20 years'),
  ('91000000-0000-4000-8000-000000000003'::uuid,'committee-member',now()),
  ('91000000-0000-4000-8000-000000000003'::uuid,'v10-acceptance-operations-target',now()-interval '20 years'),
  ('91000000-0000-4000-8000-000000000004'::uuid,'executive-director',now()),
  ('91000000-0000-4000-8000-000000000005'::uuid,'hr-manager',now()),
  ('91000000-0000-4000-8000-000000000006'::uuid,'executive-secretary',now())
 ) x(user_id,slug,effective_from) join public.roles r on r.slug=x.slug;

 insert into public.manager_relations(employee_id,manager_employee_id,relation_type,effective_from) values
  ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002','primary',current_date),
  ('92000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000004','primary',current_date),
  ('92000000-0000-4000-8000-000000000003','92000000-0000-4000-8000-000000000004','primary',current_date);

 update public.system_settings set value=to_jsonb('v10-acceptance-operations-target'::text)
 where key='leave_escalation_target_role';
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 perform public.open_annual_leave_entitlement('92000000-0000-4000-8000-000000000001',extract(year from current_date)::integer);
 perform public.open_annual_leave_entitlement('92000000-0000-4000-8000-000000000002',extract(year from current_date)::integer);

 insert into storage.objects(bucket_id,name,owner,owner_id,metadata)
 values('request-attachments','91000000-0000-4000-8000-000000000001/acceptance.jpg',
  '91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001',
  jsonb_build_object('mimetype','image/jpeg','size',2048));

 insert into public.kpi_cycles(id,period_month,status,template_id,deadline_at,self_due_at,manager_due_at,secretary_due_at,executive_due_at)
 select '94000000-0000-4000-8000-000000000001','2099-01-01','draft',id,now()+interval '30 days',now()+interval '30 days',now()+interval '30 days',now()+interval '30 days',now()+interval '30 days'
 from public.kpi_templates where official_code='OFFICIAL_KPI_100' limit 1;
end $fixture$;

create temporary table acceptance_runtime(kind text primary key,id uuid);
grant select,insert,update on acceptance_runtime to authenticated;

-- Employee persona.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select is(public.get_my_access_context()->>'defaultWorkspace','employee','employee lands in the employee workspace');
select ok((public.get_my_access_context()->'workspaces') ? 'employee' and (public.get_my_access_context()#>>'{attendancePolicy,attendanceRequired}')::boolean,'employee has self attendance');
select ok(public.has_permission('performance.kpi.self_assess') and not public.has_permission('requests.request.approve'),'employee can self-evaluate but cannot approve requests');

do $employee_actions$
declare v_req public.requests; v_case uuid;
begin
 v_req:=public.submit_my_request('leave','إجازة قبول V10','طلب إجازة موثق بالمرفق والبديل',jsonb_build_object(
  'leaveType','annual','startDate',current_date+10,'endDate',current_date+11,
  'substituteEmployeeId','92000000-0000-4000-8000-000000000003',
  'attachmentPaths',jsonb_build_array(jsonb_build_object('path','91000000-0000-4000-8000-000000000001/acceptance.jpg','name','acceptance.jpg','mimeType','image/jpeg','sizeBytes',2048))));
 insert into acceptance_runtime values('employee_leave',v_req.id);
 v_req:=public.submit_my_request('mission','مأمورية قبول V10','مأمورية لاختبار الاعتماد والتعارض',jsonb_build_object(
  'startDate',current_date+10,'endDate',current_date+11,'location','مقر الاختبار'));
 insert into acceptance_runtime values('employee_mission',v_req.id);
 v_case:=public.submit_my_dispute('مشكلة قبول الأدوار الستة','تفاصيل كافية لمشكلة قبول Runtime بين الموظف ومسؤول العمليات.',
  'employee_conflict','normal',null,'مقر الاختبار',
  '[{"employeeId":"92000000-0000-4000-8000-000000000003","type":"respondent"}]'::jsonb,
  '[]'::jsonb,null,null,null,'المراجعة والحل',true,true,true);
 insert into acceptance_runtime values('employee_dispute',v_case);
end $employee_actions$;

select is((select status from public.requests where id=(select id from acceptance_runtime where kind='employee_leave')),'pending','employee submits leave');
select is((select status from public.requests where id=(select id from acceptance_runtime where kind='employee_mission')),'pending','employee submits mission');
select is((select status from public.dispute_cases where id=(select id from acceptance_runtime where kind='employee_dispute')),'submitted','employee submits a problem');
select is((select count(*)::integer from public.attachments where entity_type='request' and entity_id=(select id from acceptance_runtime where kind='employee_leave')),1,'request attachment is privately registered');
select is((select substitute_employee_id from public.leave_requests where request_id=(select id from acceptance_runtime where kind='employee_leave')),'92000000-0000-4000-8000-000000000003'::uuid,'employee selects a substitute');
select ok((public.get_mobile_request_detail((select id from acceptance_runtime where kind='employee_leave'))->>'canCancel')::boolean,'employee can cancel before manager decision');
select throws_ok($$select public.decide_request((select id from acceptance_runtime where kind='employee_leave'),'approve','محاولة ذاتية')$$,'42501',null,'employee cannot approve own request');

-- Assign the submitted case to the Operations committee member.
reset role;
insert into public.committee_members(case_id,employee_id,role_in_committee,is_active)
values((select id from acceptance_runtime where kind='employee_dispute'),'92000000-0000-4000-8000-000000000003','member',true);

-- Manager persona.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select ok((public.get_my_access_context()->'workspaces') ?& array['employee','manager'] and public.has_permission('performance.kpi.manager_assess'),'manager inherits employee and manager capabilities');
select ok(public.can_access_employee('92000000-0000-4000-8000-000000000001','requests.request.approve'),'manager can access direct report');
select ok(not public.can_access_employee('92000000-0000-4000-8000-000000000003','requests.request.approve'),'manager cannot access employee outside the team');
select is((select count(*)::integer from storage.objects where bucket_id='request-attachments' and name='91000000-0000-4000-8000-000000000001/acceptance.jpg'),1,'manager can read the direct report private attachment');
select is(jsonb_array_length(public.get_mobile_request_detail((select id from acceptance_runtime where kind='employee_leave'))->'attachments'),1,'manager detail exposes registered attachment');
select is(public.get_mobile_request_detail((select id from acceptance_runtime where kind='employee_leave'))#>>'{decisionContext,substitute,name}','مسؤول Operations الفعلي','manager sees the substitute name');
select ok((public.get_mobile_request_detail((select id from acceptance_runtime where kind='employee_leave'))#>>'{decisionContext,hasConflict}')::boolean,'manager sees the overlapping mission conflict');
select lives_ok($$select public.decide_request((select id from acceptance_runtime where kind='employee_leave'),'approve','موافقة المدير المباشر')$$,'manager approves direct report leave');
select is(
  (select status from public.requests where id=(select id from acceptance_runtime where kind='employee_leave')),
  'pending',
  'manager approval advances leave to HR review without prematurely approving it'
);
select throws_ok($$select public.decide_request((select id from acceptance_runtime where kind='employee_mission'),'reject',null)$$,'22023',null,'server requires a rejection reason');
select lives_ok($$select public.decide_request((select id from acceptance_runtime where kind='employee_mission'),'reject','تعارض مع خطة التشغيل')$$,'manager rejects mission with a reason');
select is((select status from public.requests where id=(select id from acceptance_runtime where kind='employee_mission')),'rejected','mission rejection is persisted');

do $manager_request$
declare v_req public.requests;
begin
 v_req:=public.submit_my_request('leave','إجازة المدير الشخصية','طلب شخصي يجب أن يصعد للمدير الأعلى',jsonb_build_object(
  'leaveType','annual','startDate',current_date+20,'endDate',current_date+20));
 insert into acceptance_runtime values('manager_leave',v_req.id);
end $manager_request$;
select throws_ok($$select public.decide_request((select id from acceptance_runtime where kind='manager_leave'),'approve','محاولة اعتماد ذاتي')$$,'42501',null,'manager cannot approve own request');

-- Expire the executive decision SLA and route it to the configured Operations user.
reset role;
update public.requests set decision_due_at=now()-interval '1 hour'
where id=(select id from acceptance_runtime where kind='manager_leave');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select is(public.process_request_sla(10),1,'SLA processor escalates the overdue executive request');

-- Operations persona.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000003',true);
select ok((public.get_my_access_context()->'workspaces') ?& array['employee','manager','field_operations','committee'],'Operations inherits employee/manager and receives operations/committee workspaces');
select ok(exists(select 1 from jsonb_array_elements(public.get_dispute_operations_catalog(null)->'cases') c where c->>'id'=(select id::text from acceptance_runtime where kind='employee_dispute')),'Operations sees the assigned committee case');
select is((select payload#>>'{escalation,onBehalfOfExecutive}' from public.requests where id=(select id from acceptance_runtime where kind='manager_leave')),'true','escalation is marked on behalf of the executive director');
select lives_ok($$select public.decide_request((select id from acceptance_runtime where kind='manager_leave'),'approve','قرار Operations بعد انتهاء المهلة')$$,'Operations decides the escalated request');
select is((select status from public.requests where id=(select id from acceptance_runtime where kind='manager_leave')),'approved','Operations decision is persisted');
select is((select actor_employee_id from public.request_actions where request_id=(select id from acceptance_runtime where kind='manager_leave') and action='approve' order by created_at desc limit 1),'92000000-0000-4000-8000-000000000003'::uuid,'real Operations employee is the decision actor');
select is((select metadata->>'actorName' from public.request_actions where request_id=(select id from acceptance_runtime where kind='manager_leave') and action='approve' order by created_at desc limit 1),'مسؤول Operations الفعلي','Operations actor name is recorded');
select is((select metadata->>'onBehalfOfExecutive' from public.request_actions where request_id=(select id from acceptance_runtime where kind='manager_leave') and action='approve' order by created_at desc limit 1),'true','decision audit records on-behalf mode');
select ok((public.get_mobile_request_detail((select id from acceptance_runtime where kind='manager_leave'))->>'decisionOnBehalfOfExecutive')::boolean and public.get_mobile_request_detail((select id from acceptance_runtime where kind='manager_leave'))->>'decisionActorName'='مسؤول Operations الفعلي','mobile detail attributes the decision to Operations, not the executive');

-- Executive director persona.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000004',true);
select ok(not (public.get_my_access_context()->'workspaces') ? 'employee' and (public.get_my_access_context()->'workspaces') ? 'executive' and not (public.get_my_access_context()#>>'{attendancePolicy,selfPunchEnabled}')::boolean,'executive has no attendance or employee workspace');
select lives_ok($$select public.get_v10_executive_daily_report(current_date)$$,'executive reads the V10 daily report');
select ok((public.get_v10_executive_daily_report(current_date)#>>'{employees,active}')::integer>=5,'daily report starts from all active non-executive employees');
select lives_ok($$select public.request_live_location('92000000-0000-4000-8000-000000000001','snapshot','طلب موقع قبول V10')$$,'executive requests any employee location');
select is((select count(*)::integer from public.attendance_daily where employee_id='92000000-0000-4000-8000-000000000004'),0,'executive has no attendance record');

-- HR web persona.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000005',true);
select ok((public.get_my_access_context()->'workspaces') ? 'hr' and (public.get_my_access_context()->'workspaces') ? 'employee' and not (public.get_my_access_context()->'workspaces') ? 'main_admin' and (public.get_my_access_context()#>>'{attendancePolicy,attendanceRequired}')::boolean,'HR has hr + employee workspaces with attendance, no admin access');
select ok(public.current_is_hr_reviewer() and public.has_permission('performance.kpi.hr_review'),'HR owns only the HR review stage');
select throws_ok($$select public.manage_kpi_cycle('94000000-0000-4000-8000-000000000001','open','محاولة HR فتح الدورة',null)$$,'42501',null,'HR cannot open the KPI cycle');
select ok(public.has_permission('people.employee.update_basic'),'HR can edit permitted employee fields');

-- Executive secretary / Main Admin web persona.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000006","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000006',true);
select ok((public.get_my_access_context()->'workspaces') ? 'main_admin' and (public.get_my_access_context()#>>'{attendancePolicy,attendanceRequired}')::boolean,'executive secretary uses Main Admin web and follows the employee attendance policy');
select ok(public.current_is_executive_secretary(),'executive secretary is the exclusive KPI controller');
select lives_ok($$select public.manage_kpi_cycle('94000000-0000-4000-8000-000000000001','open','فتح دورة قبول V10',null)$$,'secretary opens the KPI cycle');
select lives_ok($$select public.manage_kpi_cycle('94000000-0000-4000-8000-000000000001','extend','تمديد دورة قبول V10',now()+interval '40 days')$$,'secretary extends the KPI cycle');
select ok((select status='open' and extended_until is not null from public.kpi_cycles where id='94000000-0000-4000-8000-000000000001'),'cycle control is persisted with audit fields');

reset role;
select * from finish();
rollback;
