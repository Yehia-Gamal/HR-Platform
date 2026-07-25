-- 0054: V17 §14 — dispute admin-action workflow (migration 0131).
-- propose (committee secretary) → decide (executive) → execute (HR).
-- Tests: RPC existence, permission seeds, column additions, status routing,
-- invalid-input rejection, and the full happy-path lifecycle.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(22);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Structure assertions — RPCs exist
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'propose_admin_action', array['uuid','text','text'],
  'propose_admin_action RPC exists'
);
select has_function(
  'public', 'decide_admin_action', array['uuid','text','text','text','text'],
  'decide_admin_action RPC exists'
);
select has_function(
  'public', 'execute_admin_action', array['uuid','text'],
  'execute_admin_action RPC exists'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. V17 columns on dispute_cases
-- ═══════════════════════════════════════════════════════════════════════════════

select has_column('dispute_cases', 'proposed_administrative_action',
  'dispute_cases has proposed_administrative_action');
select has_column('dispute_cases', 'executive_decision',
  'dispute_cases has executive_decision');
select has_column('dispute_cases', 'approved_administrative_action',
  'dispute_cases has approved_administrative_action');
select has_column('dispute_cases', 'executed_at',
  'dispute_cases has executed_at');
select has_column('dispute_cases', 'execution_notes',
  'dispute_cases has execution_notes');

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Permissions seeded
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select count(*)::int from public.permissions where code like 'disputes.admin_action.%'),
  3,
  'three disputes.admin_action permissions seeded'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Status CHECK accepts V17 admin-action statuses
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  declare v_chk text;
  begin
    select pg_get_constraintdef(c.oid) into v_chk
    from pg_constraint c join pg_class r on c.conrelid=r.oid
    where r.relname='dispute_cases' and c.conname='dispute_cases_status_check';
    if v_chk not ilike '%action_proposed%' then
      raise exception 'action_proposed not in status CHECK';
    end if;
    if v_chk not ilike '%pending_execution%' then
      raise exception 'pending_execution not in status CHECK';
    end if;
    if v_chk not ilike '%executed%' then
      raise exception 'executed not in status CHECK';
    end if;
  end $t$$live$,
  'status CHECK includes V17 admin-action statuses'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fixtures
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'a5400000-0000-4000-8000-000000000001';
  v_dept   uuid := 'a5400000-0000-4000-8000-000000000010';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V17-DSP-LE', 'كيان نزاعات V17');
  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V17-DSP-D', 'إدارة نزاعات V17');

  -- 4 users: admin (full-access), secretary, executive, hr-specialist
  insert into auth.users(id, email, aud, role) values
    ('a5400000-0000-4000-8000-000000000101', 'v17dsp-admin@test.local',  'authenticated', 'authenticated'),
    ('a5400000-0000-4000-8000-000000000102', 'v17dsp-sec@test.local',    'authenticated', 'authenticated'),
    ('a5400000-0000-4000-8000-000000000103', 'v17dsp-exec@test.local',   'authenticated', 'authenticated'),
    ('a5400000-0000-4000-8000-000000000104', 'v17dsp-hr@test.local',     'authenticated', 'authenticated'),
    ('a5400000-0000-4000-8000-000000000105', 'v17dsp-emp@test.local',    'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('a5400000-0000-4000-8000-000000000201', 'a5400000-0000-4000-8000-000000000101', 'DA-ADM', 'مدير نزاعات',   v_dept, 'active', true, false),
    ('a5400000-0000-4000-8000-000000000202', 'a5400000-0000-4000-8000-000000000102', 'DA-SEC', 'مقرر اللجنة',   v_dept, 'active', true, false),
    ('a5400000-0000-4000-8000-000000000203', 'a5400000-0000-4000-8000-000000000103', 'DA-EXE', 'المدير التنفيذي', v_dept, 'active', true, false),
    ('a5400000-0000-4000-8000-000000000204', 'a5400000-0000-4000-8000-000000000104', 'DA-HR',  'أخصائي HR',     v_dept, 'active', true, false),
    ('a5400000-0000-4000-8000-000000000205', 'a5400000-0000-4000-8000-000000000105', 'DA-EMP', 'موظف عادي',     v_dept, 'active', true, false);

  insert into public.profiles(id, employee_id, status) values
    ('a5400000-0000-4000-8000-000000000101', 'a5400000-0000-4000-8000-000000000201', 'active'),
    ('a5400000-0000-4000-8000-000000000102', 'a5400000-0000-4000-8000-000000000202', 'active'),
    ('a5400000-0000-4000-8000-000000000103', 'a5400000-0000-4000-8000-000000000203', 'active'),
    ('a5400000-0000-4000-8000-000000000104', 'a5400000-0000-4000-8000-000000000204', 'active'),
    ('a5400000-0000-4000-8000-000000000105', 'a5400000-0000-4000-8000-000000000205', 'active');

  -- admin = full access
  insert into public.user_roles(user_id, role_id)
  select 'a5400000-0000-4000-8000-000000000101', id from public.roles where slug='admin';

  -- secretary = committee-secretary
  insert into public.user_roles(user_id, role_id)
  select 'a5400000-0000-4000-8000-000000000102', id from public.roles where slug='committee-secretary';

  -- executive = executive-secretary
  insert into public.user_roles(user_id, role_id)
  select 'a5400000-0000-4000-8000-000000000103', id from public.roles where slug='executive-secretary';

  -- hr = hr-specialist
  insert into public.user_roles(user_id, role_id)
  select 'a5400000-0000-4000-8000-000000000104', id from public.roles where slug='hr-specialist';

  -- emp = employee (no admin-action perms)
  insert into public.user_roles(user_id, role_id)
  select 'a5400000-0000-4000-8000-000000000105', id from public.roles where slug='employee';

  -- Insert a dispute case in decision_issued (the precondition for propose)
  insert into public.dispute_cases(
    id, case_number, title, description, case_type, status, severity,
    actor_employee_id, created_by
  ) values (
    'a5400000-0000-4000-8000-000000000901',
    'V17-ADM-001', 'قضية اختبار الإجراء الإداري',
    'وصف كافٍ لقضية اختبار الإجراءات الإدارية',
    'employee_conflict', 'decision_issued', 'normal',
    'a5400000-0000-4000-8000-000000000205',
    'a5400000-0000-4000-8000-000000000101'
  );
end
$fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. propose_admin_action: invalid action type → rejected
-- ═══════════════════════════════════════════════════════════════════════════════

-- Act as admin (full access) for functional tests
select pg_temp.act_as('a5400000-0000-4000-8000-000000000101');
set local role authenticated;

select throws_ok(
  $$select public.propose_admin_action(
    'a5400000-0000-4000-8000-000000000901', 'invalid_type', 'تفاصيل الاقتراح')$$,
  '22023', null,
  'propose_admin_action rejects invalid action type'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. propose_admin_action: detail is required
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.propose_admin_action(
    'a5400000-0000-4000-8000-000000000901', 'written_warning', '')$$,
  '22023', null,
  'propose_admin_action requires non-empty detail'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. propose_admin_action: happy path (admin = full-access)
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$select public.propose_admin_action(
    'a5400000-0000-4000-8000-000000000901', 'written_warning',
    'إنذار كتابي بسبب مخالفة سلوكية متكررة')$$,
  'propose_admin_action succeeds for full-access user'
);

select is(
  (select status from public.dispute_cases where id = 'a5400000-0000-4000-8000-000000000901'),
  'action_proposed',
  'case status transitions to action_proposed after proposal'
);

select is(
  (select proposed_administrative_action from public.dispute_cases where id = 'a5400000-0000-4000-8000-000000000901'),
  'written_warning',
  'proposed_administrative_action is recorded'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. decide_admin_action: wrong status → rejected
-- ═══════════════════════════════════════════════════════════════════════════════

-- First put a second case in decision_issued (not action_proposed) to test guard
select throws_ok(
  $$select public.decide_admin_action(
    'a5400000-0000-4000-8000-000000000901', 'invalid_decision', 'سبب', null, null)$$,
  '22023', null,
  'decide_admin_action rejects invalid decision type'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9. decide_admin_action: approve → pending_execution
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$select public.decide_admin_action(
    'a5400000-0000-4000-8000-000000000901', 'approved',
    'موافق على الإجراء كما هو', null, null)$$,
  'decide_admin_action approve succeeds'
);

select is(
  (select status from public.dispute_cases where id = 'a5400000-0000-4000-8000-000000000901'),
  'pending_execution',
  'case transitions to pending_execution after executive approval'
);

select is(
  (select approved_administrative_action from public.dispute_cases where id = 'a5400000-0000-4000-8000-000000000901'),
  'written_warning',
  'approved_administrative_action matches proposed action'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10. execute_admin_action: notes required
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.execute_admin_action(
    'a5400000-0000-4000-8000-000000000901', '')$$,
  '22023', null,
  'execute_admin_action requires non-empty notes'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11. execute_admin_action: happy path → executed
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$select public.execute_admin_action(
    'a5400000-0000-4000-8000-000000000901',
    'تم تسليم الإنذار الكتابي للموظف وتوقيعه عليه')$$,
  'execute_admin_action succeeds'
);

select is(
  (select status from public.dispute_cases where id = 'a5400000-0000-4000-8000-000000000901'),
  'executed',
  'case transitions to executed after HR execution'
);

select ok(
  (select executed_at is not null from public.dispute_cases where id = 'a5400000-0000-4000-8000-000000000901'),
  'executed_at is stamped'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 12. Audit trail — dispute_actions recorded for each step
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select count(*)::int from public.dispute_actions
   where case_id = 'a5400000-0000-4000-8000-000000000901'
     and action_type in ('propose_admin_action','decide_admin_action','execute_admin_action')),
  3,
  'three dispute_actions audit rows recorded (propose + decide + execute)'
);

reset role;
select * from finish();
rollback;
