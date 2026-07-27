begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(28);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم أ: attendance_settings singleton table
-- ═══════════════════════════════════════════════════════════════════════════════

select has_table('public', 'attendance_settings', 'attendance_settings table exists');

select col_is_pk(
  'public', 'attendance_settings', 'singleton_key',
  'singleton_key is the primary key'
);

select has_column('public', 'attendance_settings', 'geofence_radius_default_meters',
  'geofence_radius_default_meters column exists');
select has_column('public', 'attendance_settings', 'location_age_max_seconds',
  'location_age_max_seconds column exists');
select has_column('public', 'attendance_settings', 'accuracy_max_default_meters',
  'accuracy_max_default_meters column exists');
select has_column('public', 'attendance_settings', 'missing_checkout_grace_minutes',
  'missing_checkout_grace_minutes column exists');
select has_column('public', 'attendance_settings', 'impossible_travel_speed_mps',
  'impossible_travel_speed_mps column exists');
select has_column('public', 'attendance_settings', 'timezone',
  'timezone column exists');

-- Singleton row is seeded
select ok(
  (select count(*) = 1 from public.attendance_settings),
  'exactly one settings row exists (singleton)'
);

-- Default values are correct
select ok(
  (select geofence_radius_default_meters = 300
      and location_age_max_seconds = 15
      and accuracy_max_default_meters = 100
      and missing_checkout_grace_minutes = 60
      and impossible_travel_speed_mps = 42
      and timezone = 'Africa/Cairo'
   from public.attendance_settings limit 1),
  'default settings values match V23 spec'
);

-- RLS is enabled
select ok(
  (select relrowsecurity from pg_class where oid = 'public.attendance_settings'::regclass),
  'attendance_settings has RLS enabled'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ب: attendance_daily.status constraint expanded
-- ═══════════════════════════════════════════════════════════════════════════════

-- Verify the constraint allows the new 'missing_checkout' value
select ok(
  (select pg_get_constraintdef(oid) ilike '%missing_checkout%'
   from pg_constraint
   where conrelid = 'public.attendance_daily'::regclass
     and conname = 'attendance_daily_status_check'),
  'attendance_daily status constraint includes missing_checkout'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ج: record_attendance_event — night shift + period bounds
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'record_attendance_event',
  array['uuid','text','double precision','double precision','double precision',
        'text','text','uuid','boolean','boolean'],
  'record_attendance_event function exists with correct signature'
);

-- Service role restriction
select function_privs_are(
  'public', 'record_attendance_event',
  array['uuid','text','double precision','double precision','double precision',
        'text','text','uuid','boolean','boolean'],
  'authenticated', array[]::text[],
  'authenticated cannot call record_attendance_event'
);
select function_privs_are(
  'public', 'record_attendance_event',
  array['uuid','text','double precision','double precision','double precision',
        'text','text','uuid','boolean','boolean'],
  'service_role', array['EXECUTE'],
  'service_role can call record_attendance_event'
);

-- Night shift logic is present in function body
select ok(
  position('crosses_midnight' in pg_get_functiondef(
    'public.record_attendance_event(uuid,text,double precision,double precision,double precision,text,text,uuid,boolean,boolean)'::regprocedure
  )) > 0,
  'record_attendance_event contains night shift (crosses_midnight) logic'
);

-- Period-based queries replace date-based queries
select ok(
  position('v_period_start' in pg_get_functiondef(
    'public.record_attendance_event(uuid,text,double precision,double precision,double precision,text,text,uuid,boolean,boolean)'::regprocedure
  )) > 0,
  'record_attendance_event uses period boundaries (v_period_start)'
);

-- Uses attendance_settings for timezone
select ok(
  position('attendance_settings' in pg_get_functiondef(
    'public.record_attendance_event(uuid,text,double precision,double precision,double precision,text,text,uuid,boolean,boolean)'::regprocedure
  )) > 0,
  'record_attendance_event reads from attendance_settings'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم د: record_attendance_local_biometric — same night shift fix
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'record_attendance_local_biometric',
  array['uuid','text','double precision','double precision','double precision','boolean'],
  'record_attendance_local_biometric function exists with correct signature'
);

select function_privs_are(
  'public', 'record_attendance_local_biometric',
  array['uuid','text','double precision','double precision','double precision','boolean'],
  'authenticated', array[]::text[],
  'authenticated cannot call record_attendance_local_biometric'
);
select function_privs_are(
  'public', 'record_attendance_local_biometric',
  array['uuid','text','double precision','double precision','double precision','boolean'],
  'service_role', array['EXECUTE'],
  'service_role can call record_attendance_local_biometric'
);

select ok(
  position('crosses_midnight' in pg_get_functiondef(
    'public.record_attendance_local_biometric(uuid,text,double precision,double precision,double precision,boolean)'::regprocedure
  )) > 0,
  'record_attendance_local_biometric contains night shift logic'
);

select ok(
  position('v_period_start' in pg_get_functiondef(
    'public.record_attendance_local_biometric(uuid,text,double precision,double precision,double precision,boolean)'::regprocedure
  )) > 0,
  'record_attendance_local_biometric uses period boundaries'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم هـ: finalize_missing_checkouts
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'finalize_missing_checkouts',
  array[]::text[],
  'finalize_missing_checkouts function exists'
);

select function_privs_are(
  'public', 'finalize_missing_checkouts',
  array[]::text[],
  'authenticated', array[]::text[],
  'authenticated cannot call finalize_missing_checkouts'
);
select function_privs_are(
  'public', 'finalize_missing_checkouts',
  array[]::text[],
  'service_role', array['EXECUTE'],
  'service_role can call finalize_missing_checkouts'
);

-- Function body inspections
select ok(
  position('missing_checkout' in pg_get_functiondef(
    'public.finalize_missing_checkouts()'::regprocedure
  )) > 0,
  'finalize_missing_checkouts marks status as missing_checkout'
);

select ok(
  position('attendance_exceptions' in pg_get_functiondef(
    'public.finalize_missing_checkouts()'::regprocedure
  )) > 0,
  'finalize_missing_checkouts creates attendance_exception records'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم و: Geofence audit trigger
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'tg_geofence_audit',
  'geofence audit trigger function exists'
);

select has_trigger(
  'public', 'geofences', 'trg_geofence_audit',
  'geofence audit trigger is attached to geofences table'
);

select * from finish();
rollback;
