-- 0029: Break-glass runtime lifecycle (P0.4 mandatory scenario).
-- Proves with live persona contexts that:
--   1. Unauthorized users cannot request break-glass.
--   2. The requester can never approve their own request (four-eyes).
--   3. A different privileged approver can approve.
--   4. Approval grants a time-boxed role.
--   5. Expiry worker revokes the role automatically after active_until.
-- Everything rolls back.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(9);

-- =====================================================================
-- Fixture (superuser)
-- =====================================================================
do $fixture$
begin
  insert into auth.users (id, email, aud, role)
  values
    ('44444444-0000-4000-8000-000000000001', 'bg-requester@test.local', 'authenticated', 'authenticated'),
    ('44444444-0000-4000-8000-000000000002', 'bg-approver@test.local',  'authenticated', 'authenticated'),
    ('44444444-0000-4000-8000-000000000003', 'bg-target@test.local',    'authenticated', 'authenticated');

  -- requester: admin (is_full_access=true → passes current_is_full_access() in request_break_glass)
  insert into public.user_roles (user_id, role_id)
  select '44444444-0000-4000-8000-000000000001', r.id from public.roles r where r.slug = 'admin';

  -- approver: admin (full access → may approve)
  insert into public.user_roles (user_id, role_id)
  select '44444444-0000-4000-8000-000000000002', r.id from public.roles r where r.slug = 'admin';

  -- target holds no roles (so the requested role is genuinely new).
end
$fixture$;

-- =====================================================================
-- 1) Unauthorized user (target, no roles) cannot request break-glass
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000003', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.request_break_glass(
      '44444444-0000-4000-8000-000000000003'::uuid,
      (select id from public.roles where slug='hr-manager'),
      30, 'محاولة غير مخولة')$$,
  '42501', null,
  'unauthorized user cannot request break-glass');

-- =====================================================================
-- 2) Requester creates a pending request
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.request_break_glass(
      '44444444-0000-4000-8000-000000000003'::uuid,
      (select id from public.roles where slug='hr-manager'),
      30, 'وصول طارئ لمعالجة حادثة بيانات')$$,
  'privileged requester creates break-glass request');

reset role;
select is(
  (select status from public.break_glass_requests
   where target_user_id = '44444444-0000-4000-8000-000000000003'
   order by requested_at desc limit 1),
  'pending',
  'break-glass request starts pending');

-- =====================================================================
-- 3) Requester cannot approve their own request (four-eyes)
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.approve_break_glass(
      (select id from public.break_glass_requests
       where target_user_id='44444444-0000-4000-8000-000000000003'
       order by requested_at desc limit 1),
      'موافقة ذاتية ممنوعة')$$,
  '42501', null,
  'requester cannot approve own break-glass request (four-eyes)');

-- =====================================================================
-- 4) A different privileged approver approves
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.approve_break_glass(
      (select id from public.break_glass_requests
       where target_user_id='44444444-0000-4000-8000-000000000003'
       order by requested_at desc limit 1),
      'موافقة رباعية العيون لحادثة بيانات')$$,
  'second privileged user approves break-glass');

reset role;
select is(
  (select status from public.break_glass_requests
   where target_user_id = '44444444-0000-4000-8000-000000000003'
   order by requested_at desc limit 1),
  'approved',
  'break-glass request becomes approved');

select ok(
  exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = '44444444-0000-4000-8000-000000000003'
      and r.slug = 'hr-manager'
      and ur.effective_from <= now()
      and ur.effective_to is not null
      and ur.effective_to > now()
  ),
  'approval grants the target a time-boxed active role');

-- =====================================================================
-- 5) Expiry: after active_until passes, the worker revokes automatically
-- =====================================================================
update public.break_glass_requests
   set active_until = now() - interval '1 minute'
 where target_user_id = '44444444-0000-4000-8000-000000000003'
   and status = 'approved';

select cmp_ok(public.expire_break_glass_access(), '>=', 1,
  'expiry worker expires the elapsed break-glass grant');

select ok(
  not exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = '44444444-0000-4000-8000-000000000003'
      and r.slug = 'hr-manager'
      and (ur.effective_to is null or ur.effective_to > now())
  ),
  'target role is no longer active after break-glass expiry');

select * from finish();
rollback;
