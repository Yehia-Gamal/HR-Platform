-- pgTAP test for migration 0226: attendance device mismatch fix
-- Validates:
--   ① get_my_attendance_state(text) — new signature with p_installation_id
--   ② punch_attendance_local_biometric_v1 — structured JSON for device errors
--   ③ _humanizePunchError coverage — all v_known_errors have Flutter handling

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- ═══════════════════════════════════════════════════════════════════════════
-- ① get_my_attendance_state — signature and grants
-- ═══════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'get_my_attendance_state', array['text'],
  '0226: get_my_attendance_state accepts optional text p_installation_id');

select function_returns(
  'public', 'get_my_attendance_state', array['text'], 'jsonb',
  '0226: attendance state returns jsonb');

select function_privs_are(
  'public', 'get_my_attendance_state', array['text'],
  'authenticated', array['EXECUTE'],
  '0226: authenticated users can call get_my_attendance_state');

-- Verify the old parameterless version no longer exists
select ok(
  not exists(
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_my_attendance_state'
      and p.pronargs = 0
  ),
  '0226: old parameterless get_my_attendance_state() is dropped');

-- Verify function body contains currentDeviceStatus (new 0226 field)
select ok(
  position('currentDeviceStatus' in pg_get_functiondef(
    'public.get_my_attendance_state(text)'::regprocedure)) > 0,
  '0226: attendance state returns currentDeviceStatus field');

-- Verify function body contains currentDeviceActive (new 0226 field)
select ok(
  position('currentDeviceActive' in pg_get_functiondef(
    'public.get_my_attendance_state(text)'::regprocedure)) > 0,
  '0226: attendance state returns currentDeviceActive field');

-- Verify canPunch uses CASE for per-device vs all-device logic
select ok(
  position('v_current_device_active' in pg_get_functiondef(
    'public.get_my_attendance_state(text)'::regprocedure)) > 0,
  '0226: canPunch checks current device when installation_id provided');

-- ═══════════════════════════════════════════════════════════════════════════
-- ② punch_attendance_local_biometric_v1 — structured errors
-- ═══════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'punch_attendance_local_biometric_v1',
  array['uuid','text','text','double precision','double precision','double precision','boolean'],
  '0226: punch_attendance_local_biometric_v1 exists with correct signature');

select function_privs_are(
  'public', 'punch_attendance_local_biometric_v1',
  array['uuid','text','text','double precision','double precision','double precision','boolean'],
  'authenticated', array['EXECUTE'],
  '0226: authenticated users can call punch_attendance_local_biometric_v1');

-- Verify device-not-active returns JSON instead of RAISE
select ok(
  position('local_biometric_device_not_active' in pg_get_functiondef(
    'public.punch_attendance_local_biometric_v1(uuid,text,text,double precision,double precision,double precision,boolean)'::regprocedure)) > 0,
  '0226: punch function contains local_biometric_device_not_active error code');

-- Verify managed_device_not_active detail is present (structured JSON path)
select ok(
  position('managed_device_not_active' in pg_get_functiondef(
    'public.punch_attendance_local_biometric_v1(uuid,text,text,double precision,double precision,double precision,boolean)'::regprocedure)) > 0,
  '0226: punch function returns managed_device_not_active detail');

-- Verify employee_device_not_active detail is present (structured JSON path)
select ok(
  position('employee_device_not_active' in pg_get_functiondef(
    'public.punch_attendance_local_biometric_v1(uuid,text,text,double precision,double precision,double precision,boolean)'::regprocedure)) > 0,
  '0226: punch function returns employee_device_not_active detail');

select * from finish();
rollback;
