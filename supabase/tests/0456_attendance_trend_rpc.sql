-- pgTAP test for migration 0456: attendance trend RPC
-- Validates:
--   ① function exists with correct signature, returns jsonb, granted to authenticated
--   ② security invoker (no security definer) — RLS scopes rows naturally
--   ③ shape: empty org → '[]'; days param guard via greatest()

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(6);

select has_function(
  'public', 'get_mobile_attendance_trend', array['int'],
  '0456: دالة اتجاه الحضور بالتوقيع الصحيح');

select function_returns(
  'public', 'get_mobile_attendance_trend', array['int'], 'jsonb',
  '0456: تعيد jsonb');

select function_privs_are(
  'public', 'get_mobile_attendance_trend', array['int'],
  'authenticated', array['EXECUTE'],
  '0456: authenticated ينفذها');

-- security invoker (وليس definer) — RLS يبقى مطبقاً على attendance_daily
select ok(
  (select prosecdef = false from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_mobile_attendance_trend'),
  '0456: الدالة security invoker — تحترم RLS');

-- قاعدة فارغة → []
select is(
  (select public.get_mobile_attendance_trend(14)::text),
  '[]'::jsonb::text,
  '0456: قاعدة بلا بيانات تعيد مصفوفة فارغة');

-- أيام أقل من 1 → greatest يحمي من مدى صفر أو سالب (لا استثناء)
select ok(
  (select jsonb_typeof(public.get_mobile_attendance_trend(0)) = 'array'),
  '0456: p_days=0 يعيد مصفوفة سليمة بلا خطأ');

select * from finish();
rollback;