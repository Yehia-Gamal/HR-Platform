begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

select has_function(
  'public', 'activate_verified_passkey_device',
  array['uuid','uuid','text','text','bigint','text[]','text','text','text','boolean'],
  'server-verified passkey/device activation RPC exists');

select function_privs_are(
  'public', 'activate_verified_passkey_device',
  array['uuid','uuid','text','text','bigint','text[]','text','text','text','boolean'],
  'service_role', array['EXECUTE'],
  'only service_role can activate a verified passkey device');

select function_privs_are(
  'public', 'activate_verified_passkey_device',
  array['uuid','uuid','text','text','bigint','text[]','text','text','text','boolean'],
  'authenticated', array[]::text[],
  'clients cannot self-activate trusted devices');

select has_column('public', 'employee_devices', 'credential_id',
  'employee_devices keeps the passkey credential identifier');
select has_column('public', 'employee_devices', 'device_identifier_hash',
  'employee_devices keeps the privacy-safe device identifier hash');

select ok(
  position('autoCancelledByNewRequest' in pg_get_functiondef(
    'public.request_live_location(uuid,text,text)'::regprocedure
  )) = 0,
  'resending never auto-cancels an earlier request');

select ok(
  position('30 seconds' in pg_get_functiondef(
    'public.request_live_location(uuid,text,text)'::regprocedure
  )) > 0,
  'request creation has a server-side 30-second cooldown');

select ok(
  position('fullScreen' in pg_get_functiondef(
    'public.request_live_location(uuid,text,text)'::regprocedure
  )) > 0,
  'urgent notification metadata requests full-screen presentation');

select ok(
  position('ahlashabab://action/live_location_request/' in pg_get_functiondef(
    'public.request_live_location(uuid,text,text)'::regprocedure
  )) > 0,
  'urgent notification deep-links to the exact request');

select has_function(
  'public', 'resolve_mobile_action_target', array['text','text'],
  'authorized exact mobile action resolver exists');

select function_privs_are(
  'public', 'resolve_mobile_action_target', array['text','text'],
  'authenticated', array['EXECUTE'],
  'authenticated clients can resolve authorized action targets');

select ok(
  position('live_location_request' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver explicitly allowlists live-location requests');

select has_function(
  'public', 'register_live_location_map_snapshot', array['uuid','text'],
  'private map snapshot registration RPC exists');

select function_privs_are(
  'public', 'register_live_location_map_snapshot', array['uuid','text'],
  'authenticated', array['EXECUTE'],
  'authenticated employee can register an owned map snapshot');

select has_function(
  'public', 'can_view_live_location_map_snapshot', array['uuid'],
  'map snapshot signed-URL authorization gate exists');

select is(
  (select public from storage.buckets where id='live-location-map-snapshots'),
  false,
  'map snapshot bucket is private');

select * from finish();
rollback;
