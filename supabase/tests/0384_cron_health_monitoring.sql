-- =====================================================================
-- 0384: اختبار مراقبة صحة Cron (cron_health_log + process_request_sla + get_cron_health)
-- ─────────────────────────────────────────────────────────────────────
-- التحقق من:
--   ① جدول cron_health_log موجود مع RLS مُقيَّد على full_access
--   ② process_request_sla دالة SECURITY DEFINER مقيدة (service_role / full_access)
--   ③ get_cron_health() موجودة، محجوبة عن anon، مرئية للـ authenticated
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(8);

-- =====================================================================
-- ① بنية الجدول والـ RLS (3 اختبارات)
-- =====================================================================

select has_table(
  'public', 'cron_health_log',
  '0384: جدول cron_health_log موجود'
);

select row_eq(
  $$select relrowsecurity from pg_class where relname = 'cron_health_log'$$,
  row(true),
  '0384: RLS مُفعّل على cron_health_log'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename   = 'cron_health_log'
      and cmd         in ('SELECT', 'ALL')
      and qual        = 'true'
  ),
  '0384: cron_health_log — بدون سياسة SELECT/ALL using(true)'
);

-- =====================================================================
-- ② الدوال موجودة (2 اختبار)
-- =====================================================================

select has_function(
  'public', 'process_request_sla',
  ARRAY['integer'],
  '0384: دالة process_request_sla(integer) موجودة'
);

select has_function(
  'public', 'get_cron_health',
  ARRAY[]::text[],
  '0384: دالة get_cron_health() موجودة'
);

-- =====================================================================
-- Fixture (superuser — إدراج سجل صحة وهمي للاختبار السلوكي)
-- =====================================================================
do $fix$
begin
  insert into public.cron_health_log(job_name, rows_affected, status)
  values ('test_job_0384', 5, 'ok');
end $fix$;

-- =====================================================================
-- ③ سلوكي: موظف عادي (2 اختبار)
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000099', true);
end $$;
set local role authenticated;

-- الموظف العادي لا يرى سجلات cron_health (full_access فقط)
select is(
  (select count(*)::int from public.cron_health_log),
  0,
  '0384 سلوكي: الموظف العادي يرى 0 سجلات cron_health_log'
);

-- process_request_sla مرفوضة على الموظف العادي (EXECUTE مُسحوب → رفض على مستوى الامتياز)
select throws_ok(
  $$select public.process_request_sla()$$,
  '42501', null,
  '0384 سلوكي: process_request_sla ترفض الموظف غير المخوّل (permission denied)'
);

-- =====================================================================
-- ④ سلوكي: مجهول — get_cron_health محجوبة (1 اختبار)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
set local role anon;

select throws_ok(
  $$select * from public.get_cron_health()$$,
  '42501', null,
  '0384 سلوكي: مجهول (anon) محجوب من get_cron_health()'
);

-- =====================================================================
reset role;
select * from finish();
rollback;
