-- 0435: تطبيع أنواع كيانات الإشعارات الفعلية في resolve_mobile_action_target
-- (live_location_requests/attendance_daily/attendance_event/attendance_corrections/
--  overtime_records/work_rosters/requests/dispute_case — الأنواع المخزنة فعلاً)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(15);

-- كل فرع التطبيع الجديد موجود في تعريف الدالة
select ok(
  position('''live_location_requests'' then' in lower(pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  ))) > 0,
  'action resolver normalizes the plural live_location_requests kind');
select ok(
  position('''attendance_daily'' then' in lower(pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  ))) > 0,
  'action resolver normalizes attendance_daily to attendance');
select ok(
  position('''attendance_event'' then' in lower(pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  ))) > 0,
  'action resolver normalizes attendance_event to attendance');
-- 0544/0549 غيّرا وجهة attendance_corrections من attendance إلى attendance_correction
-- (صفحة مخصصة لمراجعة التصحيحات) — الفرع موجود ويؤدي إلى الوجهة الجديدة.
select ok(
  position('''attendance_corrections'' then ''attendance_correction''' in lower(pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  ))) > 0,
  'action resolver normalizes attendance_corrections to attendance_correction');
select ok(
  position('''overtime_records'' then' in lower(pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  ))) > 0,
  'action resolver normalizes overtime_records to attendance');
select ok(
  position('''work_rosters'' then' in lower(pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  ))) > 0,
  'action resolver normalizes work_rosters to attendance');
select ok(
  position('''requests'' then' in lower(pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  ))) > 0,
  'action resolver normalizes plural requests to request');
select ok(
  position('''dispute_case'' then' in lower(pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  ))) > 0,
  'action resolver normalizes dispute_case to dispute');

-- live_location_requests (الجمع) يُقبل ثم يُقيَّد بوجود الطلب — 0549 استبدلت رمي P0002
-- بكائن jsonb آمن mobileRoute='unsupported' (منع تجميد الموبايل على شاشة الفتح)
select is(
  public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000001','live_location_requests'),
  '{"kind": "live_location_request", "recordId": "00000000-0000-0000-0000-000000000001", "mobileRoute": "unsupported"}'::jsonb,
  'plural live_location_requests kind is accepted then guarded by existence');

-- attendance_daily (الأنواع الحضورية) تُقبل وتعود مسار attendance_detail حتى لمعرّف غير موجود
select results_eq(
  $q$ select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000002','attendance_daily')::text $q$,
  array['{"kind": "attendance", "recordId": "00000000-0000-0000-0000-000000000002", "mobileRoute": "attendance_detail"}'],
  'attendance_daily resolves to the attendance detail route');
-- attendance_corrections (0544/0549) تُطبَّع الآن إلى attendance_correction وتُقيَّد
-- بصلاحية مراجعة التصحيحات — معرّف غير موجود/غير مخوّل يرفض بـ 42501
select throws_ok($$
  select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000003','attendance_corrections')
$$, '42501', null, 'attendance_corrections is guarded by the correction review permission');
select results_eq(
  $q$ select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000004','work_rosters')::text $q$,
  array['{"kind": "attendance", "recordId": "00000000-0000-0000-0000-000000000004", "mobileRoute": "attendance_detail"}'],
  'work_rosters resolves to the attendance detail route');

-- requests (الجمع) يصل إلى فرع request ثم يُقيَّد بوجود الطلب — استعلام غياب السجل
select throws_ok($$
  select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000005','requests')
$$, '42501', null, 'plural requests kind is accepted then guarded by access');

-- الأنواع بلا صفحة موبايل تبقى غير مدعومة — 0549 استبدلت رمي 22023 بكائن jsonb
-- آمن mobileRoute='unsupported' (تُعالج معلوماتياً من التطبيق بعد قراءة mobileRoute)
select is(
  public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000006','kpi_appeals'),
  '{"kind": "kpi_appeals", "recordId": "00000000-0000-0000-0000-000000000006", "mobileRoute": "unsupported"}'::jsonb,
  'kpi_appeals stays unsupported (informational only)');
select is(
  public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000007','work_assignments'),
  '{"kind": "work_assignments", "recordId": "00000000-0000-0000-0000-000000000007", "mobileRoute": "unsupported"}'::jsonb,
  'work_assignments stays unsupported (informational only)');

select * from finish();
rollback;
