begin;
select plan(10);

select has_function('public', 'get_my_access_context', array[]::text[],
  'get_my_access_context exists');
select function_privs_are(
  'public', 'get_my_access_context', array[]::text[], 'authenticated',
  array['EXECUTE'], 'authenticated can execute access-context RPC'
);
select has_function(
  'public', 'provision_employee_record',
  array['uuid','uuid','text','text','text','text','text','uuid','uuid','uuid','uuid','uuid','uuid','uuid','uuid','uuid','date','boolean','text','text'],
  'transactional employee provisioning RPC exists'
);
select function_privs_are(
  'public', 'provision_employee_record',
  array['uuid','uuid','text','text','text','text','text','uuid','uuid','uuid','uuid','uuid','uuid','uuid','uuid','uuid','date','boolean','text','text'],
  'authenticated', array[]::text[],
  'authenticated cannot provision employees directly'
);
select function_privs_are(
  'public', 'provision_employee_record',
  array['uuid','uuid','text','text','text','text','text','uuid','uuid','uuid','uuid','uuid','uuid','uuid','uuid','uuid','date','boolean','text','text'],
  'anon', array[]::text[],
  'anonymous users cannot provision employees'
);
select ok((select relrowsecurity from pg_class where oid = 'public.employees'::regclass),
  'employees has RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'profiles has RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.user_roles'::regclass),
  'user_roles has RLS');

-- Canonical employee access hardening from migration 0014.
select ok(
  has_function_privilege('authenticated', 'public.provision_employee_record(uuid,uuid,text,text,text,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,date,boolean,text,text)', 'EXECUTE') = false,
  'authenticated cannot provision employees (privilege hardening)'
);
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'employees'
      and cmd in ('INSERT', 'DELETE')
  ),
  'employees have no direct insert or delete policy'
);

select * from finish();
rollback;
