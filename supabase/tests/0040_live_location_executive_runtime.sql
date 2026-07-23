-- 0040: Live-location executive flow runtime (Migrations 0067→0124).
-- Runs real persona contexts (JWT claims + role switch) against the live
-- RLS policies and SECURITY DEFINER RPCs for the executive location journey.
-- Everything rolls back.
--
-- V12 §9 policy: the video feature is PERMANENTLY REMOVED. This contract now
-- asserts that snapshot/track_* modes work and that video modes are rejected.
--
-- Personas:
--   executive-director (org scope), operations-manager (dept scope),
--   employee target (dept A), peer employee (dept B), unauthorized employee.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(20);

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

-- 2. snapshot metadata: needsPoint=true, needsVideo=false, videoRemoved=true
select is(
  (select ((r.metadata->>'needsPoint')::boolean
           and not (r.metadata->>'needsVideo')::boolean
           and (r.metadata->>'videoRemoved')::boolean)
   from public.live_location_requests r
   where r.employee_id='eeee0000-0000-4000-8000-000000000001'
   order by r.requested_at desc limit 1),
  true, 'exec: snapshot metadata is point-only, video removed');

-- 3. V12 §9: location_video mode is rejected (video removed)
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000001','location_video','فيديو وموقع')$$,
  '22023', null, 'exec: location_video mode rejected (V12 §9)');

-- 4. V12 §9: video_5s mode is rejected (video removed)
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000001','video_5s','فيديو فقط')$$,
  '22023', null, 'exec: video_5s mode rejected (V12 §9)');

-- 5. request own location -> 22023
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000004','snapshot','نفسي')$$,
  '22023', null, 'exec: cannot request own location');

-- 6. reason is optional in the executive flow.
select lives_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000002','snapshot','')$$,
  'exec: request without reason succeeds');

-- 7. invalid mode -> 22023
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000002','teleport','وضع غير صالح')$$,
  '22023', null, 'exec: invalid mode rejected');

-- 8. resend inside 30-second cooldown rejected
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000001','snapshot','طلب مكرر')$$,
  '22023', null, 'exec: resend inside 30-second cooldown rejected');

-- 9. track_15 mode works and sets duration=15
reset role;
delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004'); set local role authenticated;
select is(
  (select r.duration_minutes
   from public.request_live_location('eeee0000-0000-4000-8000-000000000001','track_15','تتبع') r),
  15, 'exec: track_15 sets duration=15');

-- 10. inactive employee -> P0002
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000006','snapshot','غير نشط')$$,
  'P0002', null, 'exec: inactive employee rejected');

-- 11. audit row written
reset role;
select is(
  (select count(*)::int>=1 from public.audit_events where event_type='live_location.requested'),
  true, 'audit: live_location.requested row written');

-- =====================================================================
-- Operations-manager (department scope)
-- =====================================================================
reset role; delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000003'); set local role authenticated;

-- 12. ops-manager requests same-dept employee (dept A) -> ok
select lives_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000001','snapshot','متابعة قسم')$$,
  'ops-manager: request same-department employee succeeds');

-- 13. ops-manager requests out-of-department (dept B) -> 42501
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000002','snapshot','خارج القسم')$$,
  '42501', null, 'ops-manager: out-of-department request rejected');

-- =====================================================================
-- Unauthorized employee (self-only, no live_location.request)
-- =====================================================================
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000005'); set local role authenticated;

-- 14. plain employee requests anyone -> 42501
select throws_ok(
  $$select public.request_live_location('eeee0000-0000-4000-8000-000000000002','snapshot','بلا صلاحية')$$,
  '42501', null, 'employee: cannot request others');

-- =====================================================================
-- Target responds + submits point (snapshot auto-completes)
-- =====================================================================
reset role;
delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004'); set local role authenticated;
do $mk$ begin perform public.request_live_location('eeee0000-0000-4000-8000-000000000001','snapshot','لقطة'); end $mk$;

select pg_temp.act_as('dddd0000-0000-4000-8000-000000000001'); set local role authenticated;

-- 15. target accepts -> active
select is(
  (select public.respond_live_location_request(
      (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
      true)).status,
  'active', 'target: accept -> status active');

-- 16. submit point (snapshot) -> completes request
do $pt$
declare v_id uuid;
begin
  select id into v_id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1;
  perform public.submit_live_location_point(v_id, 30.05::double precision, 31.23::double precision, 12::double precision);
end $pt$;
select is(
  (select status from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
  'completed', 'snapshot: point auto-completes request');

-- 17. submit point invalid coords -> 22023 (new pending request)
reset role;
delete from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001';
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004'); set local role authenticated;
do $mk2$ begin perform public.request_live_location('eeee0000-0000-4000-8000-000000000001','snapshot','لاختبار الإحداثيات'); end $mk2$;
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000001'); set local role authenticated;
do $acc$
declare v_id uuid;
begin
  select id into v_id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1;
  perform public.respond_live_location_request(v_id, true);
end $acc$;
select throws_ok(
  format($$select public.submit_live_location_point(%L,200::double precision,31::double precision,10::double precision)$$,
    (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)),
  '22023', null, 'target: invalid coordinates rejected');

-- Now submit a VALID point so the executive read below returns a point.
do $vpt$
declare v_id uuid;
begin
  select id into v_id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1;
  perform public.submit_live_location_point(v_id, 30.05::double precision, 31.23::double precision, 12::double precision);
end $vpt$;

-- =====================================================================
-- Response read (executive) + RLS isolation
-- =====================================================================
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000004'); set local role authenticated;

-- 18. executive reads response -> has at least one point
select is(
  (with resp as (
     select public.get_live_location_response(
       (select id from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1)) j)
   select (jsonb_array_length(j->'points')>=1) from resp),
  true, 'executive: response read returns point');

-- Capture target request id for peer test.
reset role;
select set_config('tests.target_request_id',
  (select id::text from public.live_location_requests where employee_id='eeee0000-0000-4000-8000-000000000001' order by requested_at desc limit 1),
  false);

-- =====================================================================
-- Unauthorized read (peer employee, dept B)
-- =====================================================================
select pg_temp.act_as('dddd0000-0000-4000-8000-000000000002'); set local role authenticated;

-- 19. unauthorized get_live_location_response -> 42501
select throws_ok(
  format($$select public.get_live_location_response(%L)$$, current_setting('tests.target_request_id')),
  '42501', null, 'peer: cannot read another employee response');

-- 20. RLS: peer sees zero employee_locations of the target via direct select
select is((select count(*)::int from public.employee_locations where employee_id='eeee0000-0000-4000-8000-000000000001'),
  0, 'RLS: peer cannot select target employee_locations');

select * from finish();
rollback;
