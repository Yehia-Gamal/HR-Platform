-- 0429: اختبارات تحصين الوصول (الحضور/الإجازات) + المأموريات/القوافل لا تُحتسب غياباً
--       + بدل الراحة الأسبوعي (الجمعة: مأمورية/قافلة/تكليف) + المنح اليدوي.
-- Personas: موظف (self) / مدير مباشر / HR / تنفيذي. كل شيء يُرجع (rollback).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(37);

-- =====================================================================
-- Pre-fixture: roles + permissions + role_permissions (self-contained)
-- =====================================================================
do $ensure$
declare
  v_perm_id uuid;
  v_role_id uuid;
  v_pair record;
begin
  insert into public.roles (slug, name_ar, is_system, is_full_access)
  values
    ('employee',            'موظف',           true, false),
    ('direct-manager',      'مدير مباشر',     true, false),
    ('hr-manager',          'مدير موارد بشرية', true, false),
    ('executive-director',  'المدير التنفيذي', true, false)
  on conflict (slug) do nothing;

  insert into public.permissions (code, module, resource, action) values
    ('people.employee.read', 'people', 'employee', 'read'),
    ('attendance.record.read', 'attendance', 'record', 'read'),
    ('attendance.record.process', 'attendance', 'record', 'process'),
    ('requests.leave.balance.adjust', 'requests', 'leave', 'balance-adjust')
  on conflict (code) do nothing;

  -- employee @ self
  select id into v_role_id from public.roles where slug = 'employee';
  for v_pair in
    select * from (values
      ('employee','self','people.employee.read'),
      ('employee','self','attendance.record.read'),
      ('employee','self','attendance.record.process')
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

  -- direct-manager @ direct_reports
  select id into v_role_id from public.roles where slug = 'direct-manager';
  for v_perm_id in
    select id from public.permissions where code in ('people.employee.read','attendance.record.read')
  loop
    insert into public.role_permissions (role_id, permission_id, scope)
    values (v_role_id, v_perm_id, 'direct_reports')
    on conflict (role_id, permission_id, scope) do nothing;
  end loop;

  -- hr-manager + executive-director @ organization
  for v_pair in
    select * from (values
      ('hr-manager',             'people.employee.read'),
      ('hr-manager',             'attendance.record.read'),
      ('hr-manager',             'attendance.record.process'),
      ('hr-manager',             'requests.leave.balance.adjust'),
      ('executive-director',     'people.employee.read'),
      ('executive-director',     'attendance.record.read')
    ) as t(slug, code)
  loop
    select id into v_role_id from public.roles where slug = v_pair.slug;
    select id into v_perm_id from public.permissions where code = v_pair.code;
    if v_role_id is not null and v_perm_id is not null then
      insert into public.role_permissions (role_id, permission_id, scope)
      values (v_role_id, v_perm_id, 'organization')
      on conflict (role_id, permission_id, scope) do nothing;
    end if;
  end loop;
end $ensure$;

-- =====================================================================
-- Fixture: كيان + إدارتان + مستخدمون/موظفون + أدوار + علاقة إشراف
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'aaaaaaaa-0000-4000-8000-000000000201';
  v_a uuid := 'aaaaaaaa-0000-4000-8000-000000000202';
  v_b uuid := 'aaaaaaaa-0000-4000-8000-000000000203';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'RST-LE', 'كيان اختبار 0429');
  insert into public.departments (id, legal_entity_id, code, name) values
    (v_a, v_le, 'RST-A', 'إدارة أ'),
    (v_b, v_le, 'RST-B', 'إدارة ب');

  insert into auth.users (id, email, aud, role) values
    ('22222222-0000-4000-8000-000000000201', '0429-emp@test.local',  'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000202', '0429-peer@test.local', 'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000203', '0429-mgr@test.local',  'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000204', '0429-hr@test.local',   'authenticated', 'authenticated'),
    ('22222222-0000-4000-8000-000000000205', '0429-exec@test.local', 'authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('11111111-0000-4000-8000-000000000201', '22222222-0000-4000-8000-000000000201', 'RST-001', 'موظف الاختبار',    v_a, 'active', true),
    ('11111111-0000-4000-8000-000000000202', '22222222-0000-4000-8000-000000000202', 'RST-002', 'زميل إدارة أخرى',  v_b, 'active', true),
    ('11111111-0000-4000-8000-000000000203', '22222222-0000-4000-8000-000000000203', 'RST-003', 'المدير المباشر',   v_a, 'active', true),
    ('11111111-0000-4000-8000-000000000204', '22222222-0000-4000-8000-000000000204', 'RST-004', 'مدير الموارد البشرية', v_b, 'active', true),
    ('11111111-0000-4000-8000-000000000205', '22222222-0000-4000-8000-000000000205', 'RST-005', 'المدير التنفيذي',  v_b, 'active', true);

  insert into public.profiles (id, employee_id, status)
  select u, e, 'active' from (values
    ('22222222-0000-4000-8000-000000000201'::uuid, '11111111-0000-4000-8000-000000000201'::uuid),
    ('22222222-0000-4000-8000-000000000202'::uuid, '11111111-0000-4000-8000-000000000202'::uuid),
    ('22222222-0000-4000-8000-000000000203'::uuid, '11111111-0000-4000-8000-000000000203'::uuid),
    ('22222222-0000-4000-8000-000000000204'::uuid, '11111111-0000-4000-8000-000000000204'::uuid),
    ('22222222-0000-4000-8000-000000000205'::uuid, '11111111-0000-4000-8000-000000000205'::uuid)
  ) as t(u, e);

  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('22222222-0000-4000-8000-000000000201'::uuid, 'employee'),
    ('22222222-0000-4000-8000-000000000202'::uuid, 'employee'),
    ('22222222-0000-4000-8000-000000000203'::uuid, 'employee'),
    ('22222222-0000-4000-8000-000000000203'::uuid, 'direct-manager'),
    ('22222222-0000-4000-8000-000000000204'::uuid, 'hr-manager'),
    ('22222222-0000-4000-8000-000000000205'::uuid, 'executive-director')
  ) as t(u, slug)
  join public.roles r on r.slug = t.slug;

  insert into public.manager_relations (employee_id, manager_employee_id, relation_type)
  values ('11111111-0000-4000-8000-000000000201', '11111111-0000-4000-8000-000000000203', 'primary');

  -- حضور اليوم للموظف الزميل (لاختبار الحالة العامة في الدليل) + حضور للزميل بلا رصيد
  insert into public.attendance_daily (employee_id, work_date, status)
  values ('11111111-0000-4000-8000-000000000202', current_date, 'present');
end $fixture$;

-- =====================================================================
-- Persona: موظف (self) — يرتبط بهذه الصلاحيات بنطاق self فقط
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000201","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000201', true);
end $$;
set local role authenticated;

-- منع كتابة صفوف موظف آخر (كان مسموحاً قبل 0429 بحمل الصلاحية حتى بنطاق self)
select throws_ok(
  $$insert into public.attendance_daily (employee_id, work_date, status)
    values ('11111111-0000-4000-8000-000000000202', '2030-01-05', 'absent')$$,
  '42501', null, 'لا يستطيع الموظف كتابة حضور موظف آخر (attendance_daily)');
select throws_ok(
  $$insert into public.attendance_events (employee_id, event_type)
    values ('11111111-0000-4000-8000-000000000202', 'CHECK_IN')$$,
  '42501', null, 'لا يستطيع الموظف كتابة أحداث حضور موظف آخر (attendance_events)');
select throws_ok(
  $$insert into public.attendance_identity_checks (employee_id, method, passed)
    values ('11111111-0000-4000-8000-000000000202', 'manual', true)$$,
  '42501', null, 'لا يستطيع الموظف كتابة فحوص هوية موظف آخر (attendance_identity_checks)');
select throws_ok(
  $$insert into public.attendance_permits (employee_id, permit_date, kind, status)
    values ('11111111-0000-4000-8000-000000000202', '2030-01-05', 'arrival', 'pending')$$,
  '42501', null, 'لا يستطيع الموظف إدراج إذن حضور لموظف آخر (attendance_permits)');
select throws_ok(
  $$insert into public.attendance_exceptions (employee_id, work_date, kind, status)
    values ('11111111-0000-4000-8000-000000000202', '2030-01-05', 'late', 'open')$$,
  '42501', null, 'لا يستطيع الموظف إدراج استثناء حضور لموظف آخر (attendance_exceptions)');

-- ويبقى قادراً على التعامل مع سجله هو
select lives_ok(
  $$insert into public.attendance_daily (employee_id, work_date, status)
    values ('11111111-0000-4000-8000-000000000201', '2030-01-02', 'present')$$,
  'الموظف يستطيع كتابة حضوره هو (self)');
select lives_ok(
  $$insert into public.attendance_permits (employee_id, permit_date, kind, status)
    values ('11111111-0000-4000-8000-000000000201', '2030-01-02', 'arrival', 'pending')$$,
  'الموظف يستطيع إدراج إذن لنفسه (self)');

-- الكشف الشهري: ممنوع لموظف آخر، مسموح لذاته
select throws_ok(
  $$select public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000202', 2030, 1)$$,
  '42501', null, 'الموظف العادي ممنوع من كشف حضور موظف آخر');
select lives_ok(
  $$select public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000201', 2030, 1)$$,
  'الموظف يرى كشفه هو فقط');

-- القائمة التنفيذية: لا تُظهر سوى من له وصول فعلي (self)
select is(
  (select jsonb_array_length(public.get_mobile_executive_people(null, 100))),
  1,
  'القائمة التنفيذية للموظف العادي تُظهر سوى سجله هو');
select throws_ok(
  $$select public.get_mobile_executive_employee_summary('11111111-0000-4000-8000-000000000202')$$,
  '42501', null, 'الموظف العادي ممنوع من ملخص ملف موظف آخر');

-- الدليل العام: الحالة العامة فقط، لا تفاصيل
select is(
  (select x->>'statusToday' from jsonb_array_elements(public.get_mobile_employee_directory(null, 100)) x
   where x->>'id' = '11111111-0000-4000-8000-000000000202'),
  'present',
  'حالة الزميل الحاضر في الدليل = present');
-- 0444: المدير التنفيذي مستبعد من دليل الموظفين بالكامل
select ok(
  not exists (select 1 from jsonb_array_elements(public.get_mobile_employee_directory(null, 100)) x
    where x->>'id' = '11111111-0000-4000-8000-000000000205'),
  'المدير التنفيذي مستبعد من دليل الموظفين (0444)');
select ok(
  not exists (select 1 from jsonb_array_elements(public.get_mobile_employee_directory(null, 100)) x
    where x ? 'lateMinutes' or x ? 'workDate' or x ? 'leaveBalance'),
  'الدليل لا يسرّب أي تفاصيل حضور/أرصدة — الحالة العامة فقط');

-- المنح اليدوي ممنوع للموظف العادي
select throws_ok(
  $$select public.grant_weekly_rest_credit('11111111-0000-4000-8000-000000000201', '2030-01-03', 1)$$,
  '42501', null, 'المنح اليدوي لبدل الراحة ممنوع على الموظف العادي');

-- =====================================================================
-- Persona: المدير المباشر (direct_reports) — يرى مرؤوسه فقط
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000203","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000203', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000201', 2030, 1)$$,
  'المدير المباشر يرى كشف مرؤوسه');
select throws_ok(
  $$select public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000202', 2030, 1)$$,
  '42501', null, 'المدير المباشر ممنوع من كشف من ليس تحت إشرافه');
select lives_ok(
  $$select public.get_mobile_executive_employee_summary('11111111-0000-4000-8000-000000000201')$$,
  'المدير المباشر يرى ملخص مرؤوسه');
select throws_ok(
  $$select public.get_mobile_executive_employee_summary('11111111-0000-4000-8000-000000000202')$$,
  '42501', null, 'المدير المباشر ممنوع من ملخص من ليس تحت إشرافه');

-- =====================================================================
-- Persona: مدير الموارد البشرية (organization)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000204","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000204', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000202', 2030, 1)$$,
  'HR يرى كشف أي موظف');
select lives_ok(
  $$insert into public.attendance_daily (employee_id, work_date, status)
    values ('11111111-0000-4000-8000-000000000202', '2030-02-10', 'present')$$,
  'HR يستطيع كتابة حضور أي موظف');
select is(
  (select public.grant_weekly_rest_credit('11111111-0000-4000-8000-000000000201', '2030-01-03', 1)),
  1,
  'HR يستطيع منح بدل راحة يدوي لأي موظف (يوم واحد)');
select throws_ok(
  $$select public.grant_weekly_rest_credit('11111111-0000-4000-8000-000000000201', '2030-01-03', 366)$$,
  '22023', null, 'رفض عدد أيام خارج النطاق (366) حتى للمخوّل');

-- =====================================================================
-- Persona: المدير التنفيذي (organization)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"22222222-0000-4000-8000-000000000205","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '22222222-0000-4000-8000-000000000205', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.get_employee_monthly_attendance_statement('11111111-0000-4000-8000-000000000201', 2030, 1)$$,
  'التنفيذي يرى كشف أي موظف');

-- =====================================================================
-- Superuser: السجل/الترغير + التحقق من الرصيد (بدون RLS)
-- =====================================================================
reset role;

-- المنح اليدوي سُجّل في السجل بقيد مصدر فريد
select is(
  (select count(*)::int from public.leave_ledger_entries
   where source_key = 'weekly-rest:manual:11111111-0000-4000-8000-000000000201:2030-01-03'),
  1,
  'سجل المنح اليدوي يحتوي قيداً واحداً بقيد مصدر فريد');

-- ═══ المأمورية المعتمدة: لا غياب + بدل الجمعة (2030-03-15 جمعة) ═══
insert into public.requests (id, request_type, employee_id, manager_employee_id, status, workflow_status, title)
values ('33333333-0000-4000-8000-000000000201', 'mission',
        '11111111-0000-4000-8000-000000000201', '11111111-0000-4000-8000-000000000203',
        'pending', 'submitted', 'مأمورية اختبار');
insert into public.missions (request_id, employee_id, destination, purpose, start_at, end_at)
values ('33333333-0000-4000-8000-000000000201', '11111111-0000-4000-8000-000000000201',
        'القاهرة', 'عمل ميداني', '2030-03-14 08:00:00+02', '2030-03-15 20:00:00+02');
update public.requests set status = 'approved' where id = '33333333-0000-4000-8000-000000000201';

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000201' and work_date = '2030-03-14' and status = 'present'),
  1, 'يوم مأمورية (خميس) present — لا غياب');
select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000201' and work_date = '2030-03-15' and status = 'present'),
  1, 'يوم مأمورية (جمعة) present — لا غياب');
select is(
  (select count(*)::int from public.leave_ledger_entries
   where source_key = 'weekly-rest:credit:11111111-0000-4000-8000-000000000201:2030-03-15'),
  1, 'بدل راحة أسبوعي مُنح تلقائياً عن جمعة المأمورية');

-- ═══ القافلة المعتمدة: لا غياب + بدل الجمعة (2030-03-22 جمعة ضمن الفترة) ═══
insert into public.requests (id, request_type, employee_id, manager_employee_id, status, workflow_status, title)
values ('33333333-0000-4000-8000-000000000202', 'convoy',
        '11111111-0000-4000-8000-000000000201', '11111111-0000-4000-8000-000000000203',
        'pending', 'submitted', 'قافلة اختبار');
insert into public.convoy_requests (request_id, employee_id, convoy_name, origin, destination, departure_at, return_at)
values ('33333333-0000-4000-8000-000000000202', '11111111-0000-4000-8000-000000000201',
        'قافلة الخير', 'القاهرة', 'طنطا', '2030-03-21 06:00:00+02', '2030-03-23 20:00:00+02');
update public.requests set status = 'approved' where id = '33333333-0000-4000-8000-000000000202';

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000201' and work_date = '2030-03-21' and status = 'present'),
  1, 'يوم قافلة present — لا غياب');
select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000201' and work_date = '2030-03-23' and status = 'present'),
  1, 'يوم قافلة (نهاية) present — لا غياب');
select is(
  (select count(*)::int from public.leave_ledger_entries
   where source_key = 'weekly-rest:credit:11111111-0000-4000-8000-000000000201:2030-03-22'),
  1, 'بدل راحة أسبوعي مُنح تلقائياً عن جمعة القافلة');

-- ═══ تكليف العمل (work_assignments): المشارك أيام معتمدة + بدل الجمعة + التراجع ═══
insert into public.work_assignments (id, assignment_type, title, status, start_at, end_at, counts_as_work_day)
values ('44444444-0000-4000-8000-000000000201', 'MISSION', 'تكليف اختبار', 'APPROVED',
        '2030-04-18 08:00:00+02', '2030-04-19 18:00:00+02', true);
insert into public.work_assignment_participants (assignment_id, employee_id)
values ('44444444-0000-4000-8000-000000000201', '11111111-0000-4000-8000-000000000202');

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000202' and work_date = '2030-04-18' and status = 'present'),
  1, 'مشارك التكليف يوم (خميس) present — لا غياب');
select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000202' and work_date = '2030-04-19' and status = 'present'),
  1, 'مشارك التكليف يوم (جمعة) present — لا غياب');
select is(
  (select count(*)::int from public.leave_ledger_entries
   where source_key = 'weekly-rest:credit:11111111-0000-4000-8000-000000000202:2030-04-19'),
  1, 'بدل راحة أسبوعي مُنح تلقائياً عن جمعة التكليف');

update public.work_assignments set status = 'CANCELLED' where id = '44444444-0000-4000-8000-000000000201';
select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000202' and work_date = '2030-04-18' and status = 'absent'),
  1, 'تراجع التكليف يُرجع يوم الخميس إلى غياب (بلا بصمات)');
select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000202' and work_date = '2030-04-19' and status = 'absent'),
  1, 'تراجع التكليف يُرجع يوم الجمعة إلى غياب (بلا بصمات)');

-- ═══ الإجازة المعتمدة: on_leave (الخصم/الحجز مسار قائم — 0429 يضمن عدم الخصم للمأمورية/القافلة/التكليف) ═══
-- رصيد افتتاحي حتى ينجح حجز tg_leave_reserve_on_detail عند إدراج التفاصيل
select public.apply_leave_ledger_entry(
  '11111111-0000-4000-8000-000000000201',
  (select id from public.leave_types where code = 'annual'),
  2030, 'opening', 30,
  '0429-test:opening:annual:2030', null, 'رصيد افتتاحي للاختبار');
insert into public.requests (id, request_type, employee_id, manager_employee_id, status, workflow_status, title)
values ('33333333-0000-4000-8000-000000000203', 'leave',
        '11111111-0000-4000-8000-000000000201', '11111111-0000-4000-8000-000000000203',
        'pending', 'submitted', 'إجازة اختبار');
insert into public.leave_requests (request_id, employee_id, leave_type_id, start_date, end_date, days_count)
values ('33333333-0000-4000-8000-000000000203', '11111111-0000-4000-8000-000000000201',
        (select id from public.leave_types where code = 'annual'), '2030-05-06', '2030-05-08', 3);
update public.requests set status = 'approved' where id = '33333333-0000-4000-8000-000000000203';

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = '11111111-0000-4000-8000-000000000201'
     and work_date between '2030-05-06' and '2030-05-08' and status = 'on_leave'),
  3, 'أيام الإجازة المعتمدة كلها on_leave');

rollback;