-- 0431: تصنيف "بصمة بلا انصراف" (Migration 0431)
-- يثبت أن من بصم حضوراً ولم يُتمم الانصراف:
--   1) يُعدّ حاضراً لليوم (فئة present في اللوحة والقائمة).
--   2) لا يظهر في "بصمات غير مكتملة" (incomplete تقتصر على partial+pending).
--   3) يبقى ظاهراً في فئة missing_checkout ("بصمة بلا انصراف") كتنبيه.
--   4) بعد finalize_missing_checkouts (الآلية الليلية) يتحول صف الحضور إلى
--      status='missing_checkout' مع إنشاء استثناء، ويظل حاضراً لليوم.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(18);

-- =====================================================================
-- Fixture: كيان + إدارة + وردية + موظفان (بصمة بلا انصراف / ساعات ناقصة).
-- =====================================================================
do $fixture$
declare
  v_le      uuid := 'c4310000-0000-4000-8000-000000000001';
  v_dept    uuid := 'c4310000-0000-4000-8000-000000000002';
  v_shift   uuid := 'c4310000-0000-4000-8000-000000000003';
  v_day     date := '2026-08-03'; -- اثنين (ليس الجمعة/العطلة)
begin
  perform set_config('app.t0431_day', to_char(v_day, 'YYYY-MM-DD'), false);

  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0431', 'كيان 0431');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0431', 'إدارة 0431');
  insert into public.shifts(id, code, name, start_time, end_time,
    crosses_midnight, break_minutes, grace_in_minutes, grace_out_minutes, is_active)
    values (v_shift, 'S-0431', 'وردية 0431', '09:00', '17:00', false, 0, 0, 0, true);

  insert into public.employees(id, employee_code, full_name_ar, department_id,
    status, is_active, hire_date)
  values
    ('c4310000-0000-4000-8000-000000000010', 'E-431-MK', 'بصمة بلا انصراف', v_dept, 'active', true, '2020-01-01'),
    ('c4310000-0000-4000-8000-000000000011', 'E-431-PT', 'ساعات ناقصة',     v_dept, 'active', true, '2020-01-01');

  -- حضر بصمة دخول فقط (لم يُتمم الانصراف) — غير منتهٍ → missing_checkout.
  insert into public.attendance_daily(employee_id, work_date, shift_id,
    first_check_in, last_check_out, work_minutes, late_minutes, status, is_finalized)
  values
    ('c4310000-0000-4000-8000-000000000010', v_day, v_shift, '2026-08-03 09:00:00+02', null, 0, 0, 'present', false),
    -- حضر ببصمتين لكن ساعات العمل أقل من المطلوب → partial.
    ('c4310000-0000-4000-8000-000000000011', v_day, v_shift, '2026-08-03 09:00:00+02', '2026-08-03 13:00:00+02', 240, 0, 'partial', true);
end $fixture$;

-- =====================================================================
-- (1) قبل التصفية الليلية: الرسترة واللوحة.
-- =====================================================================
select is(
  (select total from (
     select public.get_attendance_day_roster(
       nullif(current_setting('app.t0431_day', true), '')::date, 'present',
       null, 'c4310000-0000-4000-8000-000000000002') j
   ) x, jsonb_to_record(j) as t(total int) limit 1),
  2,
  'فئة present تضم صاحب البصمة بلا انصراف + صاحب الساعات الناقصة (حاضرون لليوم)'
);

select ok(
  exists (select 1 from jsonb_array_elements(
     (public.get_attendance_day_roster(
       nullif(current_setting('app.t0431_day', true), '')::date, 'present',
       null, 'c4310000-0000-4000-8000-000000000002')->'items')) it
     where it->>'employeeId' = 'c4310000-0000-4000-8000-000000000010'
       and it->>'status' = 'missing_checkout'),
  'صاحب البصمة بلا انصراف يظهر في present بحالة missing_checkout'
);

select is(
  (select total from (
     select public.get_attendance_day_roster(
       nullif(current_setting('app.t0431_day', true), '')::date, 'incomplete',
       null, 'c4310000-0000-4000-8000-000000000002') j
   ) x, jsonb_to_record(j) as t(total int) limit 1),
  1,
  'فئة incomplete تضم صاحب الساعات الناقصة فقط'
);

select ok(
  not exists (select 1 from jsonb_array_elements(
     (public.get_attendance_day_roster(
       nullif(current_setting('app.t0431_day', true), '')::date, 'incomplete',
       null, 'c4310000-0000-4000-8000-000000000002')->'items')) it
     where it->>'employeeId' = 'c4310000-0000-4000-8000-000000000010'),
  'صاحب البصمة بلا انصراف غير موجود في "بصمات غير مكتملة"'
);

select is(
  (select total from (
     select public.get_attendance_day_roster(
       nullif(current_setting('app.t0431_day', true), '')::date, 'missing_checkout',
       null, 'c4310000-0000-4000-8000-000000000002') j
   ) x, jsonb_to_record(j) as t(total int) limit 1),
  1,
  'فئة missing_checkout تبقى مستقلة وتضم صاحب البصمة الناقصة'
);

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0431_day', true), '')::date,
     'c4310000-0000-4000-8000-000000000002')->>'present')::int,
  2,
  'لوحة الحضور: present = 2 (بصمة بلا انصراف + ساعات ناقصة — كلاهما حاضر)'
);

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0431_day', true), '')::date,
     'c4310000-0000-4000-8000-000000000002')->>'incomplete')::int,
  1,
  'لوحة الحضور: incomplete = 1 (الساعات الناقصة فقط)'
);

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0431_day', true), '')::date,
     'c4310000-0000-4000-8000-000000000002')->>'missingCheckout')::int,
  1,
  'لوحة الحضور: missingCheckout = 1 (تنبيه مستقل)'
);

-- =====================================================================
-- (2) بعد التصفية الليلية finalize_missing_checkouts:
--     تتحول الحالة إلى missing_checkout + استثناء، ويبقى حاضراً لليوم.
-- =====================================================================
select ok(
  public.finalize_missing_checkouts() >= 1,
  'finalize_missing_checkouts يصفّي صف البصمة الناقصة'
);

select is(
  (select status from public.attendance_daily
    where employee_id = 'c4310000-0000-4000-8000-000000000010'),
  'missing_checkout',
  'بعد التصفية: حالة صف الحضور missing_checkout (بصمة انصراف ناقصة)'
);

select is(
  (select count(*) from public.attendance_exceptions
    where attendance_daily_id = (select id from public.attendance_daily
      where employee_id = 'c4310000-0000-4000-8000-000000000010')
      and kind = 'missing_check_out'),
  1::bigint,
  'استثناء "بصمة خروج مفقودة" أُنشئ تلقائياً'
);

select is(
  (select total from (
     select public.get_attendance_day_roster(
       nullif(current_setting('app.t0431_day', true), '')::date, 'present',
       null, 'c4310000-0000-4000-8000-000000000002') j
   ) x, jsonb_to_record(j) as t(total int) limit 1),
  2,
  'بعد التصفية: يبقى حاضراً في فئة present'
);

select ok(
  not exists (select 1 from jsonb_array_elements(
     (public.get_attendance_day_roster(
       nullif(current_setting('app.t0431_day', true), '')::date, 'incomplete',
       null, 'c4310000-0000-4000-8000-000000000002')->'items')) it
     where it->>'employeeId' = 'c4310000-0000-4000-8000-000000000010'),
  'بعد التصفية: لا يظهر في "بصمات غير مكتملة"'
);

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0431_day', true), '')::date,
     'c4310000-0000-4000-8000-000000000002')->>'present')::int,
  2,
  'بعد التصفية: لوحة الحضور present = 2'
);

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0431_day', true), '')::date,
     'c4310000-0000-4000-8000-000000000002')->>'incomplete')::int,
  1,
  'بعد التصفية: لوحة الحضور incomplete = 1 (لم يتغير)'
);

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0431_day', true), '')::date,
     'c4310000-0000-4000-8000-000000000002')->>'missingCheckout')::int,
  1,
  'بعد التصفية: لوحة الحضور missingCheckout = 1'
);

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0431_day', true), '')::date,
     'c4310000-0000-4000-8000-000000000002')->>'present')::int,
  (select total from (
     select public.get_attendance_day_roster(
       nullif(current_setting('app.t0431_day', true), '')::date, 'present',
       null, 'c4310000-0000-4000-8000-000000000002') j
   ) x, jsonb_to_record(j) as t(total int) limit 1),
  'اتساق اللوحة مع القائمة: present = عدد قائمة present'
);

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0431_day', true), '')::date,
     'c4310000-0000-4000-8000-000000000002')->>'incomplete')::int,
  (select total from (
     select public.get_attendance_day_roster(
       nullif(current_setting('app.t0431_day', true), '')::date, 'incomplete',
       null, 'c4310000-0000-4000-8000-000000000002') j
   ) x, jsonb_to_record(j) as t(total int) limit 1),
  'اتساق اللوحة مع القائمة: incomplete = عدد قائمة incomplete'
);

select finish();
rollback;