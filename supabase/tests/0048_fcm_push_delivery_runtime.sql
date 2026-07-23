begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(14);

insert into auth.users(id, email, aud, role) values
  ('97000000-0000-4000-8000-000000000001', 'push-one@test.local', 'authenticated', 'authenticated'),
  ('97000000-0000-4000-8000-000000000002', 'push-two@test.local', 'authenticated', 'authenticated'),
  ('97000000-0000-4000-8000-000000000003', 'push-no-token@test.local', 'authenticated', 'authenticated');

select has_function(
  'public', 'upsert_my_push_token', array['text', 'text'],
  'FCM token upsert function exists'
);

select ok(
  position('fcm://' in pg_get_functiondef('public.upsert_my_push_token(text,text)'::regprocedure)) > 0,
  'FCM token upsert supplies the required endpoint'
);

select ok(
  position('p256dh_key' in pg_get_functiondef('public.upsert_my_push_token(text,text)'::regprocedure)) > 0
  and position('auth_key' in pg_get_functiondef('public.upsert_my_push_token(text,text)'::regprocedure)) > 0,
  'FCM token upsert supplies legacy Web Push placeholder columns'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config('request.jwt.claim.sub', '97000000-0000-4000-8000-000000000001', true);

select lives_ok(
  $$select public.upsert_my_push_token('fcm-runtime-token-000000000001', 'android')$$,
  'Android FCM token registration succeeds at runtime'
);

select is(
  (select count(*)::integer from public.push_subscriptions
   where user_id = '97000000-0000-4000-8000-000000000001'
     and fcm_token = 'fcm-runtime-token-000000000001'),
  1,
  'FCM subscription row is stored'
);

select is(
  (select endpoint from public.push_subscriptions
   where user_id = '97000000-0000-4000-8000-000000000001'
     and fcm_token = 'fcm-runtime-token-000000000001'),
  'fcm://fcm-runtime-token-000000000001',
  'FCM endpoint placeholder is deterministic'
);

select is(
  (select p256dh_key || auth_key from public.push_subscriptions
   where user_id = '97000000-0000-4000-8000-000000000001'
     and fcm_token = 'fcm-runtime-token-000000000001'),
  '--',
  'Legacy Web Push key placeholders are populated'
);

select ok(
  (select is_active from public.push_subscriptions
   where user_id = '97000000-0000-4000-8000-000000000001'
     and fcm_token = 'fcm-runtime-token-000000000001'),
  'New FCM subscription is active'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config('request.jwt.claim.sub', '97000000-0000-4000-8000-000000000002', true);

select lives_ok(
  $$select public.upsert_my_push_token('fcm-runtime-token-000000000001', 'android')$$,
  'The same physical token can move safely to the current user'
);

select is(
  (select count(*)::integer from public.push_subscriptions
   where fcm_token = 'fcm-runtime-token-000000000001' and is_active),
  1,
  'Only one user remains active for a physical FCM token'
);

select is(
  (select user_id from public.push_subscriptions
   where fcm_token = 'fcm-runtime-token-000000000001' and is_active),
  '97000000-0000-4000-8000-000000000002'::uuid,
  'The active token belongs to the latest authenticated user'
);

select ok(
  position(
    'new.entity_type = ''live_location_request'''
    in pg_get_functiondef('public.queue_notification_jobs()'::regprocedure)
  ) > 0,
  'Live-location notifications always enqueue an observable push job'
);

insert into public.notifications(
  recipient_user_id, title, body, category, priority, entity_type, entity_id, metadata
) values (
  '97000000-0000-4000-8000-000000000003',
  'طلب تحقق من الموقع',
  'اختبار إرسال عاجل',
  'system',
  'urgent',
  'live_location_request',
  '97000000-0000-4000-8000-000000000099',
  jsonb_build_object('requestId', '97000000-0000-4000-8000-000000000099')
);

select is(
  (select count(*)::integer
   from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.recipient_user_id = '97000000-0000-4000-8000-000000000003'
     and n.entity_type = 'live_location_request'
     and j.channel = 'push'),
  1,
  'Live-location push job is queued even before token registration'
);

select is(
  (select count(*)::integer
   from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.recipient_user_id = '97000000-0000-4000-8000-000000000003'
     and n.entity_type = 'live_location_request'
     and j.channel = 'in_app'),
  1,
  'In-app delivery remains queued alongside push'
);

select * from finish();
rollback;
