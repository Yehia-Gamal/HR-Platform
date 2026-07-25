-- 0055: V17 §1.7 — official holidays scope & exclusions (migration 0132).
-- Tests: new columns, scope CHECK, is_official_holiday() helper,
-- holidays.manage permission, and RLS policies.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(20);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Structure: new columns on public_holidays
-- ═══════════════════════════════════════════════════════════════════════════════

select has_column('public_holidays', 'scope',
  'public_holidays has scope column');
select has_column('public_holidays', 'department_id',
  'public_holidays has department_id column');
select has_column('public_holidays', 'excluded_department_ids',
  'public_holidays has excluded_department_ids column');
select has_column('public_holidays', 'notes',
  'public_holidays has notes column');

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Scope CHECK constraint
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$do $t$
  declare v_chk text;
  begin
    select pg_get_constraintdef(c.oid) into v_chk
    from pg_constraint c join pg_class r on c.conrelid=r.oid
    where r.relname='public_holidays'
      and c.conname ilike '%scope%'
      and c.contype = 'c';
    if v_chk not ilike '%all%' or v_chk not ilike '%legal_entity%' or v_chk not ilike '%department%' then
      raise exception 'scope CHECK missing expected values';
    end if;
  end $t$$$,
  'scope CHECK accepts all, legal_entity, department'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. is_official_holiday function exists
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'is_official_holiday', array['date','uuid'],
  'is_official_holiday(date,uuid) exists'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. holidays.manage permission seeded
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select count(*)::int from public.permissions where code = 'holidays.manage'),
  1,
  'holidays.manage permission exists'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fixtures
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'a5500000-0000-4000-8000-000000000001';
  v_dept_a uuid := 'a5500000-0000-4000-8000-000000000010';
  v_dept_b uuid := 'a5500000-0000-4000-8000-000000000011';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V17-HOL-LE', 'كيان عطل V17');
  insert into public.departments(id, legal_entity_id, code, name) values
    (v_dept_a, v_entity, 'V17-HOL-DA', 'إدارة أ'),
    (v_dept_b, v_entity, 'V17-HOL-DB', 'إدارة ب');

  -- 3 users: admin (full-access), hr (holidays.manage), employee (read-only)
  insert into auth.users(id, email, aud, role) values
    ('a5500000-0000-4000-8000-000000000101', 'v17hol-admin@test.local', 'authenticated', 'authenticated'),
    ('a5500000-0000-4000-8000-000000000102', 'v17hol-hr@test.local',    'authenticated', 'authenticated'),
    ('a5500000-0000-4000-8000-000000000103', 'v17hol-emp@test.local',   'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, legal_entity_id, status, is_active, is_deleted) values
    ('a5500000-0000-4000-8000-000000000201', 'a5500000-0000-4000-8000-000000000101', 'HL-ADM', 'مدير عطل',    v_dept_a, v_entity, 'active', true, false),
    ('a5500000-0000-4000-8000-000000000202', 'a5500000-0000-4000-8000-000000000102', 'HL-HR',  'أخصائي HR',   v_dept_a, v_entity, 'active', true, false),
    ('a5500000-0000-4000-8000-000000000203', 'a5500000-0000-4000-8000-000000000103', 'HL-EMP', 'موظف عطل',    v_dept_b, v_entity, 'active', true, false);

  insert into public.profiles(id, employee_id, status) values
    ('a5500000-0000-4000-8000-000000000101', 'a5500000-0000-4000-8000-000000000201', 'active'),
    ('a5500000-0000-4000-8000-000000000102', 'a5500000-0000-4000-8000-000000000202', 'active'),
    ('a5500000-0000-4000-8000-000000000103', 'a5500000-0000-4000-8000-000000000203', 'active');

  insert into public.user_roles(user_id, role_id)
  select 'a5500000-0000-4000-8000-000000000101', id from public.roles where slug='admin';
  insert into public.user_roles(user_id, role_id)
  select 'a5500000-0000-4000-8000-000000000102', id from public.roles where slug='hr-specialist';
  insert into public.user_roles(user_id, role_id)
  select 'a5500000-0000-4000-8000-000000000103', id from public.roles where slug='employee';

  -- === Holiday test data ===

  -- Global holiday (scope = 'all')
  insert into public.public_holidays(id, name, holiday_date, end_date, is_active, scope)
  values('a5500000-0000-4000-8000-000000000901', 'عيد الأضحى', '2026-06-15', '2026-06-18', true, 'all');

  -- Entity-scoped holiday
  insert into public.public_holidays(id, name, holiday_date, is_active, scope, legal_entity_id)
  values('a5500000-0000-4000-8000-000000000902', 'إجازة الجهة', '2026-07-01', true, 'legal_entity', v_entity);

  -- Department-scoped holiday (only dept A)
  insert into public.public_holidays(id, name, holiday_date, is_active, scope, department_id)
  values('a5500000-0000-4000-8000-000000000903', 'إجازة إدارة أ', '2026-08-10', true, 'department', v_dept_a);

  -- Global holiday with dept B excluded
  insert into public.public_holidays(id, name, holiday_date, is_active, scope, excluded_department_ids)
  values('a5500000-0000-4000-8000-000000000904', 'عيد وطني (باستثناء إدارة ب)', '2026-09-23', true, 'all',
         array[v_dept_b]::uuid[]);
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
-- 5. is_official_holiday — global holiday applies to all employees
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  public.is_official_holiday('2026-06-16'::date, 'a5500000-0000-4000-8000-000000000201'),
  'global holiday (multi-day): employee in dept A is on holiday on 2026-06-16'
);
select ok(
  public.is_official_holiday('2026-06-16'::date, 'a5500000-0000-4000-8000-000000000203'),
  'global holiday (multi-day): employee in dept B is on holiday on 2026-06-16'
);
select ok(
  not public.is_official_holiday('2026-06-19'::date, 'a5500000-0000-4000-8000-000000000201'),
  'global holiday: day after end_date is NOT a holiday'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. Entity-scoped holiday
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  public.is_official_holiday('2026-07-01'::date, 'a5500000-0000-4000-8000-000000000201'),
  'entity-scoped holiday: employee in same entity sees the holiday'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. Department-scoped holiday
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  public.is_official_holiday('2026-08-10'::date, 'a5500000-0000-4000-8000-000000000201'),
  'department-scoped holiday: employee in dept A sees it'
);
select ok(
  not public.is_official_holiday('2026-08-10'::date, 'a5500000-0000-4000-8000-000000000203'),
  'department-scoped holiday: employee in dept B does NOT see it'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. Exclusion — global holiday with dept B excluded
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  public.is_official_holiday('2026-09-23'::date, 'a5500000-0000-4000-8000-000000000201'),
  'global holiday with exclusion: dept A employee sees it'
);
select ok(
  not public.is_official_holiday('2026-09-23'::date, 'a5500000-0000-4000-8000-000000000203'),
  'global holiday with exclusion: excluded dept B employee does NOT see it'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9. is_official_holiday — no employee → only global holidays
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  public.is_official_holiday('2026-06-15'::date, null),
  'is_official_holiday with null employee matches global holidays'
);
select ok(
  not public.is_official_holiday('2026-08-10'::date, null),
  'is_official_holiday with null employee skips department-scoped'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10. RLS: employee can read holidays (SELECT using(true))
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('a5500000-0000-4000-8000-000000000103');
set local role authenticated;

select ok(
  (select count(*) >= 4 from public.public_holidays where name like '%V17%' or id like 'a5500000%'),
  'employee can SELECT holidays (reference data, using(true))'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11. RLS: employee cannot INSERT holidays
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$insert into public.public_holidays(name, holiday_date, is_active, scope)
    values('عطلة غير مصرح بها', '2026-12-31', true, 'all')$$,
  '42501', null,
  'employee without holidays.manage cannot insert holidays'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 12. RLS: HR specialist CAN insert holidays
-- ═══════════════════════════════════════════════════════════════════════════════

reset role;
select pg_temp.act_as('a5500000-0000-4000-8000-000000000102');
set local role authenticated;

select lives_ok(
  $$insert into public.public_holidays(name, holiday_date, is_active, scope)
    values('عطلة HR تجريبية', '2026-12-25', true, 'all')$$,
  'HR specialist with holidays.manage can insert holidays'
);

reset role;
select * from finish();
rollback;
