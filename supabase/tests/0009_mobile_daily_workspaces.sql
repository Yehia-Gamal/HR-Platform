begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(17);
select has_function('public', 'get_my_mobile_profile', array[]::text[], 'mobile profile RPC exists');
select has_function('public', 'get_my_mobile_tasks', array['integer'], 'mobile tasks RPC exists');
select has_function('public', 'transition_my_task', array['uuid','text'], 'task transition RPC exists');
select has_function('public', 'get_my_mobile_team', array['integer'], 'mobile team RPC exists');
select has_function('public', 'get_mobile_daily_reports', array['uuid','integer'], 'daily reports RPC exists');
select has_function('public', 'upsert_my_daily_report', array['date','text','text','text'], 'daily report upsert RPC exists');
select has_function('public', 'get_employee_360', array['uuid'], 'employee 360 RPC exists');
select has_function('public', 'review_daily_report', array['uuid','text'], 'daily report review RPC exists');
select has_function('public', 'create_team_task', array['uuid','text','text','text','date'], 'team task creation RPC exists');
select has_column('public', 'daily_reports', 'reviewed_at', 'daily report review time is stored');
select has_index('public', 'daily_reports', 'ux_daily_reports_employee_date', 'daily report uniqueness is enforced');
select has_trigger('public', 'tasks', 'trg_tasks_audit', 'task changes are audited');
select has_trigger('public', 'daily_reports', 'trg_daily_reports_audit', 'daily reports are audited');
select isnt_empty(
  $$ select 1 from information_schema.routine_privileges where routine_schema='public' and routine_name='get_my_mobile_profile' and grantee='authenticated' and privilege_type='EXECUTE' $$,
  'authenticated can execute mobile profile RPC'
);
select is_empty(
  $$ select 1 from pg_policies where schemaname='public' and tablename='tasks' and cmd in ('INSERT','UPDATE','DELETE','ALL') $$,
  'tasks have no direct write policy'
);
select is_empty(
  $$ select 1 from pg_policies where schemaname='public' and tablename='daily_reports' and cmd in ('INSERT','UPDATE','DELETE','ALL') $$,
  'daily reports have no direct write policy'
);
select results_eq(
  $$ select count(*)::bigint from pg_policies where schemaname='public' and tablename='daily_reports' and cmd='SELECT' $$,
  array[1::bigint],
  'daily reports expose one scope-aware read policy'
);
select * from finish();
rollback;
