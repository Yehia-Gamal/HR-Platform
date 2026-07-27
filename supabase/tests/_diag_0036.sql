-- Diagnostic test: why does 0036 create 0 evaluations?
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(8);

-- 1. Does OFFICIAL_KPI_100 template exist?
select ok(
  exists(select 1 from public.kpi_templates where official_code='OFFICIAL_KPI_100' and is_active),
  'OFFICIAL_KPI_100 template exists and is active'
);

-- 2. Does kpi_policy_versions have an active row?
select ok(
  exists(select 1 from public.kpi_policy_versions where is_active),
  'kpi_policy_versions has active row'
);

-- 3. What signature does create_kpi_cycle_admin have?
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on p.pronamespace=n.oid
   where n.nspname='public' and p.proname='create_kpi_cycle_admin'),
  1,
  'create_kpi_cycle_admin function exists (1 overload)'
);

-- 4. How many params?
select is(
  (select pronargs::int from pg_proc p join pg_namespace n on p.pronamespace=n.oid
   where n.nspname='public' and p.proname='create_kpi_cycle_admin'),
  8,
  'create_kpi_cycle_admin has 8 params (V23 version with parallel_flow)'
);

-- 5. Check current_stage CHECK constraint values
select lives_ok(
  $t$do $$
  declare v_ck text;
  begin
    select cc.check_clause into v_ck
    from information_schema.check_constraints cc
    join information_schema.table_constraints tc on cc.constraint_name=tc.constraint_name and cc.constraint_schema=tc.constraint_schema
    where tc.table_schema='public' and tc.table_name='kpi_evaluations'
      and tc.constraint_name='kpi_evaluations_current_stage_check';
    if v_ck is null then raise exception 'CHECK not found'; end if;
    raise notice 'current_stage CHECK: %', v_ck;
  end $$;$t$,
  'current_stage CHECK exists'
);

-- 6. Check workflow_status CHECK constraint values
select lives_ok(
  $t$do $$
  declare v_ck text;
  begin
    select cc.check_clause into v_ck
    from information_schema.check_constraints cc
    join information_schema.table_constraints tc on cc.constraint_name=tc.constraint_name and cc.constraint_schema=tc.constraint_schema
    where tc.table_schema='public' and tc.table_name='kpi_evaluations'
      and tc.constraint_name='kpi_evaluations_workflow_status_check';
    if v_ck is null then raise exception 'CHECK not found'; end if;
    if position('DRAFT' in v_ck)=0 then raise exception 'DRAFT missing from workflow_status CHECK: %', v_ck; end if;
    raise notice 'workflow_status CHECK: %', v_ck;
  end $$;$t$,
  'workflow_status CHECK includes DRAFT'
);

-- 7. Actually try creating the cycle and see what happens
insert into auth.users(id,email,aud,role) values
  ('d1000000-0000-4000-8000-000000000001','diag-sec@test.local','authenticated','authenticated'),
  ('d1000000-0000-4000-8000-000000000002','diag-emp@test.local','authenticated','authenticated');
insert into public.employees(id,user_id,employee_code,full_name_ar,status,is_active,is_deleted) values
  ('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','DG-SEC','سكرتير تشخيصي','active',true,false),
  ('d2000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000002','DG-EMP','موظف تشخيصي','active',true,false);
insert into public.profiles(id,employee_id,status) values
  ('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','active'),
  ('d1000000-0000-4000-8000-000000000002','d2000000-0000-4000-8000-000000000002','active');
insert into public.user_roles(user_id,role_id,effective_from)
select 'd1000000-0000-4000-8000-000000000001'::uuid,id,now() from public.roles where slug='executive-secretary';
insert into public.user_roles(user_id,role_id,effective_from)
select 'd1000000-0000-4000-8000-000000000002'::uuid,id,now() from public.roles where slug='employee';

set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000001',true);

select lives_ok(
  $t$do $$
  declare
    v_template uuid;
    v_cycle uuid;
    v_eval_count int;
  begin
    select id into v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100';
    if v_template is null then raise exception 'OFFICIAL_KPI_100 template not found'; end if;
    v_cycle:=public.create_kpi_cycle_admin(date '2098-01-01',v_template,now(),now(),now(),now(),false,false);
    select count(*) into v_eval_count from public.kpi_evaluations where cycle_id=v_cycle;
    if v_eval_count=0 then raise exception 'ZERO evaluations created for cycle %', v_cycle; end if;
    raise notice 'Created % evaluations for cycle %', v_eval_count, v_cycle;
  end $$;$t$,
  'create_kpi_cycle_admin creates evaluations'
);

-- 8. Count evaluations for that cycle
reset role;
select ok(
  (select count(*)::int from public.kpi_evaluations where cycle_id in (select id from public.kpi_cycles where period_month='2098-01-01')) > 0,
  'evaluations exist for diagnostic cycle'
);

select * from finish();
rollback;
