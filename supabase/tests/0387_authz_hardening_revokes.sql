-- 0387: تحقق من سحب صلاحيات SECURITY DEFINER من authenticated (mig 0387)
begin;
select plan(5);

-- 1. apply_leave_ledger_entry لا يملكها authenticated
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'apply_leave_ledger_entry'
      and grantee        = 'authenticated'
  ),
  'authenticated لا يملك EXECUTE على apply_leave_ledger_entry (سحبت في 0387)'
);

-- 2. service_role يملك apply_leave_ledger_entry
select ok(
  exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'apply_leave_ledger_entry'
      and grantee        = 'service_role'
  ),
  'service_role يملك EXECUTE على apply_leave_ledger_entry'
);

-- 3. get_cron_health SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_cron_health'
   limit 1),
  true,
  'get_cron_health يجب أن تكون SECURITY DEFINER'
);

-- 4. get_cron_health تتحقق من current_is_full_access
select like(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_cron_health'),
  '%current_is_full_access%',
  'get_cron_health تتحقق من current_is_full_access() — غير مكشوفة للجميع'
);

-- 5. resolve_request_approver لا يملكها authenticated مباشرة
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'resolve_request_approver'
      and grantee        = 'authenticated'
  ),
  'authenticated لا يملك EXECUTE مباشراً على resolve_request_approver (سحبت في 0387)'
);

select finish();
rollback;
