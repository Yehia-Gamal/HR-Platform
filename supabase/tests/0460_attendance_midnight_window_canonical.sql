-- ============================================================================
-- 0460: اختبارات نافذة تجميع اليوم المصححة (record_attendance_event /
-- record_attendance_local_biometric) — تكملة على إصلاح 0458.
-- ============================================================================
begin;

create extension if not exists pgtap;

select plan(12);

-- ── وجود الدالتين بالتواقيع المتوقعة ──
select has_function(
  'public', 'record_attendance_event',
  array['uuid','text','double precision','double precision','double precision','text','text','uuid','boolean','boolean'],
  '0460: توقيع record_attendance_event');

select has_function(
  'public', 'record_attendance_local_biometric',
  array['uuid','text','double precision','double precision','double precision','boolean'],
  '0460: توقيع record_attendance_local_biometric');

-- ── الصلاحيات: service_role فقط (نمط 0201/0230) — authenticated وanon محجوبان ──
select function_privs_are(
  'public', 'record_attendance_event',
  array['uuid','text','double precision','double precision','double precision','text','text','uuid','boolean','boolean'],
  'authenticated', array[]::text[],
  '0460: authenticated لا يملك أي صلاحية على record_attendance_event');

select function_privs_are(
  'public', 'record_attendance_local_biometric',
  array['uuid','text','double precision','double precision','double precision','boolean'],
  'authenticated', array[]::text[],
  '0460: authenticated لا يملك أي صلاحية على record_attendance_local_biometric');

select function_privs_are(
  'public', 'record_attendance_event',
  array['uuid','text','double precision','double precision','double precision','text','text','uuid','boolean','boolean'],
  'service_role', array['EXECUTE'],
  '0460: EXECUTE منوحة لـ service_role على record_attendance_event');

select function_privs_are(
  'public', 'record_attendance_local_biometric',
  array['uuid','text','double precision','double precision','double precision','boolean'],
  'service_role', array['EXECUTE'],
  '0460: EXECUTE منوحة لـ service_role على record_attendance_local_biometric');

-- ── خلو الجسمين من الصيغة المكسورة ──
select ok(
  position('v_work_date::timestamptz at time zone v_tz' in pg_get_functiondef(
    'public.record_attendance_event(uuid,text,double precision,double precision,double precision,text,text,uuid,boolean,boolean)'::regprocedure
  )) = 0,
  '0460: جسم record_attendance_event خالٍ من date::timestamptz at time zone');

select ok(
  position('v_work_date::timestamptz at time zone v_tz' in pg_get_functiondef(
    'public.record_attendance_local_biometric(uuid,text,double precision,double precision,double precision,boolean)'::regprocedure
  )) = 0,
  '0460: جسم record_attendance_local_biometric خالٍ من date::timestamptz at time zone');

-- ── وجود صيغة الإصلاح في الجسمين ──
select ok(
  position('v_period_start := v_work_date::timestamp at time zone v_tz' in pg_get_functiondef(
    'public.record_attendance_event(uuid,text,double precision,double precision,double precision,text,text,uuid,boolean,boolean)'::regprocedure
  )) > 0,
  '0460: record_attendance_event يحوّل التاريخ إلى ::timestamp قبل at time zone');

select ok(
  position('v_period_start := v_work_date::timestamp at time zone v_tz' in pg_get_functiondef(
    'public.record_attendance_local_biometric(uuid,text,double precision,double precision,double precision,boolean)'::regprocedure
  )) > 0,
  '0460: record_attendance_local_biometric يحوّل التاريخ إلى ::timestamp قبل at time zone');

-- ── دلالة الحدود: `date::timestamp at time zone` يعطي منتصف ليل القاهرة فعليًا ──
set local timezone = 'UTC';
select is(
  (('2026-08-24'::date)::timestamp at time zone 'Africa/Cairo')::text,
  '2026-08-23 21:00:00+00'::timestamptz::text,
  '0460: منتصف ليل القاهرة صيفًا (DST +03) = 21:00 UTC من اليوم السابق');

select is(
  (('2026-01-15'::date)::timestamp at time zone 'Africa/Cairo')::text,
  '2026-01-14 22:00:00+00'::timestamptz::text,
  '0460: منتصف ليل القاهرة شتاءً (+02) = 22:00 UTC من اليوم السابق');

select * from finish();
rollback;
