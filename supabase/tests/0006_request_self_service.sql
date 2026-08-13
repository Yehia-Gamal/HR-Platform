begin;
select plan(5);
select has_function('public','submit_my_request',array['text','text','text','jsonb','uuid'],'self-service request function exists');
select function_returns('public','submit_my_request',array['text','text','text','jsonb','uuid'],'requests','returns request row');
select isnt_empty(
  $$ select 1 from information_schema.routine_privileges where routine_schema='public' and routine_name='submit_request' and grantee='authenticated' and privilege_type='EXECUTE' $$,
  'V17: authenticated can invoke the validated submit_request (type-checked internally)'
);
select is_empty(
  $$ select 1 from pg_policies where schemaname='public' and tablename='requests' and cmd='INSERT' $$,
  'requests have no direct authenticated insert policy'
);
select is_empty(
  $$ select 1 from pg_policies where schemaname='public' and tablename='request_actions' and cmd='INSERT' $$,
  'request audit actions cannot be inserted directly'
);
select * from finish();
rollback;
