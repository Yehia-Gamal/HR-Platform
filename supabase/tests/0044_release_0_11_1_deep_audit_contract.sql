begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(17);

select has_table('public', 'local_attendance_operations',
  'local biometric operations have an idempotency ledger');
select col_is_pk('public', 'local_attendance_operations', 'operation_id',
  'local attendance operation UUID is the idempotency key');
select ok((select relrowsecurity from pg_class
  where oid = 'public.local_attendance_operations'::regclass),
  'local attendance operation ledger has RLS');
select ok(not has_table_privilege(
  'authenticated', 'public.local_attendance_operations', 'SELECT'),
  'clients cannot read the attendance operation ledger directly');

select has_function(
  'public', 'punch_attendance_local_v2',
  array['uuid','text','text','double precision','double precision','double precision','boolean'],
  'idempotent local-biometric attendance RPC exists');
select function_privs_are(
  'public', 'punch_attendance_local_v2',
  array['uuid','text','text','double precision','double precision','double precision','boolean'],
  'authenticated', array['EXECUTE'],
  'authenticated employees can call the guarded local attendance RPC');

select ok(position('employee_devices' in pg_get_functiondef(
  'public.get_my_passkeys()'::regprocedure)) > 0,
  'device list reads the canonical employee_devices registry');
select ok(position('employee_devices' in pg_get_functiondef(
  'public.get_my_attendance_state(text)'::regprocedure)) > 0,
  'attendance eligibility reads the same canonical device registry');
select has_function(
  'public', 'set_employee_attendance_device_status', array['uuid','text','text'],
  'Main Admin device lifecycle command exists');
select has_index(
  'public', 'employee_devices', 'ux_employee_devices_live_credential',
  'only one live row can represent an employee credential');

select has_function(
  'public', 'mark_my_notification_delivery', array['uuid','text'],
  'authenticated delivery acknowledgement RPC exists');
select function_privs_are(
  'public', 'mark_my_notification_delivery', array['uuid','text'],
  'authenticated', array['EXECUTE'],
  'authenticated owners can acknowledge notification delivery');
select ok(position('token_missing' in pg_get_constraintdef(
  (select oid from pg_constraint
   where conrelid = 'public.notification_delivery_log'::regclass
     and conname = 'notification_delivery_log_status_check'))) > 0
  and position('opened' in pg_get_constraintdef(
  (select oid from pg_constraint
   where conrelid = 'public.notification_delivery_log'::regclass
     and conname = 'notification_delivery_log_status_check'))) > 0,
  'delivery lifecycle includes token_missing and opened');

select is((select count(*)::integer from pg_trigger
  where tgrelid = 'public.notifications'::regclass
    and tgname = 'trg_normalize_live_location_notification'
    and not tgisinternal), 1,
  'urgent location notification normalizer is installed');
select ok(position('urgent_location_v6' in pg_get_functiondef(
  'public.normalize_live_location_notification()'::regprocedure)) > 0,
  'server normalizes urgent requests to channel v6 (0309)');
select ok(position('https://ahla-shabab-management-os.vercel.app/action/' in
  pg_get_functiondef(
    'public.normalize_live_location_notification()'::regprocedure)) > 0,
  'verified HTTPS App Link is the primary notification route');
select ok(position('video_required' in pg_get_functiondef(
  'public.complete_my_live_location_request(uuid)'::regprocedure)) > 0,
  'video-required requests cannot use a location-only waiver');

select * from finish();
rollback;
