begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(17);

select has_table('public', 'attendance_punch_attempts', 'attendance attempt ledger exists');
select col_is_pk('public', 'attendance_punch_attempts', 'operation_id', 'operation UUID is the idempotency key');
select has_column('public', 'attendance_punch_attempts', 'correlation_id', 'correlation ID is persisted');
select has_column('public', 'attendance_punch_attempts', 'challenge_id', 'challenge linkage is persisted');
select has_column('public', 'attendance_punch_attempts', 'attendance_event_id', 'result event linkage is persisted');
select has_index('public', 'attendance_punch_attempts', 'ux_attendance_punch_challenge', 'one operation can consume a challenge');
select has_index('public', 'attendance_punch_attempts', 'ix_attendance_punch_correlation', 'correlation lookup is indexed');
select ok((select relrowsecurity from pg_class where oid = 'public.attendance_punch_attempts'::regclass), 'attempt ledger has RLS enabled');
select ok(not has_table_privilege('authenticated', 'public.attendance_punch_attempts', 'SELECT'), 'authenticated cannot read attempt ledger');
select ok(not has_table_privilege('authenticated', 'public.attendance_punch_attempts', 'INSERT'), 'authenticated cannot insert attempts');
select ok(not has_table_privilege('authenticated', 'public.attendance_punch_attempts', 'UPDATE'), 'authenticated cannot alter attempts');
select has_function(
  'public', 'finalize_verified_attendance',
  array['uuid','uuid','uuid','uuid','uuid','uuid','text','double precision','double precision','double precision','bigint','text','boolean'],
  'atomic attendance finalizer exists'
);
select function_privs_are(
  'public', 'finalize_verified_attendance',
  array['uuid','uuid','uuid','uuid','uuid','uuid','text','double precision','double precision','double precision','bigint','text','boolean'],
  'authenticated', array[]::text[], 'authenticated cannot call finalizer'
);
select function_privs_are(
  'public', 'finalize_verified_attendance',
  array['uuid','uuid','uuid','uuid','uuid','uuid','text','double precision','double precision','double precision','bigint','text','boolean'],
  'service_role', array['EXECUTE'], 'service role can call finalizer'
);
select ok(
  position('for update' in lower(pg_get_functiondef(
    'public.finalize_verified_attendance(uuid,uuid,uuid,uuid,uuid,uuid,text,double precision,double precision,double precision,bigint,text,boolean)'::regprocedure
  ))) > 0,
  'finalizer locks idempotency, challenge, and credential rows'
);
select ok(
  position('record_attendance_event' in pg_get_functiondef(
    'public.finalize_verified_attendance(uuid,uuid,uuid,uuid,uuid,uuid,text,double precision,double precision,double precision,bigint,text,boolean)'::regprocedure
  )) > 0,
  'finalizer records attendance inside the same transaction'
);
select ok(
  position('used_at = now()' in pg_get_functiondef(
    'public.finalize_verified_attendance(uuid,uuid,uuid,uuid,uuid,uuid,text,double precision,double precision,double precision,bigint,text,boolean)'::regprocedure
  )) > 0,
  'challenge consumption is inside the finalizer'
);

select * from finish();
rollback;
