-- 0381: apply_leave_ledger_entry — advisory lock + consume balance guard (mig 0382)
begin;
select plan(5);

-- 1. الدالة موجودة
select has_function(
  'public', 'apply_leave_ledger_entry',
  array['integer','integer','text','numeric','date','date','uuid'],
  'apply_leave_ledger_entry(integer,integer,text,numeric,date,date,uuid) موجودة'
);

-- 2. SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'apply_leave_ledger_entry'),
  true,
  'apply_leave_ledger_entry يجب أن تكون SECURITY DEFINER'
);

-- 3. تحتوي على advisory lock
select like(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'apply_leave_ledger_entry'),
  '%pg_advisory_xact_lock%',
  'يجب أن تستخدم pg_advisory_xact_lock لمنع السباق'
);

-- 4. تتحقق من كفاية الرصيد
select like(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'apply_leave_ledger_entry'),
  '%INSUFFICIENT_LEAVE_BALANCE%',
  'يجب أن ترفع INSUFFICIENT_LEAVE_BALANCE عند نقص الرصيد'
);

-- 5. anon لا يملك EXECUTE
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'apply_leave_ledger_entry'
      and grantee        = 'anon'
  ),
  'anon لا يملك EXECUTE على apply_leave_ledger_entry'
);

select finish();
rollback;
