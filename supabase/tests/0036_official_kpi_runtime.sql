begin;
select plan(11);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,phone_change,phone_change_token,reauthentication_token)
values('00000000-0000-0000-0000-000000000000','81000000-0000-4000-8000-000000000001','authenticated','authenticated','kpi-admin@test.local',crypt('Test12345',gen_salt('bf')),now(),'{}','{}',now(),now(),'','','','','','','','');

insert into public.employees(id,user_id,employee_code,full_name_ar,status,is_active) values
 ('82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','KPI-ADMIN','السكرتير التنفيذي للاختبار','active',true),
 ('82000000-0000-4000-8000-000000000002',null,'KPI-EMP','موظف التقييم للاختبار','active',true);
insert into public.profiles(id,employee_id,primary_role_id,status)
select '81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001',id,'active' from public.roles where slug='executive-secretary';
insert into public.user_roles(user_id,role_id,effective_from)
select '81000000-0000-4000-8000-000000000001',id,now() from public.roles where slug='executive-secretary';
insert into public.manager_relations(employee_id,manager_employee_id,relation_type,effective_from)
values('82000000-0000-4000-8000-000000000002','82000000-0000-4000-8000-000000000001','primary',current_date);

create temporary table kpi_runtime_result(stage text,workflow_status text,final_score numeric,final_rating text,target_score numeric,attendance_score numeric,audit_count integer);
grant select,insert on kpi_runtime_result to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000001',true);
select ok(public.current_is_super_admin(),'executive secretary is the effective main/super administrator');

do $runtime$
declare v_template uuid; v_cycle uuid; v_eval uuid; v_eff uuid; v_conduct uuid; v_initiatives uuid;
begin
 select id into v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100';
 v_cycle:=public.create_kpi_cycle_admin(date_trunc('month',current_date)::date,v_template,now(),now(),now(),now(),false);
 perform public.manage_kpi_cycle(v_cycle,'extend','اختبار دورة كاملة',now()+interval '45 days');
 select id into v_eval from public.kpi_evaluations where cycle_id=v_cycle and employee_id='82000000-0000-4000-8000-000000000002';

 perform public.save_kpi_goal(v_eval,null,'هدف التحصيل','هدف رقمي للاختبار',10,8,'حالة',40,current_date,'تقرير الإنجاز','تم إنجاز ثماني حالات','تمت المراجعة','PARTIALLY_COMPLETED');
 perform public.advance_kpi_stage(v_eval,'self',null,'تم إدخال الإنجازات');
 perform public.save_kpi_review_session(v_eval,jsonb_build_object('heldAt',now(),'mode','ONSITE','discussionSummary','تمت مراجعة الإنجازات والمعوقات','strengths','الالتزام والمتابعة','improvementPoints','رفع سرعة التنفيذ','nextMonthGoals','استكمال الهدف الجديد','employeeAttended',true,'managerAttended',true));
 select id into v_eff from public.kpi_criteria where template_id=v_template and code='EFFICIENCY';
 select id into v_conduct from public.kpi_criteria where template_id=v_template and code='CONDUCT';
 select id into v_initiatives from public.kpi_criteria where template_id=v_template and code='INITIATIVES';
 perform public.advance_kpi_stage(v_eval,'manager',jsonb_build_array(
  jsonb_build_object('criterion_id',v_eff,'score',16,'note','كفاءة جيدة جدًا'),
  jsonb_build_object('criterion_id',v_conduct,'score',4,'note','سلوك جيد جدًا'),
  jsonb_build_object('criterion_id',v_initiatives,'score',3,'note','مشاركة مقبولة')
 ),'تعليق المدير النهائي');
 perform public.save_kpi_compliance_metric(v_eval,'PRAYER',10,10,0,0,'التزام كامل');
 perform public.save_kpi_compliance_metric(v_eval,'HALAQA',4,3,0,0,'حضر ثلاث حلقات');
 perform public.advance_kpi_stage(v_eval,'hr',null,'اعتماد بيانات HR والحضور');
 perform public.acknowledge_kpi_evaluation(v_eval,'اطلعت على النتيجة',null);
 perform public.advance_kpi_stage(v_eval,'secretary',null,'مراجعة السكرتير التنفيذي');
 perform public.advance_kpi_stage(v_eval,'executive',null,'الاعتماد التنفيذي النهائي');

 insert into kpi_runtime_result
 select e.current_stage,e.workflow_status,e.final_score,e.final_rating,
  (select public.kpi_effective_score(e.id,c.id) from public.kpi_criteria c where c.template_id=e.template_id and c.code='TARGET'),
  (select public.kpi_effective_score(e.id,c.id) from public.kpi_criteria c where c.template_id=e.template_id and c.code='ATTENDANCE'),
  (select count(*) from public.audit_events a where a.target_id=e.id)
 from public.kpi_evaluations e where e.id=v_eval;
end
$runtime$;

select is((select stage from kpi_runtime_result),'finalized','runtime flow reaches final approval');
select is((select workflow_status from kpi_runtime_result),'APPROVED','workflow is approved');
select is((select final_score from kpi_runtime_result),83.75::numeric,'server computes the expected 83.75 total');
select is((select final_rating from kpi_runtime_result),'جيد جدًا','rating follows the frozen policy');
select is((select target_score from kpi_runtime_result),32.00::numeric,'Target is capped and calculated from achieved/target x weight');
select is((select attendance_score from kpi_runtime_result),20.00::numeric,'attendance score is server-authored from existing attendance data');
select ok((select audit_count from kpi_runtime_result)>=6,'important workflow transitions are audited');
select is((select count(*)::integer from public.kpi_review_sessions where employee_id='82000000-0000-4000-8000-000000000002'),1,'review session is stored');
select is((select count(*)::integer from public.kpi_compliance_records where evaluation_id in (select id from public.kpi_evaluations where employee_id='82000000-0000-4000-8000-000000000002')),2,'HR compliance records are stored');
select ok((select employee_acknowledged_at is not null from public.kpi_evaluations where employee_id='82000000-0000-4000-8000-000000000002'),'employee acknowledgement is stored independently of score agreement');

select * from finish();
rollback;
