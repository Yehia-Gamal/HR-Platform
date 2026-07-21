-- 0040: Live-location executive flow runtime (Migration 0067).
-- Runs real persona contexts (JWT claims + role switch) against the live
-- RLS policies and SECURITY DEFINER RPCs for the executive location+video
-- journey. Everything rolls back.
--
-- Personas:
--   executive-director (org scope), operations-manager (dept scope),
--   employee target (dept A), peer employee (dept B), unauthorized employee.
--
-- Covers the 30 mandated cases: request/authz, mode validation, respond,
-- point/video lifecycle (incl combined location_video), response read,
-- RLS isolation, and audit/access-log writes.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(37);

-- =====================================================================
-- Fixture (superuser; RLS not yet in play)
-- =====================================================================
do $fixture$
declare
  v_le     uuid := 'cccc0000-0000-4000-8000-000000000000';
  v_dept_a uuid := 'cccc0000-0000-4000-8000-00000000000a';
  v_dept_b uuid := 'cccc0000-0000-4000-8000-00000000000b';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'LLX-LE', 'كيان اختبار الموقع');
  insert into public.departments (id, legal_entity_id, code, name) values
    (v_dept_a, v_le, 'LLX-A', 'إدارة أ'),
    (v_dept_b, v_le, 'LLX-B', 'إدارة ب');

  insert into auth.users (id, email, aud, role) values
    ('dddd0000-0000-4000-8000-000000000001', 'llx-emp@test.local',   'authenticated','authenticated'),
    ('dddd0000-0000-4000-8000-000000000002', 'llx-peer@test.local',  'authenticated','authenticated'),
    ('dddd0000-0000-4000-8000-000000000003', 'llx-opsmgr@test.local','authenticated','authenticated'),
    ('dddd0000-0000-4000-8000-000000000004', 'llx-exec@test.local',  'authenticated','authenticated'),
    ('dddd0000-0000-4000-8000-000000000005', 'llx-none@test.local',  'authenticated','authenticated'),
    ('dddd0000-0000-4000-8000-000000000006', 'llx-empb@test.local',  'authenticated','authenticated');

  -- emp + opsmgr in dept A; peer/exec/none/empb in dept B.
  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('eeee0000-0000-4000-8000-000000000001','dddd0000-0000-4000-8000-000000000001','LLX-001','موظف الهدف',       'cccc0000-0000-4000-8000-00000000000a','active',true),
    ('eeee0000-0000-4000-8000-000000000002','dddd0000-0000-4000-8000-000000000002','LLX-002','زميل إدارة ب',     'cccc0000-0000-4000-8000-00000000000b','active',true),
    ('eeee0000-0000-4000-8000-000000000003','dddd0000-0000-4000-8000-000000000003','LLX-003','مدير العمليات',    'cccc0000-0000-4000-8000-00000000000a','active',true),
    ('eeee0000-0000-4000-8000-000000000004','dddd0000-0000-4000-8000-000000000004','LLX-004','المدير التنفيذي',  'cccc0000-0000-4000-8000-00000000000b','active',true),
    ('eeee0000-0000-4000-8000-000000000005','dddd0000-0000-4000-8000-000000000005','LLX-005','موظف غير مخوّل',   'cccc0000-0000-4000-8000-00000000000b','active',true),
    ('eeee0000-0000-4000-8000-000000000006','dddd0000-0000-4000-8000-000000000006','LLX-006','موظف غير نشط',     'cccc0000-0000-4000-8000-00000000000b','terminated',false);

  insert into public.profiles (id, employee_id, status)
  select u, e, 'active' from (values
    ('dddd0000-0000-4000-8000-000000000001'::uuid,'eeee0000-0000-4000-8000-000000000001'::uuid),
    ('dddd0000-0000-4000-8000-000000000002'::uuid,'eeee0000-0000-4000-8000-000000000002'::uuid),
    ('dddd0000-0000-4000-8000-000000000003'::uuid,'eeee0000-0000-4000-8000-000000000003'::uuid),
    ('dddd0000-0000-4000-8000-000000000004'::uuid,'eeee0000-0000-4000-8000-000000000004'::uuid),
    ('dddd0000-0000-4000-8000-000000000005'::uuid,'eeee0000-0000-4000-8000-000000000005'::uuid),
    ('dddd0000-0000-4000-8000-000000000006'::uuid,'eeee0000-0000-4000-8000-000000000006'::uuid)
  ) as t(u,e);

  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('dddd0000-0000-4000-8000-000000000001'::uuid,'employee'),
    ('dddd0000-0000-4000-8000-000000000002'::uuid,'employee'),
    ('dddd0000-0000-4000-8000-000000000003'::uuid,'operations-manager'),
    ('dddd0000-0000-4000-8000-000000000004'::uuid,'executive-director'),
    ('dddd0000-0000-4000-8000-000000000005'::uuid,'employee'),
    ('dddd0000-0000-4000-8000-000000000006'::uuid,'employee')
  ) as t(u,slug)
  join public.roles r on r.slug=t.slug;
end
$fixture$;

-- Helper to switch persona.
create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_user::text,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- =====================================================================
-- Executive-director (org scope) as requester
-- =====================================================================
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004');
set local role authenticated;

-- 1. executive requests in-scope employee (snapshot) -> pending
select lives_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000001','snapshot','متابعة إدارية')$$,
  'exec: request snapshot for in-scope employee succeeds');

-- clean the created request so we can test combined mode without the single-active guard
reset role;
delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004');
set local role authenticated;

-- 2. combined location_video mode -> duration 2, videoSeconds 5, needs both
select is(
  (select (r.duration_minutes=2 and (r.metadata->>'videoSeconds')='5'
           and (r.metadata->>'needsVideo')::boolean and (r.metadata->>'needsPoint')::boolean)
   from public.request_live_location('eeee0000-0000-4000-8000-000000000001','location_video','فيديو وموقع') r),
  true, 'exec: location_video sets duration=2, videoSeconds=5, needsPoint+needsVideo');

-- 6. request own location -> 22023
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000004','snapshot','نفسي')$$,
  '22023', null, 'exec: cannot request own location');

-- 7. reason is intentionally optional in the executive flow.
select lives_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000002','snapshot','')$$,
  'exec: request without reason succeeds');

reset role;
delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000002';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004');
set local role authenticated;

-- 8. invalid mode -> 22023
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000002','teleport','وضع غير صالح')$$,
  '22023', null, 'exec: invalid mode rejected');

-- 9. resend inside the server cooldown is rejected without touching the first request.
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000001','snapshot','طلب مكرر نشط')$$,
  '22023', null, 'exec: resend inside 30-second cooldown rejected');

-- Once the cooldown elapses, a second independent request is allowed and the
-- earlier active request remains active/history-preserved.
reset role;
update public.live_location_requests
set requested_at = now() - interval '31 seconds'
where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004');
set local role authenticated;
select is(
  (with created as (
     select public.request_live_location(
       'eeee0000-0000-4000-8000-000000000001','snapshot','إعادة مستقلة'
     )
   )
   select count(*)::int
   from public.live_location_requests
   where employee_id='eeee0000-0000-4000-8000-000000000001'
     and status in ('pending','accepted','active')),
  2,
  'exec: resend after cooldown preserves the previous active request');

-- 10. request inactive employee -> P0002 (emp #6 seeded inactive)
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000006','snapshot','موظف غير نشط')$$,
  'P0002', null, 'exec: inactive employee rejected');

-- 20 (audit). requested + response_viewed audit rows exist for the location_video request
select is(
  (select count(*)::int>=1 from public.audit_events where event_type='live_location.requested'),
  true, 'audit: live_location.requested row written');

-- =====================================================================
-- Operations-manager (department scope)
-- =====================================================================
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000003');
set local role authenticated;

-- 3. ops-manager requests same-dept employee (dept A) -> ok
-- first clear emp's active request so ops-mgr can create one
reset role; delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000003'); set local role authenticated;
select lives_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000001','snapshot','متابعة قسم')$$,
  'ops-manager: request same-department employee succeeds');

-- 4. ops-manager requests out-of-department (dept B) -> 42501
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000002','snapshot','خارج القسم')$$,
  '42501', null, 'ops-manager: out-of-department request rejected');

-- =====================================================================
-- Unauthorized employee (self-only, no live_location.request)
-- =====================================================================
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000005');
set local role authenticated;

-- 5. plain employee requests anyone -> 42501
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000002','snapshot','بلا صلاحية')$$,
  '42501', null, 'employee: cannot request others');

-- =====================================================================
-- Target employee responds + submits (combined location_video path)
-- Recreate a clean location_video request as executive for the target.
-- =====================================================================
reset role;
delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004'); set local role authenticated;
do $mk$
begin
  perform public.request_live_location('eeee0000-0000-4000-8000-000000000001','location_video','فيديو وموقع مدمج');
end $mk$;

-- switch to target
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000001');
set local role authenticated;

-- 13. non-target cannot respond (peer tries) tested below; first: 11. target accepts -> active
select is(
  (select public.respond_live_location_request(
      (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
      true)).status,
  'active', 'target: accept -> status active');

-- 15. submit point while active -> employee_locations row created (does NOT complete: location_video awaits video)
select is(
  (with p as (
     select public.submit_live_location_point(
       (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
       30.05::double precision, 31.23::double precision, 12::double precision,
       null,null,null,false,'قرب شارع النيل، المنيا') r
   )
   select (r).accuracy=12 from p),
  true, 'target: submit point while active succeeds');

-- 20. location_video point does NOT complete the request (awaits video)
select is(
  (select status from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
  'active', 'location_video: point does not complete request (awaits video)');

-- 17. submit point invalid coords -> 22023
select throws_ok(
  format($$select public.submit_live_location_point(%L,200::double precision,31::double precision,10::double precision)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)),
  '22023', null, 'target: invalid coordinates rejected');

-- 18. submit point invalid accuracy -> 22023
select throws_ok(
  format($$select public.submit_live_location_point(%L,30::double precision,31::double precision,-5::double precision)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)),
  '22023', null, 'target: invalid accuracy rejected');

-- 23. register video wrong duration -> 22023
select throws_ok(
  format($$select public.register_live_location_video(%L, %L, 2, 500000::bigint, 'video/mp4', 30.05::double precision, 31.23::double precision, 12::double precision)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
    'eeee0000-0000-4000-8000-000000000001/'||(select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)||'/v.mp4'),
  '22023', null, 'target: too-short video rejected');

-- 24. register video oversize -> 22023
select throws_ok(
  format($$select public.register_live_location_video(%L, %L, 5, 20000000::bigint, 'video/mp4', 30.05::double precision, 31.23::double precision, 12::double precision)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
    'eeee0000-0000-4000-8000-000000000001/'||(select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)||'/v.mp4'),
  '22023', null, 'target: oversize video rejected');

-- 25. register video wrong storage prefix -> 42501
select throws_ok(
  format($$select public.register_live_location_video(%L, %L, 5, 500000::bigint, 'video/mp4', 30.05::double precision, 31.23::double precision, 12::double precision)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
    'someone-else/'||(select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)||'/v.mp4'),
  '42501', null, 'target: wrong storage prefix rejected');

-- 22. register valid video for location_video AFTER point -> completes request
select is(
  (select (public.register_live_location_video(
      (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
      'eeee0000-0000-4000-8000-000000000001/'||(select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)||'/v.mp4',
      5, 900000::bigint, 'video/mp4', 30.05::double precision, 31.23::double precision, 12::double precision)).status),
  'ready', 'target: valid location_video registration ready');

-- 22b. request now completed
select is(
  (select status from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
  'completed', 'location_video: request completed after point+video');

-- 26. register video when no active request -> 22023 (request now completed)
select throws_ok(
  format($$select public.register_live_location_video(%L, %L, 5, 500000::bigint, 'video/mp4', 30::double precision, 31::double precision, 12::double precision)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
    'eeee0000-0000-4000-8000-000000000001/'||(select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)||'/v2.mp4'),
  '22023', null, 'target: video on non-active request rejected');

-- 30. audit video_registered row exists (checked as superuser: audit_events RLS
--     hides rows from the target persona; the write itself is what we assert).
reset role;
select is(
  (select count(*)::int>=1 from public.audit_events where event_type='live_location.video_registered'),
  true, 'audit: video_registered row written');

-- =====================================================================
-- Response read (executive) + RLS isolation
-- =====================================================================
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004');
set local role authenticated;

-- 27. executive reads response -> has point + video
select is(
  (with resp as (
     select public.get_live_location_response(
       (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)) j)
   select (jsonb_array_length(j->'points')>=1 and (j->'video'->>'status')='ready') from resp),
  true, 'executive: response read returns point + video');

-- 30b. a 'view' access-log row was written by the response read
select is(
  (select count(*)::int>=1 from public.live_location_video_access_logs where action='view'),
  true, 'access-log: view row written on response read');

-- Capture the target's request id (under superuser) into a session GUC for the
-- peer test, because the peer's RLS hides the target's request rows from a subquery.
reset role;
select set_config('tests.target_request_id',
  (select id::text from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
  false);

-- =====================================================================
-- Unauthorized read (peer employee, dept B, no view_response on emp)
-- =====================================================================
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000002');
set local role authenticated;

-- 28. unauthorized get_live_location_response -> 42501
select throws_ok(
  format($$select public.get_live_location_response(%L)$$, current_setting('tests.target_request_id')),
  '42501', null, 'peer: cannot read another employee response');

-- 29. RLS: peer sees zero employee_locations / videos_meta of the target via direct select
select is((select count(*)::int from public.employee_locations where employee_id='eeee0000-0000-4000-8000-000000000001'),
  0, 'RLS: peer cannot select target employee_locations');
select is((select count(*)::int from public.live_location_videos_meta where employee_id='eeee0000-0000-4000-8000-000000000001'),
  0, 'RLS: peer cannot select target videos_meta');

-- =====================================================================
-- Respond edge cases (new request; peer is NOT the target)
-- =====================================================================
reset role;
delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004'); set local role authenticated;
do $mk2$ begin perform public.request_live_location('eeee0000-0000-4000-8000-000000000001','snapshot','طلب لاختبار الرفض'); end $mk2$;

-- 13. non-target responds -> P0002
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000002'); set local role authenticated;
select throws_ok(
  format($$select public.respond_live_location_request(%L, true)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)),
  'P0002', null, 'non-target cannot respond to a request');

-- 12. target rejects -> rejected
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000001'); set local role authenticated;
select is(
  (select public.respond_live_location_request(
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
    false)).status,
  'rejected', 'target: reject -> status rejected');

-- 14. respond to non-pending (already rejected) -> 22023
select throws_ok(
  format($$select public.respond_live_location_request(%L, true)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)),
  '22023', null, 'target: cannot respond to non-pending request');

-- 16. submit point on non-active (rejected) request -> 22023
select throws_ok(
  format($$select public.submit_live_location_point(%L,30::double precision,31::double precision,10::double precision)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)),
  '22023', null, 'target: submit point on non-active request rejected');

-- 19. snapshot point auto-completes: fresh snapshot request accepted then point -> completed
reset role;
delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004'); set local role authenticated;
do $mk3$ begin perform public.request_live_location('eeee0000-0000-4000-8000-000000000001','snapshot','لقطة سريعة'); end $mk3$;
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000001'); set local role authenticated;
do $mk4$
declare v_id uuid;
begin
  select id into v_id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1;
  perform public.respond_live_location_request(v_id, true);
  perform public.submit_live_location_point(v_id, 30.1, 31.1, 8);
end $mk4$;
select is(
  (select status from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
  'completed', 'snapshot: point auto-completes request');

-- 21. video_5s registration completes without a point.
reset role;
delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004'); set local role authenticated;
do $mk5$ begin perform public.request_live_location('eeee0000-0000-4000-8000-000000000001','video_5s','فيديو فقط'); end $mk5$;
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000001'); set local role authenticated;
do $mk6$
declare v_id uuid;
begin
  select id into v_id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1;
  perform public.respond_live_location_request(v_id, true);
  perform public.register_live_location_video(v_id,
    'eeee0000-0000-4000-8000-000000000001/'||v_id||'/only.mp4', 5, 800000::bigint, 'video/mp4', 30.0, 31.0, 10.0);
end $mk6$;
select is(
  (select status from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
  'completed', 'video_5s: video registration completes request without point');

-- =====================================================================
-- Legal hold (executive-secretary is full-access; executive-director has
-- no manage_retention -> rejected).
-- =====================================================================
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004'); set local role authenticated;
select throws_ok(
  format($$select public.set_live_location_legal_hold(%L, now()+interval '7 days', 'حفظ للتحقيق')$$,
    (select id from public.live_location_videos_meta order by created_at desc limit 1)),
  '42501', null, 'executive-director without manage_retention cannot set legal hold');

-- 30c. executive attendance overview returns a summary for the executive.
select is(
  (select (public.get_executive_attendance_overview(current_date)->'summary'->>'total') is not null),
  true, 'executive: attendance overview returns summary');

select * from finish();
rollback;
