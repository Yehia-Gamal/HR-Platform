-- 0431: اختبارات إصلاح تعليم أيام المأموريات/القوافل/فاندي من payload
--       + الترتيب الجديد في الكشف الشهري (مأمورية/قافلة/فاندي قبل الإجازة)
-- Personas: موظف (self) / HR (organization). كل شيء يُرجع (rollback).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(19);

-- =====================================================================
-- Pre-fixture: roles + permissions (self-contained)
-- =====================================================================
do $ensure$
declare
  v_perm_id uuid;
  v_role_id uuid;
  v_pair    record;
begin
  insert into public.roles (slug, name_ar, is_system, is_full_access)
  values
    ('employee',            'موظف',           true, false),
    ('hr-manager',          'مدير موارد بشرية', true, false)
  on conflict (slug) do nothing;

  insert into public.permissions (code, module, resource, action) values
    ('people.employee.read', 'people', 'employee', 'read'),
    ('attendance.record.read', 'attendance', 'record', 'read')
  on conflict (code) do nothing;

  -- employee @ self
  for v_pair in
    select * from (values
      ('employee','self','people.employee.read'),
      ('employee','self','attendance.record.read')
    ) as t(slug, scope, code)
  loop
    select id into v_perm_id from public.permissions where code = v_pair.code;
    select id into v_role_id from public.roles where slug = v_pair.slug;
    if v_perm_id is not null and v_role_id is not null then
      insert into public.role_permissions (role_id, permission_id, scope)
      values (v_role_id, v_perm_id, v_pair.scope)
      on conflict (role_id, permission_id, scope) do nothing;
    end if;
  end loop;

  -- hr-manager @ organization
  select id into v_role_id from public.roles where slug = 'hr-manager';
  for v_perm_id in
    select id from public.permissions where code in ('people.employee.read','attendance.record.read')
  loop
    insert into public.role_permissions (role_id, permission_id, scope)
    values (v_role_id, v_perm_id, 'organization')
    on conflict (role_id, permission_id, scope) do nothing;
  end loop;
end $ensure$;

-- =====================================================================
-- Fixture: كيان + إدارة + موظف + HR
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'aaaaaaaa-0000-4000-8000-000000000301';
  v_a uuid := 'aaaaaaaa-0000-4000-8000-000000000302';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'RST-LE2', 'كيان اختبار 0431');
  insert into public.departments (id, legal_entity_id, code, name) values
    (v_a, v_le, 'RST-A2', 'إدارة أ');

  insert into auth.users (id, email, aud, role) values
    ('22222222-0000-4000-8000-000000000301', '0431-emp@test.local',  'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000304', '0431-hr@test.local',   'authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('11111111-0000-4000-8000-000000000301', '22222222-0000-4000-8000-000000000301', 'RST2-001', 'موظف اختبار 0431', v_a, 'active', true),
    ('11111111-0000-4000-8000-000000000304', '22222222-0000-4000-8000-000000000304', 'RST2-004', 'مدير الموارد البشرية', v_a, 'active', true);

  insert into public.profiles (id, employee_id, status)
  select u, e, 'active' from (values
    ('22222222-0000-4000-8000-000000000301'::uuid, '11111111-0000-4000-8000-000000000301'::uuid),
    ('22222222-0000-4000-8000-000000000304'::uuid, '11111111-0000-4000-8000-000000000304'::uuid)
  ) as t(u, e);

  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('22222222-0000-4000-8000-000000000301'::uuid, 'employee'),
    ('22222222-0000-4000-8000-000000000304'::uuid, 'hr-manager')
  ) as t(u, slug)
  join public.roles r on r.slug = t.slug;
end $fixture$;

-- =====================================================================
-- 1) دالة _payload_date
-- =====================================================================
select is(
  public._payload_date('{"startDate":"2030-06-17"}'::jsonb, 'startDate'),
  '2030-06-17'::date,
  '_payload_date: صيغة YYYY-MM-DD');
select is(
  public._payload_date('{"startDate":"2030-06-17T10:00:00.000Z"}'::jsonb, 'startDate'),
  '2030-06-17'::date,
  '_payload_date: صيغة ISO مع وقت');
select is(
  public._payload_date('{}'::jsonb, 'startDate'),
  null,
  '_payload_date: غياب المفتاح يعيد null');

-- =====================================================================
-- 2) مأمورية معتمدة من payload (بدون جدول missions)
-- =====================================================================
insert into public.requests (id, request_type, employee_id, status, workflow_status, title, payload)
values ('33333333-0000-4000-8000-000000000301', 'mission',
        '11111111-0000-4000-8000-000000000301', 'pending', 'submitted', 'مأمورية payload',
        '{"startDate":"2030-06-17","endDate":"2030-06-19","location":"الفيوم"}');
update public.requests set status = 'approved' where id = '33333333-0000-4000-8000-000000000301';

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000301'
     and work_date between '2030-06-17' and '2030-06-19' and status = 'on_leave'),
  3, 'مأمورية payload (3 أيام) → on_leave بلا غياب');

-- مأمورية payload تغطي جمعة (2030-06-21) → بدل راحة أسبوعي تلقائي
insert into public.requests (id, request_type, employee_id, status, workflow_status, title, payload)
values ('33333333-0000-4000-8000-000000000302', 'mission',
        '11111111-0000-4000-8000-000000000301', 'pending', 'submitted', 'مأمورية payload (جمعة)',
        '{"startDate":"2030-06-20","endDate":"2030-06-21"}');
update public.requests set status = 'approved' where id = '33333333-0000-4000-8000-000000000302';

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000301'
     and work_date between '2030-06-20' and '2030-06-21' and status = 'on_leave'),
  2, 'مأمورية payload (20-21) → on_leave');
select is(
  (select count(*)::int from public.leave_ledger_entries
   where source_key = 'weekly-rest:credit:11111111-0000-4000-8000-000000000301:2030-06-21'),
  1, 'بدل راحة أسبوعي تلقائي عن جمعة المأمورية (payload)');

-- =====================================================================
-- 3) قافلة معتمدة من payload (بدون جدول convoy_requests)
-- =====================================================================
insert into public.requests (id, request_type, employee_id, status, workflow_status, title, payload)
values ('33333333-0000-4000-8000-000000000303', 'convoy',
        '11111111-0000-4000-8000-000000000301', 'pending', 'submitted', 'قافلة payload',
        '{"startDate":"2030-06-24","endDate":"2030-06-25","location":"الريف الأوروبي"}');
update public.requests set status = 'approved' where id = '33333333-0000-4000-8000-000000000303';

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000301'
     and work_date between '2030-06-24' and '2030-06-25' and status = 'on_leave'),
  2, 'قافلة payload → on_leave بلا غياب');

-- =====================================================================
-- 4) فاندي معتمد من payload (فرع جديد كامل)
-- =====================================================================
insert into public.requests (id, request_type, employee_id, status, workflow_status, title, payload)
values ('33333333-0000-4000-8000-000000000304', 'fundraising',
        '11111111-0000-4000-8000-000000000301', 'pending', 'submitted', 'فاندي payload',
        '{"startDate":"2030-06-26","endDate":"2030-06-27","location":"المنيا"}');
update public.requests set status = 'approved' where id = '33333333-0000-4000-8000-000000000304';

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000301'
     and work_date between '2030-06-26' and '2030-06-27' and status = 'on_leave'),
  2, 'فاندي payload → on_leave بلا غياب');

-- =====================================================================
-- 5) إجازة معتمدة (مسار قائم لا انحدار)
-- =====================================================================
select public.apply_leave_ledger_entry(
  '11111111-0000-4000-8000-000000000301',
  (select id from public.leave_types where code = 'annual'),
  2030, 'opening', 30,
  '0431-test:opening:annual:2030', null, 'رصيد افتتاحي للاختبار');
insert into public.requests (id, request_type, employee_id, status, workflow_status, title)
values ('33333333-0000-4000-8000-000000000305', 'leave',
        '11111111-0000-4000-8000-000000000301', 'pending', 'submitted', 'إجازة اختبار 0431');
insert into public.leave_requests (request_id, employee_id, leave_type_id, start_date, end_date, days_count)
values ('33333333-0000-4000-8000-000000000305', '11111111-0000-4000-8000-000000000301',
        (select id from public.leave_types where code = 'annual'), '2030-06-02', '2030-06-03', 2);
update public.requests set status = 'approved' where id = '33333333-0000-4000-8000-000000000305';

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000301'
     and work_date between '2030-06-02' and '2030-06-03' and status = 'on_leave'),
  2, 'إجازة معتمدة → on_leave (لا انحدار)');

-- =====================================================================
-- 6) الكشف الشهري (persona HR): الترتيب الجديد + الملخص
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000304","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000304', true);
end $$;
set local role authenticated;

select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'days') x
   where x->>'date' = '2030-06-17'),
  'مأمورية', 'الكشف: يوم مأمورية payload يُعرض مأمورية (لا غياب)');
select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'days') x
   where x->>'date' = '2030-06-18'),
  'مأمورية', 'الكشف: المأمورية تسبق الإجازة في اليومين المشتركين (18)');
select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'days') x
   where x->>'date' = '2030-06-02'),
  'إجازة معتمدة', 'الكشف: يوم إجازة يُعرض إجازة معتمدة');
select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'days') x
   where x->>'date' = '2030-06-24'),
  'قافلة', 'الكشف: يوم قافلة payload يُعرض قافلة');
select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'days') x
   where x->>'date' = '2030-06-26'),
  'فاندي', 'الكشف: يوم فاندي payload يُعرض فاندي');
select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'days') x
   where x->>'date' = '2030-06-21'),
  'راحة أسبوعية', 'الكشف: الجمعة تبقى راحة أسبوعية (سلوك قائم)');

select is(
  ((public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'summary'->>'missionDays')::int,
  5, 'الكشف: missionDays = 5');
select is(
  ((public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'summary'->>'convoyFundiDays')::int,
  4, 'الكشف: convoyFundiDays = 4 (قافلة 2 + فاندي 2)');
select is(
  ((public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'summary'->>'leaveDays')::int,
  2, 'الكشف: leaveDays = 2');
select is(
  ((public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000301', 2030, 6))->'summary'->>'absentDays')::int,
  16, 'الكشف: absentDays = 16 (بلا أي يوم عمل معتمد)');

rollback;