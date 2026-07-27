-- 0037: Problems & disputes committee — end-to-end runtime behavior.
-- Exercises the 0059/0060 workflow against live RLS + SECURITY DEFINER RPCs
-- with real persona contexts (JWT claims + role switch). Everything rolls back.
--
-- Covers: widened case_type CHECK, employee self-intake happy path, intake
-- validation (missing party, self as party, disallowed priority), respondent
-- confidentiality (hidden until notified), and workflow authorization.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- =====================================================================
-- Fixture (superuser; RLS not yet in play)
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'dddddddd-0000-4000-8000-000000000000';
  v_dept uuid := 'dddddddd-0000-4000-8000-000000000001';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'DSP-LE', 'كيان اختبار الشكاوى');
  insert into public.departments (id, legal_entity_id, code, name) values
    (v_dept, v_le, 'DSP-D', 'إدارة الشكاوى');

  insert into auth.users (id, email, aud, role) values
    ('44444444-0000-4000-8000-000000000001', 'dsp-emp@test.local',   'authenticated', 'authenticated'),
    ('44444444-0000-4000-8000-000000000002', 'dsp-resp@test.local',  'authenticated', 'authenticated'),
    ('44444444-0000-4000-8000-000000000003', 'dsp-admin@test.local', 'authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('55555555-0000-4000-8000-000000000001', '44444444-0000-4000-8000-000000000001', 'DSP-001', 'الموظف المشتكي', v_dept, 'active', true),
    ('55555555-0000-4000-8000-000000000002', '44444444-0000-4000-8000-000000000002', 'DSP-002', 'الطرف الآخر',    v_dept, 'active', true),
    ('55555555-0000-4000-8000-000000000003', '44444444-0000-4000-8000-000000000003', 'DSP-003', 'السكرتير التنفيذي', v_dept, 'active', true);

  insert into public.profiles (id, employee_id, status)
  select u, e, 'active' from (values
    ('44444444-0000-4000-8000-000000000001'::uuid, '55555555-0000-4000-8000-000000000001'::uuid),
    ('44444444-0000-4000-8000-000000000002'::uuid, '55555555-0000-4000-8000-000000000002'::uuid),
    ('44444444-0000-4000-8000-000000000003'::uuid, '55555555-0000-4000-8000-000000000003'::uuid)
  ) as t(u, e);

  -- complainant + respondent are plain employees; admin has the 'admin' role
  -- (is_full_access=true) that owns the committee workflow.
  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('44444444-0000-4000-8000-000000000001'::uuid, 'employee'),
    ('44444444-0000-4000-8000-000000000002'::uuid, 'employee'),
    ('44444444-0000-4000-8000-000000000003'::uuid, 'admin')
  ) as t(u, slug)
  join public.roles r on r.slug = t.slug;
end
$fixture$;

-- =====================================================================
-- Schema-level: case_type CHECK accepts the new spec values (0060 fix).
-- =====================================================================
select lives_ok(
  $$insert into public.dispute_cases (case_number, title, description, case_type, status, severity, actor_employee_id)
    values ('CHK-1', 'عنوان تحقق', 'وصف كافٍ للتحقق من قيد النوع', 'verbal_abuse', 'submitted', 'normal',
            '55555555-0000-4000-8000-000000000001')$$,
  'case_type CHECK accepts the widened dispute value set');
delete from public.dispute_cases where case_number = 'CHK-1';

-- =====================================================================
-- Persona: complainant employee — self-intake happy path
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.submit_my_dispute(
      'خلاف حول توزيع المهام',
      'حدث خلاف متكرر حول توزيع المهام اليومية ويؤثر على سير العمل داخل الفريق.',
      'employee_conflict', 'normal', null, 'المكتب',
      '[{"employeeId":"55555555-0000-4000-8000-000000000002","type":"respondent"}]'::jsonb,
      '[]'::jsonb, null, null, null, 'التوسط لحل الخلاف', true, true, true)$$,
  'employee submits a dispute through the self-intake RPC');

select is(
  (select status from public.dispute_cases where title = 'خلاف حول توزيع المهام'),
  'submitted',
  'new dispute starts in submitted state');
select ok(
  (select review_due_at is not null from public.dispute_cases where title = 'خلاف حول توزيع المهام'),
  '24h review SLA due-at is stamped on intake');
select is(
  (select count(*)::int from public.dispute_parties dp
     join public.dispute_cases c on c.id = dp.case_id
    where c.title = 'خلاف حول توزيع المهام' and dp.party_type = 'complainant'),
  1,
  'complainant is registered as a party on intake');

-- intake validation
select throws_ok(
  $$select public.submit_my_dispute('عنوان صالح','وصف كافٍ لا يقل عن عشرين حرفًا هنا','employee_conflict','normal',
      null,null,'[]'::jsonb,'[]'::jsonb,null,null,null,null,true,true,true)$$,
  '22023', null,
  'intake requires at least one party');
select throws_ok(
  $$select public.submit_my_dispute('عنوان صالح','وصف كافٍ لا يقل عن عشرين حرفًا هنا','employee_conflict','critical',
      null,null,'[{"employeeId":"55555555-0000-4000-8000-000000000002","type":"respondent"}]'::jsonb,
      '[]'::jsonb,null,null,null,null,true,true,true)$$,
  '22023', null,
  'employee cannot set critical priority');
select throws_ok(
  $$select public.submit_my_dispute('عنوان صالح','وصف كافٍ لا يقل عن عشرين حرفًا هنا','employee_conflict','normal',
      null,null,'[{"employeeId":"55555555-0000-4000-8000-000000000001","type":"respondent"}]'::jsonb,
      '[]'::jsonb,null,null,null,null,true,true,true)$$,
  '22023', null,
  'complainant cannot list themselves as a party');
select throws_ok(
  $$select public.submit_my_dispute('عنوان','وصف كافٍ لا يقل عن عشرين حرفًا هنا','employee_conflict','normal',
      null,null,'[{"employeeId":"55555555-0000-4000-8000-000000000002","type":"respondent"}]'::jsonb,
      '[]'::jsonb,null,null,null,null,true,false,false)$$,
  '22023', null,
  'intake requires truth + confidentiality confirmations');

-- complainant sees own case, plus authorization boundary
select is((select count(*)::int from public.dispute_cases where title = 'خلاف حول توزيع المهام'), 1,
  'complainant can read their own case');
select throws_ok(
  $$select public.transition_dispute_case(
      (select id from public.dispute_cases where title = 'خلاف حول توزيع المهام'),
      'accept', 'محاولة غير مخولة')$$,
  '42501', null,
  'plain employee cannot drive the case workflow');

-- =====================================================================
-- Persona: respondent employee — hidden until notified (confidentiality)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.dispute_cases where title = 'خلاف حول توزيع المهام'), 0,
  'respondent cannot see the case before being notified');
select is(
  (select public.can_access_dispute((select id from public.dispute_cases where title = 'خلاف حول توزيع المهام')))::text,
  'false',
  'can_access_dispute is false for an un-notified respondent');

-- notify the respondent (superuser stands in for committee decision to notify)
reset role;
update public.dispute_parties
   set notified_at = now(), notification_status = 'notified'
 where case_id = (select id from public.dispute_cases where title = 'خلاف حول توزيع المهام')
   and employee_id = '55555555-0000-4000-8000-000000000002';

do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.dispute_cases where title = 'خلاف حول توزيع المهام'), 1,
  'respondent can see the case once notified');

-- =====================================================================
-- Persona: admin (full-access) — full workflow authority
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000003', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.dispute_cases where title = 'خلاف حول توزيع المهام'), 1,
  'admin (full-access) reads committee cases org-wide');
select lives_ok(
  $$select public.transition_dispute_case(
      (select id from public.dispute_cases where title = 'خلاف حول توزيع المهام'),
      'accept', 'قبول المشكلة للدراسة')$$,
  'admin can drive the case workflow');

reset role;
select * from finish();
rollback;
