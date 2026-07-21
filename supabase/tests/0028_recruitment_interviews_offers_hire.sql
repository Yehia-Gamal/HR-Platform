begin;
select plan(11);

-- The write-side ATS RPCs added in migration 0044 must exist with the exact signatures the web hook calls.
select has_function('public','schedule_interview_admin',
  array['uuid','text','timestamp with time zone','text','uuid[]','uuid'],
  'schedule_interview_admin RPC exists');
select has_function('public','decide_interview_admin',
  array['uuid','text'],
  'decide_interview_admin RPC exists');
select has_function('public','create_job_offer_admin',
  array['uuid','text','numeric','text','date','timestamp with time zone'],
  'create_job_offer_admin RPC exists');
select has_function('public','transition_job_offer_admin',
  array['uuid','text'],
  'transition_job_offer_admin RPC exists');
select has_function('public','hire_from_application_admin',
  array['uuid'],
  'hire_from_application_admin RPC exists');

-- They must be SECURITY DEFINER (sensitive writes behind an explicit permission check).
select is(p.prosecdef, true, 'schedule_interview_admin is SECURITY DEFINER')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'schedule_interview_admin';
select is(p.prosecdef, true, 'create_job_offer_admin is SECURITY DEFINER')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'create_job_offer_admin';
select is(p.prosecdef, true, 'hire_from_application_admin is SECURITY DEFINER')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'hire_from_application_admin';

-- anon must not be able to execute these write RPCs.
select ok(
  not has_function_privilege('anon', 'public.hire_from_application_admin(uuid)', 'execute'),
  'anon cannot execute hire_from_application_admin');
select ok(
  not has_function_privilege('anon', 'public.create_job_offer_admin(uuid,text,numeric,text,date,timestamp with time zone)', 'execute'),
  'anon cannot execute create_job_offer_admin');

-- authenticated must be able to execute (permission is then enforced inside the function body).
select ok(
  has_function_privilege('authenticated', 'public.transition_job_offer_admin(uuid,text)', 'execute'),
  'authenticated may execute transition_job_offer_admin');

select * from finish();
rollback;
