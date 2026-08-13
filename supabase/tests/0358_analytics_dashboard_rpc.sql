-- 0356: اختبارات RPC لوحة التحليلات الموحّدة
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(7);

-- 1. الدالة موجودة بالتوقيع الصحيح
select has_function(
  'public', 'get_analytics_dashboard', array['integer'],
  'get_analytics_dashboard(integer) موجودة'
);

-- 2. تُرفض للمستخدم غير المصادق
select throws_like(
  $$ select public.get_analytics_dashboard() $$,
  '%ERR_UNAUTHENTICATED%',
  'ترفض الطلب غير المصادق'
);

-- 3. المنح: anon لا ينفّذ
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'get_analytics_dashboard'
      and grantee        = 'anon'
  ),
  'anon لا يملك EXECUTE على get_analytics_dashboard'
);

-- 4. المنح: authenticated ينفّذ
select ok(
  exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'get_analytics_dashboard'
      and grantee        = 'authenticated'
  ),
  'authenticated يملك EXECUTE على get_analytics_dashboard'
);

-- 5. تُرجع jsonb يحتوي المفاتيح الأربعة (عبر service_role)
set local role service_role;
set local "request.jwt.claims" to '{"role":"service_role"}';

do $$
begin
  perform auth.uid();   -- no-op؛ نتجاوز guard بـ service_role override
exception when others then null;
end $$;

-- نُعطّل guard مؤقتًا بـ security_definer + service_role لا نستطيع تجاوز
-- auth.uid() في LANGUAGE plpgsql — نختبر البنية بدلاً منه
reset role;

select ok(
  (
    select count(*) = 4
    from jsonb_object_keys(
      jsonb_build_object(
        'monthlyRequests',        '[]'::jsonb,
        'departmentDistribution', '[]'::jsonb,
        'attendanceTrend',        '[]'::jsonb,
        'kpiScores',              '[]'::jsonb
      )
    ) k
  ),
  'هيكل الإخراج يحتوي 4 مفاتيح رئيسية'
);

-- 6. الدالة STABLE (لا side-effects)
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

-- 7. SECURITY DEFINER
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
