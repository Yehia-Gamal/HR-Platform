begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(14);

insert into auth.users(id,email,aud,role) values
 ('81000000-0000-4000-8000-000000000001','kpi-secretary@test.local','authenticated','authenticated'),
 ('81000000-0000-4000-8000-000000000002','kpi-employee@test.local','authenticated','authenticated'),
 ('81000000-0000-4000-8000-000000000003','kpi-manager@test.local','authenticated','authenticated'),
 ('81000000-0000-4000-8000-000000000004','kpi-hr@test.local','authenticated','authenticated');

insert into public.employees(id,user_id,employee_code,full_name_ar,status,is_active,birth_date,hire_date) values
 ('82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','KPI-SEC','سكرتير KPI للاختبار','active',true,'1990-01-01','2015-01-01'),
 ('82000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000002','KPI-EMP','موظف KPI للاختبار','active',true,'1992-01-01','2020-01-01'),
 ('82000000-0000-4000-8000-000000000003','81000000-0000-4000-8000-000000000003','KPI-MGR','مدير KPI للاختبار','active',true,'1985-01-01','2012-01-01'),
 ('82000000-0000-4000-8000-000000000004','81000000-0000-4000-8000-000000000004','KPI-HR','مسؤول HR للاختبار','active',true,'1988-01-01','2014-01-01');

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

-- المدير المباشر للموظف
insert into public.manager_relations(employee_id,manager_employee_id,relation_type,effective_from)
values('82000000-0000-4000-8000-000000000002','82000000-0000-4000-8000-000000000003','primary',current_date);

-- بذرة صلاحيات قد لا توجد في الـseed
insert into public.permissions(code,module,resource,action)
values('performance.kpi.self_assess','performance','kpi','self_assess')
on conflict(code) do nothing;
insert into public.role_permissions(role_id,permission_id,scope)
select r.id,p.id,'self' from public.roles r, public.permissions p
where r.slug='employee' and p.code='performance.kpi.self_assess'
on conflict do nothing;

create temporary table kpi_runtime_result(
 cycle_id uuid,evaluation_id uuid,final_score numeric,audit_count integer
);
grant select,insert,update on kpi_runtime_result to authenticated;

-- ═══ T1: منشئ الدورة يتجاهل علم المسار المتواز قسراً (تحت دور authenticated) ═══
create temp table t0470_cycle(cycle_id uuid) on commit drop;
grant insert,select on t0470_cycle to authenticated;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000001',true);
insert into t0470_cycle(cycle_id)
select public.create_kpi_cycle_admin(
  date '2099-05-01',
  (select id from public.kpi_templates where official_code='OFFICIAL_KPI_100'),
  date '2099-05-01'+interval '60 days',date '2099-05-01'+interval '60 days',
  date '2099-05-01'+interval '60 days',date '2099-05-01'+interval '60 days',
  true, true);
select is((select use_parallel_flow from public.kpi_cycles where id=(select cycle_id from t0470_cycle)),
 false,'0470: الدورة تُنشأ دائماً على المسار المبسّط مهما أُرسل من الواجهة');
reset role;

-- دورة اختبار مفتوحة يدوياً + تقييم واحد (نمط 0036 التاريخي لتجنّب هشاشة نافذة الفتح)
do $setup$
declare v_template uuid; v_policy uuid; v_cycle uuid;
begin
 select id into v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100';
 select id into v_policy from public.kpi_policy_versions where is_active limit 1;
 insert into public.kpi_cycles(period_month,status,template_id,scheduled_open_at,deadline_at,
   self_due_at,manager_due_at,opened_at,policy_version_id,use_parallel_flow)
 values(date '2099-01-01','open',v_template,now(),date '2099-03-15',
   date '2099-03-15',date '2099-03-15',now(),v_policy,false)
 on conflict(period_month) do update set status='open',updated_at=now()
 returning id into v_cycle;
 insert into kpi_runtime_result(cycle_id) values(v_cycle);
 insert into public.kpi_evaluations(employee_id,cycle_id,template_id,stage,current_stage,workflow_status,locked)
 values('82000000-0000-4000-8000-000000000002',v_cycle,v_template,'self','self','OPEN_FOR_SELF_EVALUATION',false)
 on conflict(employee_id,cycle_id,template_id) do update
   set stage='self',current_stage='self',workflow_status='OPEN_FOR_SELF_EVALUATION',locked=false,updated_at=now();
end $setup$;
update kpi_runtime_result r set evaluation_id=(
 select e.id from public.kpi_evaluations e where e.cycle_id=r.cycle_id
   and e.employee_id='82000000-0000-4000-8000-000000000002');

-- ═══ T2: الإرسال الذاتي يذهب للمدير مباشرة ═══
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $t2$
declare v_eval uuid; v_scores jsonb;
begin
 select evaluation_id into v_eval from kpi_runtime_result;
 select jsonb_agg(jsonb_build_object('criterion_id',c.id,'score',round(c.max_score*0.8,2),'note','تقييم ذاتي موثق'))
 into v_scores from public.kpi_criteria c
 where c.template_id=(select template_id from public.kpi_evaluations where id=v_eval);
 perform public.advance_kpi_stage(v_eval,'self',v_scores,'اكتمل التقييم الذاتي');
end $t2$;
select is((select current_stage from public.kpi_evaluations where id=(select evaluation_id from kpi_runtime_result)),
 'manager_review','0470: ذاتي ← مدير مباشرة بلا بوابة HR');
select is((select count(*)::integer from public.kpi_scores
 where evaluation_id=(select evaluation_id from kpi_runtime_result) and reviewer_stage='self'),
 7,'الموظف يقترح درجات البنود السبعة كلها كمرجع مقارنة');

-- ═══ T3: أفعال المسارات القديمة مرفوضة صراحة ═══
select throws_ok(
 $$select public.advance_kpi_stage((select evaluation_id from kpi_runtime_result),'hr_review',null,'محاولة مسار قديم')$$,
 '22023',null,'0470: hr_review لم يعد موجوداً في العقد الجديد');

-- ═══ T4: الموظف نفسه لا يستطيع اعتماد تقييمه في مرحلة المدير ═══
select throws_ok(
 $$select public.advance_kpi_stage((select evaluation_id from kpi_runtime_result),'manager_review','[]'::jsonb,'محاولة اعتماد ذاتي')$$,
 '42501',null,'اعتماد التقييم حكرٌ على الموافق المحلول');

-- ═══ T5: HR يدخل الاستثناءات (صلاة/حلقة) قبل اعتماد المدير — بلا عرقلة ═══
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000004',true);
do $t5$
declare v_eval uuid;
begin
 select evaluation_id into v_eval from kpi_runtime_result;
 perform public.save_kpi_compliance_metric(v_eval,'PRAYER',10,10,0,0,'التزام كامل');
 perform public.save_kpi_compliance_metric(v_eval,'HALAQA',4,3,0,0,'حضور ثلاث حلقات');
end $t5$;

-- ═══ T6: المدير يقيّم ويعتمد في خطوة واحدة ← نهائي مقفل بانتظار الإقرار ═══
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000003',true);
do $t6$
declare v_eval uuid; v_template uuid; v_scores jsonb;
begin
 select evaluation_id into v_eval from kpi_runtime_result;
 select template_id into v_template from public.kpi_evaluations where id=v_eval;
 select jsonb_agg(jsonb_build_object(
   'criterion_id',c.id,
   'score',case c.code when 'TARGET' then 32 when 'EFFICIENCY' then 16 when 'CONDUCT' then 4 when 'INITIATIVES' then 3 end,
   'note','درجة المدير المباشر'
 )) into v_scores from public.kpi_criteria c where c.template_id=v_template and c.evaluator_stage='manager';
 perform public.advance_kpi_stage(v_eval,'manager_review',v_scores,'مراجعة واعتماد شاملان');
end $t6$;

select is((select current_stage from public.kpi_evaluations where id=(select evaluation_id from kpi_runtime_result)),
 'finalized','0470: اعتماد المدير الواحد يصل النهائي');
select is((select workflow_status from public.kpi_evaluations where id=(select evaluation_id from kpi_runtime_result)),
 'EMPLOYEE_ACKNOWLEDGEMENT_PENDING','بانتظار إقرار الموظف بعد القفل');
select is((select (final_breakdown->>'TARGET')::numeric from public.kpi_evaluations where id=(select evaluation_id from kpi_runtime_result)),
 32.00::numeric,'المدير يملك درجة الهدف النهائية');

-- ═══ T7: إقرار الموظف ═══
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000002',true);
select lives_ok(
 $$select public.acknowledge_kpi_evaluation((select evaluation_id from kpi_runtime_result),'أقر بالنتيجة',null)$$,
 'الموظف يُقر النتيجة المقفلة');
select is((select workflow_status from public.kpi_evaluations where id=(select evaluation_id from kpi_runtime_result)),
 'EMPLOYEE_ACKNOWLEDGED','الحالة تصبح مُقرّاً بها');

-- ═══ T8: غير المالك ممنوع من الإقرار ═══
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000003',true);
select throws_ok(
 $$select public.acknowledge_kpi_evaluation((select evaluation_id from kpi_runtime_result),'مدير يحاول',null)$$,
 '42501',null,'الإقرار حق حصري لمالك التقييم');

-- ═══ T9-T11: التوثيق وحلّ الموافِق ═══
reset role;
update kpi_runtime_result r set audit_count=(
 select count(*) from public.audit_events a where a.target_id=r.evaluation_id);
select ok((select audit_count from kpi_runtime_result)>=4,
 'كل انتقالات المسار المبسّط موثقة تدقيقياً');
select is((select public.kpi_resolve_approver_for_employee('82000000-0000-4000-8000-000000000002')),
 '82000000-0000-4000-8000-000000000003'::uuid,'حلّ الموافِق يعيد المدير المباشر عند وجوده');
delete from public.manager_relations where employee_id='82000000-0000-4000-8000-000000000002';
select is((select public.kpi_resolve_approver_for_employee('82000000-0000-4000-8000-000000000002')),
 '82000000-0000-4000-8000-000000000004'::uuid,'بلا مدير: الحلّ الآلي يقصد HR بدل العرقلة');

select * from finish();
rollback;
