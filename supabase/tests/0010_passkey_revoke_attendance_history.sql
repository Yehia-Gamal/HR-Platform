begin;
select plan(8);

select has_function('public','revoke_my_passkey',array['uuid','text']);
select has_function('public','get_my_attendance_history',array['integer','timestamp with time zone']);

select function_privs_are(
  'public','revoke_my_passkey',array['uuid','text'],'authenticated',array['EXECUTE'],
  'authenticated can execute controlled self passkey revocation'
);
select function_privs_are(
  'public','get_my_attendance_history',array['integer','timestamp with time zone'],'authenticated',array['EXECUTE'],
  'authenticated can read personal attendance history through RPC'
);

select isnt_empty(
  $$select 1 from pg_indexes where schemaname='public' and indexname='idx_passkey_credentials_owner_created'$$,
  'passkey owner history index exists'
);
select isnt_empty(
  $$select 1 from pg_indexes where schemaname='public' and indexname='idx_attendance_events_employee_recent'$$,
  'recent personal attendance index exists'
);

select is(
  has_table_privilege('authenticated','public.passkey_credentials','UPDATE'),
  false,
  'authenticated still has no direct update privilege on passkey credentials'
);
select is(
  has_table_privilege('authenticated','public.attendance_events','INSERT'),
  false,
  'authenticated still has no direct insert privilege on attendance events'
);

select * from finish();
rollback;
