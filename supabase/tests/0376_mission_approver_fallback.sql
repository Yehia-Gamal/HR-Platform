begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(3);

-- Test 1: function exists (نسخة النظام الحقيقية uuid,date — التوقيع الأجنبي integer,text أُزيل)
select has_function(
  'public', 'resolve_request_approver',
  ARRAY['uuid','date'],
  'resolve_request_approver(uuid,date) should exist'
);

-- Test 2: function contains guaranteed hr-manager fallback
select alike(
  (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='resolve_request_approver'),
  '%hr-manager%',
  'function should have hr-manager as guaranteed fallback'
);

-- Test 3: function returns approver uuid (لا يترك الطلب بلا معتمِد)
select is(
  (select pg_get_function_result(p.oid) from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='resolve_request_approver'),
  'uuid',
  'function should return approver uuid'
);

select finish();
rollback;
