-- 0027: Persona RLS runtime matrix (P0.4).
-- Runs real persona contexts (JWT claims + role switch) against live RLS
-- policies and server-authoritative RPCs. Everything rolls back.
--
-- Personas covered:
--   employee, peer employee, direct manager, department manager, HR manager,
--   executive director, committee member, unauthorized authenticated, anonymous.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(23);

-- =====================================================================
-- Fixture (inserted as superuser; RLS not yet in play)
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'aaaaaaaa-0000-4000-8000-000000000000';
  v_dept_a uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  v_dept_b uuid := 'aaaaaaaa-0000-4000-8000-000000000002';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'RLS-LE', 'كيان اختبار RLS');
  insert into public.departments (id, legal_entity_id, code, name) values
    (v_dept_a, v_le, 'RLS-A', 'إدارة أ'),
    (v_dept_b, v_le, 'RLS-B', 'إدارة ب');

  -- auth users
  insert into auth.users (id, email, aud, role)
  values
    ('22222222-0000-4000-8000-000000000001', 'rls-emp@test.local',     'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000002', 'rls-peer@test.local',    'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000003', 'rls-mgr@test.local',     'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000004', 'rls-deptmgr@test.local', 'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000005', 'rls-hr@test.local',      'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000006', 'rls-exec@test.local',    'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000007', 'rls-comm@test.local',    'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000008', 'rls-none@test.local',    'authenticated', 'authenticated');

  -- employees (7 total: dept A = emp, mgr, deptmgr / dept B = peer, hr, exec, comm)
  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active)
  values
    ('11111111-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000001', 'RLS-001', 'موظف الاختبار',        v_dept_a, 'active', true),
    ('11111111-0000-4000-8000-000000000002', '22222222-0000-4000-8000-000000000002', 'RLS-002', 'زميل إدارة أخرى',      v_dept_b, 'active', true),
    ('11111111-0000-4000-8000-000000000003', '22222222-0000-4000-8000-000000000003', 'RLS-003', 'المدير المباشر',       v_dept_a, 'active', true),
    ('11111111-0000-4000-8000-000000000004', '22222222-0000-4000-8000-000000000004', 'RLS-004', 'مدير الإدارة',         v_dept_a, 'active', true),
    ('11111111-0000-4000-8000-000000000005', '22222222-0000-4000-8000-000000000005', 'RLS-005', 'مدير الموارد البشرية', v_dept_b, 'active', true),
    ('11111111-0000-4000-8000-000000000006', '22222222-0000-4000-8000-000000000006', 'RLS-006', 'المدير التنفيذي',      v_dept_b, 'active', true),
    ('11111111-0000-4000-8000-000000000007', '22222222-0000-4000-8000-000000000007', 'RLS-007', 'عضو اللجنة',           v_dept_b, 'active', true);

  -- profiles (current_employee_id resolves via profiles)
  insert into public.profiles (id, employee_id, status)
  select u, e, 'active' from (values
    ('22222222-0000-4000-8000-000000000001'::uuid, '11111111-0000-4000-8000-000000000001'::uuid),
    ('22222222-0000-4000-8000-000000000002'::uuid, '11111111-0000-4000-8000-000000000002'::uuid),
    ('22222222-0000-4000-8000-000000000003'::uuid, '11111111-0000-4000-8000-000000000003'::uuid),
    ('22222222-0000-4000-8000-000000000004'::uuid, '11111111-0000-4000-8000-000000000004'::uuid),
    ('22222222-0000-4000-8000-000000000005'::uuid, '11111111-0000-4000-8000-000000000005'::uuid),
    ('22222222-0000-4000-8000-000000000006'::uuid, '11111111-0000-4000-8000-000000000006'::uuid),
    ('22222222-0000-4000-8000-000000000007'::uuid, '11111111-0000-4000-8000-000000000007'::uuid)
  ) as t(u, e);

  -- role assignments (from seeded system roles)
  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('22222222-0000-4000-8000-000000000001'::uuid, 'employee'),
    ('22222222-0000-4000-8000-000000000002'::uuid, 'employee'),
    ('22222222-0000-4000-8000-000000000003'::uuid, 'employee'),
    ('22222222-0000-4000-8000-000000000003'::uuid, 'direct-manager'),
    ('22222222-0000-4000-8000-000000000004'::uuid, 'employee'),
    ('22222222-0000-4000-8000-000000000004'::uuid, 'department-manager'),
    ('22222222-0000-4000-8000-000000000005'::uuid, 'hr-manager'),
    ('22222222-0000-4000-8000-000000000006'::uuid, 'executive-director'),
    ('22222222-0000-4000-8000-000000000007'::uuid, 'committee-member')
  ) as t(u, slug)
  join public.roles r on r.slug = t.slug;

  -- management relation: emp reports to mgr
  insert into public.manager_relations (employee_id, manager_employee_id, relation_type)
  values ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000003', 'primary');

  -- one pending generic request from emp, assigned to mgr
  insert into public.requests (id, request_type, employee_id, manager_employee_id, status, workflow_status, title)
  values ('33333333-0000-4000-8000-000000000001', 'generic',
          '11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000003',
          'pending', 'submitted', 'طلب اختبار RLS');
end
$fixture$;

-- =====================================================================
-- Persona 1: Employee — self only
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.employees), 1,
  'employee sees own employee row only');
select is((select count(*)::int from public.employees where id = '11111111-0000-4000-8000-000000000002'), 0,
  'employee cannot read another employee via direct API select');
select is((select count(*)::int from public.requests), 1,
  'employee sees own requests only');
select throws_ok(
  $$select public.decide_request('33333333-0000-4000-8000-000000000001', 'approve', 'محاولة ذاتية')$$,
  '42501', null,
  'self-approval is rejected');
select throws_ok(
  $$insert into public.attendance_events (employee_id, event_type) values ('11111111-0000-4000-8000-000000000001', 'CHECK_IN')$$,
  '42501', null,
  'direct write to attendance_events is rejected');
select throws_ok(
  $$select public.record_attendance_event('11111111-0000-4000-8000-000000000001'::uuid, 'CHECK_IN', 24.7::double precision, 46.7::double precision, 10::numeric, 'mobile'::text, null::text, null::uuid, false, false)$$,
  '42501', null,
  'employee cannot call trusted attendance RPC directly');

-- =====================================================================
-- Persona 2: Peer employee (other department)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.requests where employee_id = '11111111-0000-4000-8000-000000000001'), 0,
  'peer cannot see another employee''s requests');
select throws_ok(
  $$select public.decide_request('33333333-0000-4000-8000-000000000001', 'approve', 'غير مخول')$$,
  '42501', null,
  'unauthorized employee cannot decide someone else''s request');

-- =====================================================================
-- Persona 3: Direct manager — direct reports only
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000003', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.employees), 2,
  'direct manager sees self and direct reports only');
select is((select count(*)::int from public.employees where id = '11111111-0000-4000-8000-000000000002'), 0,
  'direct manager cannot see employees outside own reports');
select lives_ok(
  $$select public.decide_request('33333333-0000-4000-8000-000000000001', 'approve', 'موافقة المدير')$$,
  'assigned manager approves direct report''s pending request');

reset role;
select is((select status from public.requests where id = '33333333-0000-4000-8000-000000000001'), 'approved',
  'manager decision persisted and closed the single-step request');

-- =====================================================================
-- Persona 4: Department manager — department scope only
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000004', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.employees), 3,
  'department manager sees own department scope only');
select is((select count(*)::int from public.employees
           where department_id = 'aaaaaaaa-0000-4000-8000-000000000002'), 0,
  'department manager cannot read the other department');

-- =====================================================================
-- Persona 5: HR manager — organization read, but no direct writes
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000005', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.employees
           where id between '11111111-0000-4000-8000-000000000001'
                        and '11111111-0000-4000-8000-000000000007'), 7,
  'HR manager reads all organization fixture employees');
select throws_ok(
  $$insert into public.employees (employee_code, full_name_ar) values ('RLS-X', 'إدراج مباشر')$$,
  '42501', null,
  'HR cannot insert employees directly (must use provisioning RPC)');

-- =====================================================================
-- Persona 6: Executive director — org read, no self punch via trusted RPC
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000006","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000006', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.employees
           where id between '11111111-0000-4000-8000-000000000001'
                        and '11111111-0000-4000-8000-000000000007'), 7,
  'executive director reads all organization fixture employees');
select throws_ok(
  $$select public.record_attendance_event('11111111-0000-4000-8000-000000000006'::uuid, 'CHECK_IN', 24.7::double precision, 46.7::double precision, 10::numeric, 'mobile'::text, null::text, null::uuid, false, false)$$,
  '42501', null,
  'executive cannot self-punch through the trusted attendance RPC');

-- =====================================================================
-- Persona 7: Committee member — no cases assigned => self only
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000007","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000007', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.employees), 1,
  'committee member without assigned cases sees self only');

-- =====================================================================
-- Persona 8: Unauthorized authenticated user (no employee, no roles)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000008","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000008', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.employees), 0,
  'unauthorized authenticated user sees no employees');
select throws_ok(
  $$select public.decide_request('33333333-0000-4000-8000-000000000001', 'approve', 'بدون موظف')$$,
  '42501', null,
  'user without linked employee cannot decide requests');

-- =====================================================================
-- Persona 9: Anonymous
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
set local role anon;

select is((select count(*)::int from public.employees), 0,
  'anonymous sees no employees');
select is((select count(*)::int from public.requests), 0,
  'anonymous sees no requests');

reset role;
select * from finish();
rollback;
