begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(14);

insert into auth.users(id,email,aud,role) values
 ('81000000-0000-4000-8000-000000000001','kpi-secretary@test.local','authenticated','authenticated'),
 ('81000000-0000-4000-8000-000000000002','kpi-employee@test.local','authenticated','authenticated'),
 ('81000000-0000-4000-8000-000000000003','kpi-manager@test.local','authenticated','authenticated'),
 ('81000000-0000-4000-8000-000000000004','kpi-hr@test.local','authenticated','authenticated');

insert into public.employees(id,user_id,employee_code,full_name_ar,status,is_active) values
 ('82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','KPI-SEC','سكرتير KPI للاختبار','active',true),
 ('82000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000002','KPI-EMP','موظف KPI للاختبار','active',true),
 ('82000000-0000-4000-8000-000000000003','81000000-0000-4000-8000-000000000003','KPI-MGR','مدير KPI للاختبار','active',true),
 ('82000000-0000-4000-8000-000000000004','81000000-0000-4000-8000-000000000004','KPI-HR','مسؤول HR للاختبار','active',true);

insert into public.profiles(id,employee_id,status)
select user_id,id,'active' from public.employees where id between '82000000-0000-4000-8000-000000000001' and '82000000-0000-4000-8000-000000000004';

insert into public.user_roles(user_id,role_id,effective_from)
select x.user_id,r.id,now()
from (values
 ('81000000-0000-4000-8000-000000000001'::uuid,'executive-secretary'),
 ('81000000-0000-4000-8000-000000000002'::uuid,'employee'),
 ('81000000-0000-4000-8000-000000000003'::uuid,'direct-manager'),
 ('81000000-0000-4000-8000-000000000004'::uuid,'hr-manager')
) x(user_id,slug) join public.roles r on r.slug=x.slug;

insert into public.manager_relations(employee_id,manager_employee_id,relation_type,effective_from)
values('82000000-0000-4000-8000-000000000002','82000000-0000-4000-8000-000000000003','primary',current_date);

create temporary table kpi_runtime_result(
 cycle_id uuid,evaluation_id uuid,stage text,workflow_status text,final_score numeric,
 final_rating text,self_scores integer,target_score numeric,attendance_score numeric,audit_count integer
);
grant select,insert,update on kpi_runtime_result to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000001',true);
select ok(public.current_is_executive_secretary(),'secretary is the exclusive cycle controller');

do $create_cycle$
declare
 v_template uuid;
 v_cycle uuid;
 v_eval uuid;
 v_test_month date:=date '2099-01-01';
begin
 select id into v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100';
 v_cycle:=public.create_kpi_cycle_admin(v_test_month,v_template,now(),now(),now(),now(),false);
 perform public.manage_kpi_cycle(v_cycle,'open','فتح دورة اختبار V17',null);
 perform public.manage_kpi_cycle(v_cycle,'extend','تمديد دورة اختبار V17',v_test_month+interval '60 days');
 select id into strict v_eval from public.kpi_evaluations where cycle_id=v_cycle and employee_id='82000000-0000-4000-8000-000000000002';
 insert into kpi_runtime_result(cycle_id,evaluation_id) values(v_cycle,v_eval);
end
$create_cycle$;

-- ═══════════════════════════════════════════════════════════════════════════
-- V17 §KPI flow: Employee → HR → Manager → Manager Final → Finalized
-- ═══════════════════════════════════════════════════════════════════════════

-- Step 1: Employee self-assessment → goes to HR (not manager)
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000002',true);
do $employee_submit$
declare v_eval uuid; v_scores jsonb;
begin
 select evaluation_id into v_eval from kpi_runtime_result;
 select jsonb_agg(jsonb_build_object('criterion_id',c.id,'score',round(c.max_score*0.8,2),'note','تقييم ذاتي موثق'))
 into v_scores from public.kpi_evaluations e join public.kpi_criteria c on c.template_id=e.template_id where e.id=v_eval;
 perform public.advance_kpi_stage(v_eval,'self',v_scores,'اكتمل التقييم الذاتي للبنود السبعة');
end
$employee_submit$;

select is((select current_stage from public.kpi_evaluations where id=(select evaluation_id from kpi_runtime_result)),'hr_review','self submission goes to HR review first');
select is((select count(*)::integer from public.kpi_scores where evaluation_id=(select evaluation_id from kpi_runtime_result) and reviewer_stage='self'),7,'employee proposes all seven scores');

-- Step 2: HR reviews compliance (attendance + prayer + halaqa) → sends to manager
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000004',true);

select throws_ok(
 $$select public.manage_kpi_cycle((select cycle_id from kpi_runtime_result),'close','محاولة HR إغلاق الدورة',null)$$,
 '42501',null,'HR cannot control the KPI cycle even with legacy permission rows');

do $hr_review$
declare v_eval uuid;
begin
 select evaluation_id into v_eval from kpi_runtime_result;
 perform public.save_kpi_compliance_metric(v_eval,'PRAYER',10,10,0,0,'التزام كامل');
 perform public.save_kpi_compliance_metric(v_eval,'HALAQA',4,3,0,0,'حضور ثلاث حلقات');
 perform public.advance_kpi_stage(v_eval,'hr_review',null,'اكتملت بنود HR والحضور');
end
$hr_review$;

select is((select current_stage from public.kpi_evaluations where id=(select evaluation_id from kpi_runtime_result)),'manager_review','HR sends evaluation to manager for scoring');

-- Step 3: Manager scores targets/competency/conduct/initiatives → advances to manager_final
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000003',true);
do $manager_review$
declare v_eval uuid; v_template uuid; v_scores jsonb;
begin
 select evaluation_id into v_eval from kpi_runtime_result;
 select template_id into v_template from public.kpi_evaluations where id=v_eval;
 select jsonb_agg(jsonb_build_object(
   'criterion_id',c.id,
   'score',case c.code when 'TARGET' then 32 when 'EFFICIENCY' then 16 when 'CONDUCT' then 4 when 'INITIATIVES' then 3 end,
   'note','درجة المدير المباشر'
 )) into v_scores from public.kpi_criteria c where c.template_id=v_template and c.evaluator_stage='manager';
 perform public.advance_kpi_stage(v_eval,'manager_review',v_scores,'مراجعة المدير المباشر مكتملة');
end
$manager_review$;

select is((select current_stage from public.kpi_evaluations where id=(select evaluation_id from kpi_runtime_result)),'manager_final','V17: manager review advances to manager_final');

-- Step 4: Manager gives final approval → finalized
select lives_ok(
 $$select public.advance_kpi_stage((select evaluation_id from kpi_runtime_result),'manager_final',null,'اعتماد نهائي من المدير المباشر')$$,
 'manager gives final approval at manager_final stage');

reset role;
update kpi_runtime_result r set
 stage=e.current_stage,workflow_status=e.workflow_status,final_score=e.final_score,final_rating=e.final_rating,
 self_scores=(select count(*) from public.kpi_scores s where s.evaluation_id=e.id and s.reviewer_stage='self'),
 target_score=(select public.kpi_effective_score(e.id,c.id) from public.kpi_criteria c where c.template_id=e.template_id and c.code='TARGET'),
 attendance_score=(select public.kpi_effective_score(e.id,c.id) from public.kpi_criteria c where c.template_id=e.template_id and c.code='ATTENDANCE'),
 audit_count=(select count(*) from public.audit_events a where a.target_id=e.id)
from public.kpi_evaluations e where e.id=r.evaluation_id;

select is((select stage from kpi_runtime_result),'finalized','V17 flow reaches finalization');
select is((select workflow_status from kpi_runtime_result),'INCLUDED_IN_MONTHLY_REPORT','final result is included in monthly report');
select is((select final_score from kpi_runtime_result),83.75::numeric,'server computes the expected 83.75 total');
select is((select target_score from kpi_runtime_result),32.00::numeric,'manager owns the final Target score');
select is((select attendance_score from kpi_runtime_result),20.00::numeric,'attendance remains server-authored');
select ok((select audit_count from kpi_runtime_result)>=4,'workflow transitions are audited');

select * from finish();
rollback;
