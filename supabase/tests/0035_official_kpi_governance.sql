begin;
select plan(31);

select has_table('public','kpi_policy_versions','KPI policies are versioned');
select has_table('public','kpi_goals','monthly KPI goals exist');
select has_table('public','kpi_review_sessions','mandatory review sessions exist');
select has_table('public','kpi_compliance_records','HR compliance inputs exist');
select has_table('public','kpi_attendance_snapshots','server attendance snapshots exist');
select has_table('public','kpi_notification_receipts','notification deduplication exists');

select has_column('public','kpi_cycles','scheduled_open_at','cycles have official open time');
select has_column('public','kpi_cycles','deadline_at','cycles have official deadline');
select has_column('public','kpi_cycles','extended_until','cycles support audited extension');
select has_column('public','kpi_evaluations','workflow_status','official workflow state is stored');
select has_column('public','kpi_evaluations','rating_policy_snapshot','historical rating policy is frozen');
select has_column('public','kpi_evaluations','final_breakdown','final server breakdown is stored');

select has_function('public','manage_kpi_cycle',array['uuid','text','text','timestamp with time zone'],'cycle controls exist');
select has_function('public','save_kpi_goal',array['uuid','uuid','text','text','numeric','numeric','text','numeric','date','text','text','text','text'],'goal command exists');
select has_function('public','save_kpi_review_session',array['uuid','jsonb'],'session command exists');
select has_function('public','save_kpi_compliance_metric',array['uuid','text','integer','integer','integer','integer','text'],'HR metric command exists');
select has_function('public','acknowledge_kpi_evaluation',array['uuid','text','text'],'employee acknowledgement exists');
select has_function('public','override_kpi_score',array['uuid','uuid','numeric','text'],'audited admin override exists');
select has_function('public','get_kpi_cycle_report',array['uuid'],'KPI report exists');
select has_function('public','process_kpi_cycle_schedule',array['timestamp with time zone'],'automatic cycle scheduler exists');
select has_function('public','create_kpi_policy_version',array['text','jsonb','jsonb','boolean','date'],'versioned policy command exists');

select ok((select is_full_access from public.roles where slug='executive-secretary'),'executive secretary is the main full-access administrator');
select is((select sum(c.max_score)::integer from public.kpi_criteria c join public.kpi_templates t on t.id=c.template_id where t.official_code='OFFICIAL_KPI_100'),100,'official criteria total 100');
select is((select max_score::integer from public.kpi_criteria c join public.kpi_templates t on t.id=c.template_id where t.official_code='OFFICIAL_KPI_100' and c.code='TARGET'),40,'Target is 40 points');
select is((select max_score::integer from public.kpi_criteria c join public.kpi_templates t on t.id=c.template_id where t.official_code='OFFICIAL_KPI_100' and c.code='ATTENDANCE'),20,'attendance is an automatic 20-point component');

-- Regression: an overachieving goal must never store a per-goal score above 40
-- (the TARGET section cap), even when the overachievement policy is enabled;
-- without the least(...,40) cap this insert violated the 0..40 CHECK and aborted.
do $fixture$
declare v_policy uuid; v_template uuid; v_emp uuid; v_cycle uuid; v_eval uuid;
begin
 insert into public.kpi_policy_versions(version,name_ar,effective_from,criteria_weights,attendance_rules,rating_bands,allow_target_overachievement,is_active)
 values(9001,'سياسة اختبار تجاوز الهدف','2026-01-01',
   '{"TARGET":40,"EFFICIENCY":20,"ATTENDANCE":20,"CONDUCT":5,"PRAYER":5,"HALAQA":5,"INITIATIVES":5}'::jsonb,
   '{"late":1,"earlyLeave":1,"unexcusedAbsence":4,"missingPunch":1,"shortagePerHour":1,"maxShortagePerDay":2}'::jsonb,
   '[{"min":0,"max":100,"label":"اختبار"}]'::jsonb,true,false)
 returning id into v_policy;
 select id into v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100';
 insert into public.employees(employee_code,full_name_ar,status,is_active)
 values('KPITEST9001','موظف اختبار تجاوز الهدف','active',true) returning id into v_emp;
 insert into public.kpi_cycles(period_month,status,template_id,policy_version_id)
 values('2099-01-01','open',v_template,v_policy) returning id into v_cycle;
 insert into public.kpi_evaluations(employee_id,cycle_id,template_id,stage,current_stage)
 values(v_emp,v_cycle,v_template,'self','self') returning id into v_eval;
 insert into public.kpi_goals(evaluation_id,title,target_value,achieved_value,unit,weight,status)
 values(v_eval,'هدف متجاوز',100,200,'وحدة',40,'COMPLETED');
 perform set_config('test.goal_capped_score',(select calculated_score::text from public.kpi_goals where evaluation_id=v_eval),false);
end
$fixture$;
select is(current_setting('test.goal_capped_score')::numeric,40::numeric,'overachieving goal score is capped at 40 (no CHECK violation)');

-- Regression: HR-approved attendance exceptions must be excluded from the
-- unexcused-absence and shortage deductions, not only late/early/missing.
select ok(
  (select count(*) from regexp_matches(pg_get_functiondef('public.refresh_kpi_attendance_inputs(uuid)'::regprocedure),'not exception_settled','g'))>=4,
  'attendance refresh excludes HR exceptions from absence and shortage too');

-- Regression: workflow states advertised by the CHECK constraint are reachable.
select ok(pg_get_functiondef('public.save_kpi_goal(uuid,uuid,text,text,numeric,numeric,text,numeric,date,text,text,text,text)'::regprocedure) like '%EMPLOYEE_INPUT_IN_PROGRESS%','employee self-input state is set');
select ok(pg_get_functiondef('public.advance_kpi_stage(uuid,text,jsonb,text)'::regprocedure) like '%HR_DATA_PENDING%','HR data-pending state is set');
select ok(pg_get_functiondef('public.save_kpi_compliance_metric(uuid,text,integer,integer,integer,integer,text)'::regprocedure) like '%HR_EVALUATION_IN_PROGRESS%','HR evaluation-in-progress state is set');
select ok(pg_get_functiondef('public.acknowledge_kpi_evaluation(uuid,text,text)'::regprocedure) like '%EMPLOYEE_ACKNOWLEDGED%','plain acknowledgement sets EMPLOYEE_ACKNOWLEDGED');

select * from finish();
rollback;
