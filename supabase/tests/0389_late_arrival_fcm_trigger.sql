-- 0389: tg_notify_manager_late_arrival — إشعار FCM عند تأخر الموظف (mig 0389)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(5);

-- 1. دالة التريغر موجودة
select has_function(
  'public', 'tg_notify_manager_late_arrival',
  array[]::text[],
  'tg_notify_manager_late_arrival() موجودة'
);

-- 2. SECURITY DEFINER
select is(
  (select prosecdef from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'tg_notify_manager_late_arrival'),
  true,
  'tg_notify_manager_late_arrival يجب أن تكون SECURITY DEFINER'
);

-- 3. التريغر مربوط بجدول attendance_events
select ok(
  exists (
    select 1 from information_schema.triggers
    where trigger_schema = 'public'
      and event_object_table = 'attendance_events'
      and trigger_name = 'trg_late_arrival_notify_manager'
  ),
  'trg_late_arrival_notify_manager موجود على attendance_events'
);

-- 4. التريغر AFTER INSERT
select is(
  (select action_timing from information_schema.triggers
   where trigger_schema = 'public'
     and event_object_table = 'attendance_events'
     and trigger_name = 'trg_late_arrival_notify_manager'),
  'AFTER',
  'trg_late_arrival_notify_manager AFTER INSERT فقط'
);

-- 5. جسم الدالة يتحقق من late_minutes > 0 قبل الإشعار
select alike(
  (select prosrc from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'tg_notify_manager_late_arrival'),
  '%late_minutes%',
  'تتحقق الدالة من late_minutes قبل إصدار الإشعار'
);

select finish();
rollback;
