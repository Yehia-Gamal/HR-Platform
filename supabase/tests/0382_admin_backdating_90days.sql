-- 0382: set_employee_attendance_day_admin — backdating limit 90 days (mig 0383)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(4);

-- 1. الثابت 90 يوماً موجود في جسم الدالة
select alike(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'set_employee_attendance_day_admin' limit 1),
  '%90%',
  'الدالة يجب أن تحتوي على الثابت 90 (حد الأرشفة)'
);

-- 2. ترفض تواريخ المستقبل
select alike(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'set_employee_attendance_day_admin' limit 1),
  '%INVALID_DATE%',
  'الدالة يجب أن ترفض تواريخ المستقبل بـ INVALID_DATE'
);

-- 3. ترفض الأرشفة التاريخية البعيدة
select alike(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'set_employee_attendance_day_admin' limit 1),
  '%BACKDATING_LIMIT%',
  'الدالة يجب أن ترفض الأرشفة >90 يوم بـ BACKDATING_LIMIT'
);

-- 4. الدالة SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'set_employee_attendance_day_admin' limit 1),
  true,
  'set_employee_attendance_day_admin يجب أن تكون SECURITY DEFINER'
);

select finish();
rollback;
