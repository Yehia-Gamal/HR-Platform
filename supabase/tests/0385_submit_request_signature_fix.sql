-- 0385: submit_my_request — signature fix from mig 0386 (removed broken overload)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(4);

-- 1. الدالة الصحيحة (5 معاملات) موجودة
select has_function(
  'public', 'submit_my_request',
  array['text','text','text','jsonb','uuid'],
  'submit_my_request(text,text,text,jsonb,uuid) الإصدار الصحيح موجود'
);

-- 2. الدالة SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'submit_my_request'
   limit 1),
  true,
  'submit_my_request يجب أن تكون SECURITY DEFINER'
);

-- 3. _request_idempotency_key دالة مساعدة IMMUTABLE
select is(
  (select provolatile::text from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_request_idempotency_key'),
  'i'::text,
  '_request_idempotency_key يجب أن تكون IMMUTABLE'
);

-- 4. anon لا يملك EXECUTE
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'submit_my_request'
      and grantee        = 'anon'
  ),
  'anon لا يملك EXECUTE على submit_my_request'
);

select finish();
rollback;
