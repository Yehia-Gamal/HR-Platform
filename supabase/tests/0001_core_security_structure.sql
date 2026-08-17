begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(15);

select has_table('public', 'employees', 'employees table exists');
select has_table('public', 'attendance_events', 'attendance_events table exists');
select has_table('public', 'requests', 'requests table exists');
select has_table('public', 'request_steps', 'request_steps table exists');
select has_table('public', 'passkey_credentials', 'passkey_credentials table exists');

select has_function(
  'public', 'can_access_employee', array['uuid','text'],
  'scope-aware can_access_employee exists'
);
select has_function(
  'public', 'decide_request', array['uuid','text','text'],
  'multi-stage decide_request exists'
);
select has_function(
  'public', 'record_attendance_event',
  array['uuid','text','double precision','double precision','numeric','text','text','uuid','boolean','boolean'],
  'trusted attendance RPC exists'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.employees'::regclass),
  'RLS enabled on employees'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.attendance_events'::regclass),
  'RLS enabled on attendance_events'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.requests'::regclass),
  'RLS enabled on requests'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_attendance_event(uuid,text,double precision,double precision,numeric,text,text,uuid,boolean,boolean)',
    'EXECUTE'
  ),
  'authenticated cannot execute trusted attendance RPC directly'
);

-- لا سياسة إدراج خام/مفتوحة على attendance_events: أي سياسة INSERT موجودة
-- يجب أن تكون مقيدة بالصلاحية (with_check عبر can_access_employee) — بلا
-- using(true) أو with_check مفتوح. (0429 استبدلت غياب السياسة بسياسة مقيدة.)
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'public' and tablename = 'attendance_events' and cmd = 'INSERT'
     and (with_check is null or with_check = 'true')),
  0,
  'no open/unscoped INSERT policy on attendance_events'
);

select ok(
  (select bool_and(with_check like '%can_access_employee%')
     from pg_policies
    where schemaname = 'public' and tablename = 'attendance_events' and cmd = 'INSERT'),
  'any INSERT policy on attendance_events must be permission-scoped'
);

select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'public' and tablename = 'passkey_credentials' and cmd in ('INSERT','UPDATE','DELETE')),
  0,
  'passkey credentials have no direct authenticated write policies'
);

select * from finish();
rollback;
