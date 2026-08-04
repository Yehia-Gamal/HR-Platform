-- 0101: conservative RLS gap closure (migration 0260).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(5);

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.employee_compensation'::regclass),
  'employee compensation continues to force RLS'
);

select ok(
  not has_table_privilege('anon', 'public.employee_compensation', 'SELECT'),
  'anon cannot read employee compensation'
);

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.departments'::regclass),
  'organization reference tables force RLS'
);

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.dispute_actions'::regclass),
  'dispute operational tables force RLS'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename in ('employee_compensation', 'payroll_runs', 'payslips')
      and policyname like '%self_or_hr%'
  ),
  'gap closure does not reintroduce permissive financial policies'
);

select * from finish();
rollback;
