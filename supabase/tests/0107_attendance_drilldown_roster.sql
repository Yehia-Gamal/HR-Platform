-- 0107: 0294-0296 — drill-down لوحات الحضور: القائمة خلف كل رقم.
-- يثبت أن:
--   1) overload القديم (date,text) أُزيل (0296) والوظيفة الموسّعة وحدها.
--   2) المنح: authenticated ينفّذ، anon لا.
--   3) total لكل فئة يطابق عدّاد لوحة الحضور (الرقم=القائمة) لنفس اليوم.
--   4) البنية {items,total,limit,offset} + ترقيم سليم + مفاتيح الصفوف.
--   5) التحقق من المدخلات (فئة/ترتيب/اتجاه/limit/offset) برمز 22023.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(24);

-- =====================================================================
-- 1. البنية والمنح
-- =====================================================================
select ok(
  to_regprocedure('public.get_attendance_day_roster(date,text)') is null,
  'overload القديم (date,text) أُزيل (0296)'
);

select ok(
  to_regprocedure('public.get_attendance_day_roster(date,text,text,uuid,uuid,uuid,text,text,integer,integer)') is not null,
  'الوظيفة الموسّعة موجودة بكل معاملاتها'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_attendance_day_roster(date,text,text,uuid,uuid,uuid,text,text,integer,integer)',
    'EXECUTE'
  ),
  'authenticated ينفّذ الوظيفة الموسّعة'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.get_attendance_day_roster(date,text,text,uuid,uuid,uuid,text,text,integer,integer)',
    'EXECUTE'
  ),
  'anon لا ينفّذ الوظيفة الموسّعة'
);

-- =====================================================================
-- 2. اتساق العدد=القائمة لكل الفئات (نفس اليوم)
-- =====================================================================
select is(
  (public.get_attendance_dashboard(current_date)->>'scheduled')::int,
  (public.get_attendance_day_roster(current_date, 'scheduled')->>'total')::int,
  'المجدولون = عدد قائمة المجدولون'
);

select is(
  (public.get_attendance_dashboard(current_date)->>'present')::int,
  (public.get_attendance_day_roster(current_date, 'present')->>'total')::int,
  'الحاضرون = عدد قائمة الحاضرون'
);

select is(
  (public.get_attendance_dashboard(current_date)->>'late')::int,
  (public.get_attendance_day_roster(current_date, 'late')->>'total')::int,
  'المتأخرون = عدد قائمة المتأخرون'
);

select is(
  (public.get_attendance_dashboard(current_date)->>'absent')::int,
  (public.get_attendance_day_roster(current_date, 'absent')->>'total')::int,
  'الغياب = عدد قائمة الغياب'
);

select is(
  (public.get_attendance_dashboard(current_date)->>'unexcusedAbsent')::int,
  (public.get_attendance_day_roster(current_date, 'unexcused_absent')->>'total')::int,
  'الغياب بدون إذن = عدد قائمته'
);

select is(
  (public.get_attendance_dashboard(current_date)->>'incomplete')::int,
  (public.get_attendance_day_roster(current_date, 'incomplete')->>'total')::int,
  'البصمات غير المكتملة = عدد قائمتها'
);

select is(
  (public.get_attendance_dashboard(current_date)->>'pendingReview')::int,
  (public.get_attendance_day_roster(current_date, 'pending_review')->>'total')::int,
  'تحتاج مراجعة = عدد قائمتها'
);

select is(
  (public.get_attendance_dashboard(current_date)->>'locationRequestsToday')::int,
  (public.get_attendance_day_roster(current_date, 'location_requests')->>'total')::int,
  'طلبات الموقع = عدد قائمتها'
);

select is(
  (public.get_attendance_dashboard(current_date)->>'locationRespondedToday')::int,
  (public.get_attendance_day_roster(current_date, 'location_responded')->>'total')::int,
  'استجابات الموقع = عدد قائمتها'
);

-- =====================================================================
-- 3. بنية النتيجة والترقيم
-- =====================================================================
select is(
  (select jsonb_build_array((j ? 'items'), (j ? 'total'), (j ? 'limit'), (j ? 'offset'))
     from (select public.get_attendance_day_roster(current_date, 'scheduled') as j) x),
  '[true, true, true, true]'::jsonb,
  'النتيجة تحمل مفاتيح items/total/limit/offset'
);

select is(
  jsonb_typeof((public.get_attendance_day_roster(current_date, 'scheduled'))->'items'),
  'array',
  'items مصفوفة'
);

select ok(
  jsonb_array_length((public.get_attendance_day_roster(current_date, 'scheduled', null, null, null, null, 'name', 'asc', 25, 0)->'items'))
    <= 25,
  'عدد عناصر الصفحة لا يتجاوز limit'
);

select is(
  jsonb_array_length((public.get_attendance_day_roster(current_date, 'scheduled', null, null, null, null, 'name', 'asc', 3, 0)->'items')),
  least(3, (public.get_attendance_day_roster(current_date, 'scheduled')->>'total')::int),
  'الترقيم يقصّ العناصر إلى limit ما لم يتجاوز الإجمالي'
);

select ok(
  not exists (
    select 1
      from jsonb_array_elements((public.get_attendance_day_roster(current_date, 'scheduled')->'items')) it
     where not (it ? 'employeeId') or not (it ? 'employeeName') or not (it ? 'status')
  ),
  'كل صف يحمل employeeId/employeeName/status'
);

select ok(
  (public.get_attendance_day_roster(current_date, 'scheduled')->>'total')::int >= 0,
  'total غير سالب'
);

select is(
  (public.get_attendance_day_roster(current_date, 'scheduled', 'zzzz-nomatch-987')->>'total')::int,
  0,
  'بحث لا يطابق أي موظف يرجع total=0'
);

-- =====================================================================
-- 4. التحقق من المدخلات (22023)
-- =====================================================================
select throws_ok(
  $$select public.get_attendance_day_roster(current_date, 'bogus')$$,
  '22023', null,
  'فئة غير صالحة تُرفض'
);

select throws_ok(
  $$select public.get_attendance_day_roster(current_date, 'scheduled', null, null, null, null, 'bogus_sort', 'asc', 25, 0)$$,
  '22023', null,
  'ترتيب غير صالح يُرفض'
);

select throws_ok(
  $$select public.get_attendance_day_roster(current_date, 'scheduled', null, null, null, null, 'name', 'sideways', 25, 0)$$,
  '22023', null,
  'اتجاه غير صالح يُرفض'
);

select throws_ok(
  $$select public.get_attendance_day_roster(current_date, 'scheduled', null, null, null, null, 'name', 'asc', 0, 0)$$,
  '22023', null,
  'limit صفر يُرفض'
);

select throws_ok(
  $$select public.get_attendance_day_roster(current_date, 'scheduled', null, null, null, null, 'name', 'asc', 25, -1)$$,
  '22023', null,
  'offset سالب يُرفض'
);

select finish();
rollback;
