begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(15);

-- get_mobile_feed_item يدعم recognition الآن (0353)
select has_function(
  'public', 'get_mobile_feed_item', array['text','uuid'],
  'mobile feed detail exists');
select function_privs_are(
  'public', 'get_mobile_feed_item', array['text','uuid'],
  'authenticated', array['EXECUTE'],
  'authenticated clients fetch feed detail');
select function_privs_are(
  'public', 'get_mobile_feed_item', array['text','uuid'],
  'anon', array[]::text[],
  'anonymous clients cannot fetch feed detail');
select ok(
  position('''recognition'' then' in pg_get_functiondef(
    'public.get_mobile_feed_item(text,uuid)'::regprocedure
  )) > 0,
  'feed detail accepts recognition items');
select throws_ok($$
  select public.get_mobile_feed_item('bogus','00000000-0000-0000-0000-000000000001')
$$, '22023', null, 'feed detail rejects unsupported kinds');
select throws_ok($$
  select public.get_mobile_feed_item('recognition','00000000-0000-0000-0000-000000000001')
$$, 'P0002', null, 'recognition kind is accepted then guarded by visibility');

-- resolve_mobile_action_target يطبّع live_location (0319) → live_location_request (0353)
select has_function(
  'public', 'resolve_mobile_action_target', array['text','text'],
  'authorized mobile action resolver exists');
select function_privs_are(
  'public', 'resolve_mobile_action_target', array['text','text'],
  'authenticated', array['EXECUTE'],
  'authenticated clients resolve action targets');
select ok(
  position('''live_location'' then' in pg_get_functiondef(
    'public.resolve_mobile_action_target(text,text)'::regprocedure
  )) > 0,
  'action resolver normalizes the proactive live_location kind');
select throws_ok($$
  select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000001','bogus')
$$, '22023', null, 'action resolver rejects unsupported kinds');
select throws_ok($$
  select public.resolve_mobile_action_target('00000000-0000-0000-0000-000000000001','live_location')
$$, 'P0002', null, 'live_location kind is accepted then guarded by existence');

-- get_live_location_request_by_id يفتح طلب الموقع بالمعرّف للطرفين (0353)
select has_function(
  'public', 'get_live_location_request_by_id', array['uuid'],
  'single live-location request resolver exists');
select function_privs_are(
  'public', 'get_live_location_request_by_id', array['uuid'],
  'authenticated', array['EXECUTE'],
  'authenticated clients open a location request by id');
select function_privs_are(
  'public', 'get_live_location_request_by_id', array['uuid'],
  'anon', array[]::text[],
  'anonymous clients cannot open location requests');
select throws_ok($$
  select public.get_live_location_request_by_id('00000000-0000-0000-0000-000000000001')
$$, 'P0002', null, 'missing location request yields a guarded error');

select * from finish();
rollback;
