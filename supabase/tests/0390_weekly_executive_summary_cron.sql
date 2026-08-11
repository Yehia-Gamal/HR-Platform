-- 0390: EXEC_WEEKLY_SUMMARY seed في scheduled_reports (mig 0390)
begin;
select plan(4);

-- 1. السطر موجود في scheduled_reports
select ok(
  exists (
    select 1 from public.scheduled_reports
    where code = 'EXEC_WEEKLY_SUMMARY'
  ),
  'EXEC_WEEKLY_SUMMARY موجود في scheduled_reports'
);

-- 2. مفعّل (active = true)
select is(
  (select active from public.scheduled_reports where code = 'EXEC_WEEKLY_SUMMARY'),
  true,
  'EXEC_WEEKLY_SUMMARY يجب أن يكون active'
);

-- 3. مجدول يوم الأحد (run_weekday = 0)
select is(
  (select run_weekday from public.scheduled_reports where code = 'EXEC_WEEKLY_SUMMARY'),
  0,
  'EXEC_WEEKLY_SUMMARY مجدول يوم الأحد (run_weekday = 0)'
);

-- 4. الساعة 7 صباحاً
select is(
  (select run_hour from public.scheduled_reports where code = 'EXEC_WEEKLY_SUMMARY'),
  7,
  'EXEC_WEEKLY_SUMMARY مجدول الساعة 7:00 صباحاً'
);

select finish();
rollback;
