-- pgTAP: V23 §4 — attendance geofence hardening contract tests
-- Migration 0162 — attendance_settings, missing_checkout status,
-- record functions with night-shift + period boundaries,
-- finalize_missing_checkouts, geofence audit trigger.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(28);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم أ: attendance_settings singleton (11 assertions)
-- ═══════════════════════════════════════════════════════════════════════════════

select has_table('public', 'attendance_settings', 'attendance_settings table exists');
select col_is_pk('public', 'attendance_settings', 'singleton_key', 'singleton_key is PK');
select has_column('public', 'attendance_settings', 'geofence_radius_default_meters', 'has geofence_radius_default_meters');
select has_column('public', 'attendance_settings', 'location_age_max_seconds', 'has location_age_max_seconds');
select has_column('public', 'attendance_settings', 'accuracy_max_default_meters', 'has accuracy_max_default_meters');
select has_column('public', 'attendance_settings', 'missing_checkout_grace_minutes', 'has missing_checkout_grace_minutes');
select has_column('public', 'attendance_settings', 'impossible_travel_speed_mps', 'has impossible_travel_speed_mps');
select has_column('public', 'attendance_settings', 'timezone', 'has timezone');

-- Singleton row seeded with defaults
select is(
  (select count(*)::integer from public.attendance_settings),
  1,
  'exactly one settings row exists'
);
select is(
  (select geofence_radius_default_meters from public.attendance_settings limit 1),
  300,
  'default geofence radius is 300m'
);

-- RLS is enabled
select ok(
  (select relrowsecurity from pg_class where oid = 'public.attendance_settings'::regclass),
  'attendance_settings has RLS enabled'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ب: attendance_daily.status constraint includes 'missing_checkout' (1)
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.attendance_daily'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%missing_checkout%'
  ),
  'attendance_daily status constraint includes missing_checkout'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم ج: record_attendance_event — V23 enhancements (5)
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'record_attendance_event',
  array['uuid','text','double precision','double precision','double precision',
        'text','text','uuid','boolean','boolean'],
  'record_attendance_event function exists'
);

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

-- Function body contains night-shift detection logic
select ok(
  position('crosses_midnight' in pg_get_functiondef(
    'public.record_attendance_event(uuid,text,double precision,double precision,double precision,text,text,uuid,boolean,boolean)'::regprocedure
  )) > 0,
  'record_attendance_event contains crosses_midnight night-shift logic'
);

-- Function body contains period-based lookups
select ok(
  position('v_period_start' in pg_get_functiondef(
    'public.record_attendance_event(uuid,text,double precision,double precision,double precision,text,text,uuid,boolean,boolean)'::regprocedure
  )) > 0,
  'record_attendance_event uses period-based boundaries'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم د: record_attendance_local_biometric — V23 enhancements (4)
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'record_attendance_local_biometric',
  array['uuid','text','double precision','double precision','double precision','boolean'],
  'record_attendance_local_biometric function exists'
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
  position('v_period_start' in pg_get_functiondef(
    'public.record_attendance_local_biometric(uuid,text,double precision,double precision,double precision,boolean)'::regprocedure
  )) > 0,
  'record_attendance_local_biometric uses period-based boundaries'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم هـ: finalize_missing_checkouts (4)
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

-- Function body references missing_checkout and attendance_exceptions
select ok(
  position('missing_checkout' in pg_get_functiondef(
    'public.finalize_missing_checkouts()'::regprocedure
  )) > 0
  and position('attendance_exceptions' in pg_get_functiondef(
    'public.finalize_missing_checkouts()'::regprocedure
  )) > 0,
  'finalize_missing_checkouts handles missing_checkout and creates exceptions'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- القسم و: geofence audit trigger (3)
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'tg_geofence_audit',
  array[]::text[],
  'tg_geofence_audit trigger function exists'
);

select has_trigger(
  'public', 'geofences', 'trg_geofence_audit',
  'geofence audit trigger is installed'
);

select ok(
  position('geofence.config_changed' in pg_get_functiondef(
    'public.tg_geofence_audit()'::regprocedure
  )) > 0,
  'tg_geofence_audit logs geofence.config_changed audit event'
);

select * from finish();
rollback;
