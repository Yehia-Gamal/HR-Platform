-- Diagnostic: why does advance_kpi_stage raise FORBIDDEN for self-assessment?
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(6);

-- Fixtures (same as 0036)
insert into auth.users(id,email,aud,role) values
 ('81000000-0000-4000-8000-000000000001','kpi-s9@test.local','authenticated','authenticated'),
 ('81000000-0000-4000-8000-000000000002','kpi-e9@test.local','authenticated','authenticated'),
 ('81000000-0000-4000-8000-000000000003','kpi-m9@test.local','authenticated','authenticated'),
 ('81000000-0000-4000-8000-000000000004','kpi-h9@test.local','authenticated','authenticated');

insert into public.employees(id,user_id,employee_code,full_name_ar,status,is_active) values
 ('82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','KPI-S9','سكرتير','active',true),
 ('82000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000002','KPI-E9','موظف','active',true),
 ('82000000-0000-4000-8000-000000000003','81000000-0000-4000-8000-000000000003','KPI-M9','مدير','active',true),
 ('82000000-0000-4000-8000-000000000004','81000000-0000-4000-8000-000000000004','KPI-H9','HR','active',true);

insert into public.profiles(id,employee_id,status)
select user_id,id,'active' from public.employees
where id between '82000000-0000-4000-8000-000000000001' and '82000000-0000-4000-8000-000000000004';

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

-- Create cycle as secretary
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

create temp table diag9(key text primary key, val text);

do $cyc$
declare v_t uuid; v_c uuid;
begin
  select id into v_t from public.kpi_templates where official_code='OFFICIAL_KPI_100';
  v_c:=public.create_kpi_cycle_admin(date '2091-01-01',v_t,now(),now(),now(),now(),false,false);
  perform public.manage_kpi_cycle(v_c,'open','فتح دورة اختبار',null);
  insert into diag9 values('cycle',v_c::text),('template',v_t::text);
end $cyc$;

select pass('cycle created and opened');

-- Check eval state as superuser
reset role;
do $chk$
declare
  v_cycle uuid; v_eval_id uuid;
  v_ws text; v_locked boolean; v_emp uuid; v_stage text;
begin
  select val::uuid into v_cycle from diag9 where key='cycle';
  select id, workflow_status, locked, employee_id, current_stage
    into v_eval_id, v_ws, v_locked, v_emp, v_stage
    from public.kpi_evaluations where cycle_id=v_cycle and employee_id='82000000-0000-4000-8000-000000000002';

  raise notice 'eval_id=%, workflow_status=%, locked=%, employee_id=%, current_stage=%',
    v_eval_id, v_ws, v_locked, v_emp, v_stage;

  insert into diag9 values('eval_id', v_eval_id::text);
end $chk$;

select pass('eval state checked');

-- Now test each FORBIDDEN condition as KPI-EMP
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"81000000-0000-4000-8000-000000000002","role":"authenticated"}',true);

-- Condition 1: workflow_status = 'DRAFT'?
select ok(
  (select workflow_status from public.kpi_evaluations where id=(select val::uuid from diag9 where key='eval_id')) <> 'DRAFT',
  'workflow_status is NOT DRAFT after opening cycle'
);

-- Condition 2: employee_id <> current_employee_id()?
select ok(
  (select employee_id from public.kpi_evaluations where id=(select val::uuid from diag9 where key='eval_id')) = public.current_employee_id(),
  'employee_id matches current_employee_id()'
);

-- Condition 3: has_permission('performance.kpi.self_assess')?
select ok(
  public.has_permission('performance.kpi.self_assess'),
  'employee has performance.kpi.self_assess permission'
);

-- Also check: can the employee even see the eval via RLS?
select ok(
  exists(select 1 from public.kpi_evaluations where id=(select val::uuid from diag9 where key='eval_id')),
  'employee can see own evaluation via RLS'
);

select * from finish();
rollback;
