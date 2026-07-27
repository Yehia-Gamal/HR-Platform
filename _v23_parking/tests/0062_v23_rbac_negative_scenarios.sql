-- V23 Agent 01 — RBAC/ABAC negative scenarios.
-- 6 categories: HR restriction, KPI isolation, cross-team, self-approval,
-- location authz, committee scope. Uses real auth users with RLS.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,storage,pg_temp;
select plan(16);

-- =====================================================================
-- Fixture
-- =====================================================================
do $fixture$
declare
  v_le uuid:='A5200000-0000-4000-8000-000000000001';
  v_d1 uuid:='A5200000-0000-4000-8000-000000000002';
  v_d2 uuid:='A5200000-0000-4000-8000-000000000003';
  v_perm_id uuid; v_hr_role_id uuid;
begin
  insert into public.legal_entities(id,code,name) values(v_le,'V23-NEG','كيان V23 السلبي');
  insert into public.departments(id,legal_entity_id,code,name) values
    (v_d1,v_le,'V23-D1','إدارة V23 أولى'),
    (v_d2,v_le,'V23-D2','إدارة V23 ثانية');

  insert into auth.users(id,email,aud,role) values
    ('A5000000-0000-4000-8000-000000000001','v23-emp1@test.local','authenticated','authenticated'),
    ('A5000000-0000-4000-8000-000000000002','v23-emp2@test.local','authenticated','authenticated'),
    ('A5000000-0000-4000-8000-000000000003','v23-mgr@test.local','authenticated','authenticated'),
    ('A5000000-0000-4000-8000-000000000004','v23-hr@test.local','authenticated','authenticated'),
    ('A5000000-0000-4000-8000-000000000005','v23-committee@test.local','authenticated','authenticated');

  insert into public.employees(id,user_id,employee_code,full_name_ar,department_id,status,is_active,hire_date) values
    ('A5100000-0000-4000-8000-000000000001','A5000000-0000-4000-8000-000000000001','V23-E1','موظف أول',v_d1,'active',true,current_date-500),
    ('A5100000-0000-4000-8000-000000000002','A5000000-0000-4000-8000-000000000002','V23-E2','موظف ثاني',v_d2,'active',true,current_date-400),
    ('A5100000-0000-4000-8000-000000000003','A5000000-0000-4000-8000-000000000003','V23-MGR','مدير V23',v_d1,'active',true,current_date-600),
    ('A5100000-0000-4000-8000-000000000004','A5000000-0000-4000-8000-000000000004','V23-HR','مسؤول HR',v_d1,'active',true,current_date-700),
    ('A5100000-0000-4000-8000-000000000005','A5000000-0000-4000-8000-000000000005','V23-CM','عضو لجنة',v_d1,'active',true,current_date-300);

  insert into public.profiles(id,employee_id,status)
  select user_id,id,'active' from public.employees where employee_code like 'V23-%';

  -- Roles — use ON CONFLICT for idempotent fixture
  insert into public.user_roles(user_id,role_id,effective_from)
  select x.uid,r.id,now()
  from (values
    ('A5000000-0000-4000-8000-000000000001'::uuid,'employee'),
    ('A5000000-0000-4000-8000-000000000002'::uuid,'employee'),
    ('A5000000-0000-4000-8000-000000000003'::uuid,'employee'),
    ('A5000000-0000-4000-8000-000000000003'::uuid,'direct-manager'),
    ('A5000000-0000-4000-8000-000000000004'::uuid,'hr-manager'),
    ('A5000000-0000-4000-8000-000000000005'::uuid,'employee'),
    ('A5000000-0000-4000-8000-000000000005'::uuid,'committee-member')
  ) x(uid,slug) join public.roles r on r.slug=x.slug;

  -- HR needs access.role.assign permission to enter rpc_assign_role
  select id into v_perm_id from public.permissions where code='access.role.assign';
  if v_perm_id is null then
    insert into public.permissions(code,module,resource,action,description)
    values('access.role.assign','access','role','assign','Assign Role')
    returning id into v_perm_id;
  end if;
  select id into v_hr_role_id from public.roles where slug='hr-manager';
  insert into public.role_permissions(role_id,permission_id,scope)
  values(v_hr_role_id,v_perm_id,'organization')
  on conflict do nothing;

  -- Manager relation: manager → employee1 only (not employee2)
  insert into public.manager_relations(employee_id,manager_employee_id,relation_type,effective_from) values
    ('A5100000-0000-4000-8000-000000000001','A5100000-0000-4000-8000-000000000003','primary',current_date);

  -- KPI cycle + evaluations for isolation test
  insert into public.kpi_cycles(id,period_month,status)
  values('A5300000-0000-4000-8000-000000000001','2098-06-01','open');
  insert into public.kpi_evaluations(employee_id,cycle_id,stage,current_stage) values
    ('A5100000-0000-4000-8000-000000000001','A5300000-0000-4000-8000-000000000001','self','self'),
    ('A5100000-0000-4000-8000-000000000002','A5300000-0000-4000-8000-000000000001','self','self');

  -- Two dispute cases; committee member assigned to the first only
  insert into public.dispute_cases(id,title,description,case_type,status,severity,actor_employee_id,respondent_employee_id) values
    ('A5400000-0000-4000-8000-000000000001','قضية مسندة','وصف','grievance','submitted','normal',
     'A5100000-0000-4000-8000-000000000001','A5100000-0000-4000-8000-000000000002'),
    ('A5400000-0000-4000-8000-000000000002','قضية غير مسندة','وصف','grievance','submitted','normal',
     'A5100000-0000-4000-8000-000000000003','A5100000-0000-4000-8000-000000000004');
  insert into public.committee_members(case_id,employee_id,role_in_committee,is_active)
  values('A5400000-0000-4000-8000-000000000001','A5100000-0000-4000-8000-000000000005','member',true);
end $fixture$;

-- =============================================================================
-- 1. is_capability column — committee roles marked
-- =============================================================================
select ok(
  (select is_capability from public.roles where slug='committee-member'),
  'committee-member role is marked as capability');

-- =============================================================================
-- 2–4. HR restriction — can't access Admin, can't assign senior roles
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"A5000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','A5000000-0000-4000-8000-000000000004',true);

select ok(public.current_is_hr_only(),'current_is_hr_only() returns true for HR user');

select ok(
  (public.get_my_access_context()->'workspaces') ? 'hr'
  and not (public.get_my_access_context()->'workspaces') ? 'main_admin',
  'HR has hr workspace but no main_admin');

-- HR can assign employee role (positive control)
select lives_ok(
  $$select public.rpc_assign_role(
      'A5000000-0000-4000-8000-000000000002',
      (select id from public.roles where slug='employee'),
      null, now(), null)$$,
  'HR can assign employee role');

-- HR cannot assign executive-director
select throws_ok(
  $$select public.rpc_assign_role(
      'A5000000-0000-4000-8000-000000000002',
      (select id from public.roles where slug='executive-director'),
      null, now(), null)$$,
  '42501', null,
  'HR cannot assign executive-director role');

-- HR cannot assign committee-member (capability)
select throws_ok(
  $$select public.rpc_assign_role(
      'A5000000-0000-4000-8000-000000000002',
      (select id from public.roles where slug='committee-member'),
      null, now(), null)$$,
  '42501', null,
  'HR cannot assign committee-member capability');

-- Audit trail recorded for the successful assignment
select ok(
  exists(
    select 1 from public.audit_events
    where event_type='access.role.assigned'
      and metadata->>'target_user_id'='A5000000-0000-4000-8000-000000000002'
  ),
  'audit event recorded for HR role assignment');

-- =============================================================================
-- 5. Employee KPI isolation — can't see another employee's evaluations
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"A5000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','A5000000-0000-4000-8000-000000000001',true);

select is(
  (select count(*)::integer from public.kpi_evaluations
   where cycle_id='A5300000-0000-4000-8000-000000000001'),
  1,
  'employee sees only own KPI evaluation, not others');

select ok(
  not exists(
    select 1 from public.kpi_evaluations
    where employee_id='A5100000-0000-4000-8000-000000000002'
  ),
  'employee cannot see other employee KPI evaluation');

-- =============================================================================
-- 6. Manager cross-team isolation
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"A5000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','A5000000-0000-4000-8000-000000000003',true);

select ok(
  public.can_access_employee('A5100000-0000-4000-8000-000000000001'),
  'manager can access direct report');

select ok(
  not public.can_access_employee('A5100000-0000-4000-8000-000000000002'),
  'manager cannot access employee outside team');

-- =============================================================================
-- 7. Non-executive cannot request live location
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"A5000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','A5000000-0000-4000-8000-000000000001',true);

select throws_ok(
  $$select public.request_live_location(
      'A5100000-0000-4000-8000-000000000002','snapshot','محاولة غير مخولة')$$,
  '42501', null,
  'non-executive employee cannot request live location');

-- =============================================================================
-- 8. Committee member sees only assigned cases
-- =============================================================================
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"A5000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','A5000000-0000-4000-8000-000000000005',true);

select ok(
  public.can_access_dispute('A5400000-0000-4000-8000-000000000001'),
  'committee member can access assigned case');

select ok(
  not public.can_access_dispute('A5400000-0000-4000-8000-000000000002'),
  'committee member cannot access unassigned case');

-- =============================================================================
reset role;
select * from finish();
rollback;
