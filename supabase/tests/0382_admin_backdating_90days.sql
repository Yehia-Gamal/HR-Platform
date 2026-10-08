-- 0382: set_employee_attendance_day_admin — backdating limit (mig 0383 ثم 0501)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(4);

-- 1. ثابت حد الأرشفة موجود في جسم الدالة
-- 0501 رفعت الحد من 90 إلى 180 يوماً ضمن «تبسيط وتطوير تعديل أيام الحضور»،
-- وأعادت 0578 تأكيد 180 يوماً — فالحارس ما زال مفروضاً لكن بسقف 180 يوماً.
select alike(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'set_employee_attendance_day_admin' limit 1),
  '%older than 180 days%',
  'الدالة يجب أن تحتوي على ثابت حد الأرشفة 180 يوماً (0383 ثم 0501/0578)'
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
  'الدالة يجب أن ترفض الأرشفة >180 يوم بـ BACKDATING_LIMIT'
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
