-- 0391: mv_executive_attendance_snapshot + refresh fn + get_executive_attendance_overview (mig 0391)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(6);

-- 1. المنظر المادي موجود
select ok(
  exists (
    select 1 from pg_matviews
    where schemaname = 'public'
      and matviewname = 'mv_executive_attendance_snapshot'
  ),
  'mv_executive_attendance_snapshot موجودة'
);

-- 2. دالة التحديث موجودة
select has_function(
  'public', 'refresh_executive_attendance_snapshot',
  array[]::text[],
  'refresh_executive_attendance_snapshot() موجودة'
);

-- 3. دالة التحديث SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'refresh_executive_attendance_snapshot'),
  true,
  'refresh_executive_attendance_snapshot يجب أن تكون SECURITY DEFINER'
);

-- 4. anon لا يملك EXECUTE على refresh_executive_attendance_snapshot
select ok(
  not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name   = 'refresh_executive_attendance_snapshot'
      and grantee        = 'anon'
  ),
  'لا يملك anon EXECUTE على refresh_executive_attendance_snapshot'
);

-- 5. get_executive_attendance_overview موجودة
select has_function(
  'public', 'get_executive_attendance_overview',
  array['date'],
  'get_executive_attendance_overview(date) موجودة'
);

-- 6. get_executive_attendance_overview تقرأ من MV عند اليوم الحالي
select alike(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_executive_attendance_overview'
   limit 1),
  '%mv_executive_attendance_snapshot%',
  'get_executive_attendance_overview تقرأ من الـ MV للأداء'
);

select finish();
rollback;
