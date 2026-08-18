-- 0435: تطبيع أنواع كيانات الإشعارات الفعلية في resolve_mobile_action_target
-- (live_location_requests/attendance_daily/attendance_event/attendance_corrections/
--  overtime_records/work_rosters/requests/dispute_case — الأنواع المخزنة فعلاً)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(15);

-- كل فرع التطبيع الجديد موجود في تعريف الدالة
select ok(
  position('''live_location_requests'' then' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver normalizes the plural live_location_requests kind');
select ok(
  position('''attendance_daily'' then' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver normalizes attendance_daily to attendance');
select ok(
  position('''attendance_event'' then' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver normalizes attendance_event to attendance');
select ok(
  position('''attendance_corrections'' then' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver normalizes attendance_corrections to attendance');
select ok(
  position('''overtime_records'' then' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver normalizes overtime_records to attendance');
select ok(
  position('''work_rosters'' then' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver normalizes work_rosters to attendance');
select ok(
  position('''requests'' then' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver normalizes plural requests to request');
select ok(
  position('''dispute_case'' then' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver normalizes dispute_case to dispute');

-- live_location_requests (الجمع) يُقبل ثم يُقيَّد بوجود الطلب — نفس سلوك 0353
select throws_ok($$
  select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000001','live_location_requests')
$$, 'P0002', null, 'plural live_location_requests kind is accepted then guarded by existence');

-- attendance_daily (الأنواع الحضورية) تُقبل وتعود مسار attendance_detail حتى لمعرّف غير موجود
select results_eq(
  $q$ select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000002','attendance_daily')::text $q$,
  array['{"kind": "attendance", "recordId": "00000000-0000-0000-0000-000000000002", "mobileRoute": "attendance_detail"}'],
  'attendance_daily resolves to the attendance detail route');
select results_eq(
  $q$ select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000003','attendance_corrections')::text $q$,
  array['{"kind": "attendance", "recordId": "00000000-0000-0000-0000-000000000003", "mobileRoute": "attendance_detail"}'],
  'attendance_corrections resolves to the attendance detail route');
select results_eq(
  $q$ select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000004','work_rosters')::text $q$,
  array['{"kind": "attendance", "recordId": "00000000-0000-0000-0000-000000000004", "mobileRoute": "attendance_detail"}'],
  'work_rosters resolves to the attendance detail route');

-- requests (الجمع) يصل إلى فرع request ثم يُقيَّد بوجود الطلب — استعلام غياب السجل
select throws_ok($$
  select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000005','requests')
$$, '42501', null, 'plural requests kind is accepted then guarded by access');

-- الأنواع بلا صفحة موبايل تبقى مرفوضة (معلوماتية تُعالج من التطبيق فقط)
select throws_ok($$
  select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000006','kpi_appeals')
$$, '22023', null, 'kpi_appeals stays unsupported (informational only)');
select throws_ok($$
  select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000007','work_assignments')
$$, '22023', null, 'work_assignments stays unsupported (informational only)');

select * from finish();
rollback;
