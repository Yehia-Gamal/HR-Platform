-- 0357: اختبارات RPC لوحة التحليلات الموحّدة
begin;
select plan(6);

select has_function(
  'public', 'get_analytics_dashboard', array['integer'],
  'get_analytics_dashboard(integer) موجودة'
);

select throws_like(
  $$ select public.get_analytics_dashboard() $$,
  '%ERR_UNAUTHENTICATED%',
  'ترفض الطلب غير المصادق'
);

select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'get_analytics_dashboard'
      and grantee        = 'anon'
  ),
  'anon لا يملك EXECUTE على get_analytics_dashboard'
);

select ok(
  exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'get_analytics_dashboard'
      and grantee        = 'authenticated'
  ),
  'authenticated يملك EXECUTE على get_analytics_dashboard'
);

select ok(
  (
    select provolatile = 's'
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_analytics_dashboard'
  ),
  'الدالة STABLE'
);

select ok(
  (
    select prosecdef = true
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_analytics_dashboard'
  ),
  'الدالة SECURITY DEFINER'
);

select finish();
rollback;
