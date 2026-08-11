-- 0383: resolve_request_approver — guaranteed fallback for missions (mig 0385)
begin;
select plan(5);

-- 1. الدالة موجودة
select has_function(
  'public', 'resolve_request_approver',
  array['integer','text'],
  'resolve_request_approver(integer,text) موجودة'
);

-- 2. SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'resolve_request_approver'),
  true,
  'resolve_request_approver يجب أن تكون SECURITY DEFINER'
);

-- 3. تحتوي على fallback لـ hr-manager
select like(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'resolve_request_approver'),
  '%hr-manager%',
  'الدالة يجب أن تتضمن fallback لـ hr-manager'
);

-- 4. ترفع خطأ واضحاً عند غياب كل المعتمدين
select like(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'resolve_request_approver'),
  '%NO_APPROVER%',
  'الدالة يجب أن ترفع NO_APPROVER عند غياب جميع المعتمدين'
);

-- 5. anon لا يملك EXECUTE
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'resolve_request_approver'
      and grantee        = 'anon'
  ),
  'anon لا يملك EXECUTE على resolve_request_approver'
);

select finish();
rollback;
