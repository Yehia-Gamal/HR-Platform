-- 0032: P2/P3 audit remediation runtime proof (migration 0052).
-- Proves the runtime-observable P2 fixes. Rolls back.
--
-- Covers:
--   CTB-04 [P2] security_events.handled_by is server-forced to the caller
--               (a client-supplied handled_by is overwritten by the trigger).
--   CTB-02 [P2] a plain service-request requester cannot self-transition their
--               ticket to a privileged status (resolved); cancel is allowed.
--   SDEF-01[P2] anon/public EXECUTE is revoked on the 0035/0036 DEFINER RPCs.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(6);

-- =====================================================================
-- Fixture
-- =====================================================================
do $fixture$
declare
  v_le    uuid := 'dddddddd-0000-4000-8000-000000000000';
  v_dept  uuid := 'dddddddd-0000-4000-8000-00000000000a';
  v_role  uuid;
  v_pm    uuid;
  v_cat   uuid := 'dddddddd-0000-4000-8000-0000000000ca';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'P2-LE', 'كيان P2');
  insert into public.departments (id, legal_entity_id, code, name) values (v_dept, v_le, 'P2-D', 'إدارة P2');

  insert into auth.users (id, email, aud, role) values
    ('66666666-0000-4000-8000-000000000001', 'p2-sec@test.local',   'authenticated', 'authenticated'),
    ('66666666-0000-4000-8000-000000000002', 'p2-req@test.local',   'authenticated', 'authenticated'),
    ('66666666-0000-4000-8000-000000000003', 'p2-other@test.local', 'authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('77777777-0000-4000-8000-000000000001', '66666666-0000-4000-8000-000000000001', 'P2-001', 'مسؤول أمن', v_dept, 'active', true),
    ('77777777-0000-4000-8000-000000000002', '66666666-0000-4000-8000-000000000002', 'P2-002', 'مقدّم تذكرة', v_dept, 'active', true);

  insert into public.profiles (id, employee_id, status) values
    ('66666666-0000-4000-8000-000000000001', '77777777-0000-4000-8000-000000000001', 'active'),
    ('66666666-0000-4000-8000-000000000002', '77777777-0000-4000-8000-000000000002', 'active');

  -- security manager role for the security officer
  select id into v_pm from public.permissions where code = 'security.event.manage';
  if v_pm is null then
    insert into public.permissions(code,module,resource,action,description,risk_level)
    values('security.event.manage','security','event','manage','إدارة الأحداث الأمنية','critical') returning id into v_pm;
  end if;
  insert into public.roles (id, slug, name_ar, is_system, is_full_access)
  values (gen_random_uuid(), 'p2-secmgr', 'مدير أمن اختبار', false, false) returning id into v_role;
  insert into public.role_permissions (role_id, permission_id, scope) values (v_role, v_pm, 'organization');
  insert into public.user_roles (user_id, role_id) values ('66666666-0000-4000-8000-000000000001', v_role);

  -- a security event to be handled
  insert into public.security_events (id, event_type, severity, details)
  values ('88888888-0000-4000-8000-000000000001', 'login_failed', 'medium', '{}'::jsonb);

  -- a service catalog item + a ticket owned by the requester
  insert into public.service_catalog_items (id, code, name_ar, category, sla_hours, active)
  values (v_cat, 'P2-SVC', 'خدمة اختبار', 'general', 24, true);
  insert into public.service_requests (id, catalog_item_id, requester_employee_id, title, status)
  values ('99999999-0000-4000-8000-000000000001', v_cat, '77777777-0000-4000-8000-000000000002', 'تذكرة اختبار', 'submitted');
end
$fixture$;

-- =====================================================================
-- SDEF-01 [P2] — anon/public EXECUTE revoked on DEFINER RPCs
-- =====================================================================
select is(
  has_function_privilege('anon', 'public.get_my_payslips()', 'EXECUTE'),
  false,
  'SDEF-01: anon cannot EXECUTE get_my_payslips (0036)');
select is(
  has_function_privilege('anon', 'public.get_people_finance_catalog()', 'EXECUTE'),
  false,
  'SDEF-01: anon cannot EXECUTE get_people_finance_catalog (0036)');
select is(
  has_function_privilege('anon', 'public.get_my_service_portal()', 'EXECUTE'),
  false,
  'SDEF-01: anon cannot EXECUTE get_my_service_portal (0035)');

-- =====================================================================
-- CTB-04 [P2] — handled_by is server-forced to the caller
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"66666666-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '66666666-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

-- security officer marks the event handled but tries to attribute it to ANOTHER user
update public.security_events
  set handled = true, handled_by = '66666666-0000-4000-8000-000000000003'
  where id = '88888888-0000-4000-8000-000000000001';

reset role;
select is(
  (select handled_by from public.security_events where id = '88888888-0000-4000-8000-000000000001'),
  '66666666-0000-4000-8000-000000000001'::uuid,
  'CTB-04: handled_by is forced to the actual caller, not the forged value');

-- =====================================================================
-- CTB-02 [P2] — requester cannot self-transition to a privileged status
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"66666666-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '66666666-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select throws_ok(
  $$update public.service_requests set status = 'resolved' where id = '99999999-0000-4000-8000-000000000001'$$,
  '42501', null,
  'CTB-02: requester cannot self-resolve their own ticket');

select lives_ok(
  $$update public.service_requests set status = 'cancelled' where id = '99999999-0000-4000-8000-000000000001'$$,
  'CTB-02: requester may cancel their own ticket');

reset role;

select * from finish();
rollback;
