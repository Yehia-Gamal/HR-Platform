-- 0657: ملف الموظف وكشفه الشهري — المتابعة لمن فوقه، والتعديل للموارد البشرية فقط
-- Personas: زميل إدارة بنطاق department / مدير مباشر / موظف عادي / أخصائي موارد بشرية.
-- كل شيء يُرجع (rollback).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(22);

-- =====================================================================
-- Pre-fixture: أدوار وصلاحيات مكتفية ذاتياً
-- =====================================================================
do $ensure$
declare
  v_pair record;
begin
  insert into public.roles (slug, name_ar, is_system, is_full_access)
  values
    ('employee',        'موظف',              true,  false),
    ('direct-manager',  'مدير مباشر',        true,  false),
    ('hr-specialist',   'أخصائي موارد بشرية', true,  false),
    ('acc-dept-reader', 'قارئ إدارة (اختبار)', false, false)
  on conflict (slug) do nothing;

  insert into public.permissions (code, module, resource, action) values
    ('people.employee.read',         'people',     'employee',   'read'),
    ('attendance.record.read',       'attendance', 'record',     'read'),
    ('attendance.correction.review', 'attendance', 'correction', 'review'),
    ('attendance.day.override',      'attendance', 'day',        'override')
  on conflict (code) do nothing;

  for v_pair in
    select * from (values
      ('employee',        'self',           'people.employee.read'),
      ('employee',        'self',           'attendance.record.read'),
      ('direct-manager',  'direct_reports', 'people.employee.read'),
      ('direct-manager',  'direct_reports', 'attendance.record.read'),
      ('direct-manager',  'direct_reports', 'attendance.correction.review'),
      ('hr-specialist',   'organization',   'people.employee.read'),
      ('hr-specialist',   'organization',   'attendance.record.read'),
      ('hr-specialist',   'organization',   'attendance.day.override'),
      ('acc-dept-reader', 'department',     'people.employee.read'),
      ('acc-dept-reader', 'department',     'attendance.record.read'),
      ('acc-dept-reader', 'department',     'attendance.correction.review')
    ) as t(slug, scope, code)
  loop
    insert into public.role_permissions (role_id, permission_id, scope)
    select r.id, p.id, v_pair.scope
      from public.roles r, public.permissions p
     where r.slug = v_pair.slug and p.code = v_pair.code
    on conflict (role_id, permission_id, scope) do nothing;
  end loop;
end $ensure$;

-- =====================================================================
-- Fixture: إدارتان، مدير ومرؤوسه في (أ)، زميلان في (ب) بلا رئيس، وموارد بشرية
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'acce5500-0000-4000-8000-000000000001';
  v_a  uuid := 'acce5500-0000-4000-8000-000000000002';
  v_b  uuid := 'acce5500-0000-4000-8000-000000000003';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'ACC-LE', 'كيان اختبار الوصول');
  insert into public.departments (id, legal_entity_id, code, name) values
    (v_a, v_le, 'ACC-A', 'إدارة أ'),
    (v_b, v_le, 'ACC-B', 'إدارة ب');

  insert into auth.users (id, email, aud, role) values
    ('acce5500-0000-4000-8000-000000000101', 'acc-mgr@test.local',    'authenticated', 'authenticated'),
    ('acce5500-0000-4000-8000-000000000102', 'acc-report@test.local', 'authenticated', 'authenticated'),
    ('acce5500-0000-4000-8000-000000000103', 'acc-peer@test.local',   'authenticated', 'authenticated'),
    ('acce5500-0000-4000-8000-000000000104', 'acc-target@test.local', 'authenticated', 'authenticated'),
    ('acce5500-0000-4000-8000-000000000105', 'acc-hr@test.local',     'authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('acce5500-0000-4000-8000-000000000201', 'acce5500-0000-4000-8000-000000000101', 'ACC-001', 'مدير مباشر',   v_a, 'active', true),
    ('acce5500-0000-4000-8000-000000000202', 'acce5500-0000-4000-8000-000000000102', 'ACC-002', 'مرؤوس',        v_a, 'active', true),
    ('acce5500-0000-4000-8000-000000000203', 'acce5500-0000-4000-8000-000000000103', 'ACC-003', 'زميل بنطاق إدارة', v_b, 'active', true),
    ('acce5500-0000-4000-8000-000000000204', 'acce5500-0000-4000-8000-000000000104', 'ACC-004', 'زميل مستهدف', v_b, 'active', true),
    ('acce5500-0000-4000-8000-000000000205', 'acce5500-0000-4000-8000-000000000105', 'ACC-005', 'موارد بشرية',  v_b, 'active', true);

  insert into public.profiles (id, employee_id, status)
  select u, e, 'active' from (values
    ('acce5500-0000-4000-8000-000000000101'::uuid, 'acce5500-0000-4000-8000-000000000201'::uuid),
    ('acce5500-0000-4000-8000-000000000102'::uuid, 'acce5500-0000-4000-8000-000000000202'::uuid),
    ('acce5500-0000-4000-8000-000000000103'::uuid, 'acce5500-0000-4000-8000-000000000203'::uuid),
    ('acce5500-0000-4000-8000-000000000104'::uuid, 'acce5500-0000-4000-8000-000000000204'::uuid),
    ('acce5500-0000-4000-8000-000000000105'::uuid, 'acce5500-0000-4000-8000-000000000205'::uuid)
  ) as t(u, e)
  on conflict (id) do update set employee_id = excluded.employee_id, status = excluded.status;

  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('acce5500-0000-4000-8000-000000000101'::uuid, 'employee'),
    ('acce5500-0000-4000-8000-000000000101'::uuid, 'direct-manager'),
    ('acce5500-0000-4000-8000-000000000102'::uuid, 'employee'),
    ('acce5500-0000-4000-8000-000000000103'::uuid, 'employee'),
    ('acce5500-0000-4000-8000-000000000103'::uuid, 'acc-dept-reader'),
    ('acce5500-0000-4000-8000-000000000104'::uuid, 'employee'),
    ('acce5500-0000-4000-8000-000000000105'::uuid, 'hr-specialist')
  ) as t(u, slug)
  join public.roles r on r.slug = t.slug;

  insert into public.manager_relations (employee_id, manager_employee_id, relation_type)
  values ('acce5500-0000-4000-8000-000000000202', 'acce5500-0000-4000-8000-000000000201', 'primary');
end $fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- =====================================================================
-- (1) زميل الإدارة بنطاق department: لا ملف كامل ولا كشف لزميله
-- =====================================================================
select pg_temp.act_as('acce5500-0000-4000-8000-000000000103');
set local role authenticated;
select throws_ok(
  $$select public.get_employee_monthly_attendance_statement('acce5500-0000-4000-8000-000000000204',
      extract(year from now())::int, extract(month from now())::int)$$,
  '42501', null, 'زميل الإدارة لا يفتح الكشف الشهري لزميله');
select is(
  public.get_employee_360('acce5500-0000-4000-8000-000000000204')->>'viewerScope', 'basic',
  'زميل الإدارة يرى الملف الأساسي فقط');
select ok(
  not (public.get_employee_360('acce5500-0000-4000-8000-000000000204') ? 'email'),
  'الملف الأساسي بلا بيانات اتصال');
reset role;

-- رئيس الإدارة نفسها يرى موظفي إدارته (ولا يعدّل)
update public.departments set manager_id = 'acce5500-0000-4000-8000-000000000203'
 where id = 'acce5500-0000-4000-8000-000000000003';
select pg_temp.act_as('acce5500-0000-4000-8000-000000000103');
set local role authenticated;
select lives_ok(
  $$select public.get_employee_monthly_attendance_statement('acce5500-0000-4000-8000-000000000204',
      extract(year from now())::int, extract(month from now())::int)$$,
  'رئيس الإدارة يرى كشف موظف إدارته');
select is(
  public.get_employee_monthly_attendance_statement('acce5500-0000-4000-8000-000000000204',
    extract(year from now())::int, extract(month from now())::int)->'capabilities'->>'canEditDays',
  'false', 'رئيس الإدارة لا يعدّل أيام موظف إدارته');
reset role;

-- =====================================================================
-- (2) المدير المباشر: يتابع كشف مرؤوسه ولا يعدّله
-- =====================================================================
select pg_temp.act_as('acce5500-0000-4000-8000-000000000101');
set local role authenticated;
select lives_ok(
  $$select public.get_employee_monthly_attendance_statement('acce5500-0000-4000-8000-000000000202',
      extract(year from now())::int, extract(month from now())::int)$$,
  'المدير المباشر يرى كشف مرؤوسه');
select is(
  public.get_employee_monthly_attendance_statement('acce5500-0000-4000-8000-000000000202',
    extract(year from now())::int, extract(month from now())::int)->'capabilities'->>'canEditDays',
  'false', 'المدير المباشر بلا محرّر أيام لمرؤوسه');
select is(
  public.get_employee_360('acce5500-0000-4000-8000-000000000202')->>'viewerScope', 'full',
  'المدير المباشر يرى الملف الكامل لمرؤوسه');
select throws_ok(
  $$select public.set_employee_attendance_day_admin('acce5500-0000-4000-8000-000000000202',
      (now() at time zone 'Africa/Cairo')::date - 1, 'leave', null, null, true, true, 'اختبار الصلاحية', null, 'annual')$$,
  '42501', null, 'المدير المباشر لا يسجّل لمرؤوسه إجازة إدارياً');
select throws_ok(
  $$select public.clear_employee_attendance_day_admin('acce5500-0000-4000-8000-000000000202',
      (now() at time zone 'Africa/Cairo')::date - 1)$$,
  '42501', null, 'المدير المباشر لا يلغي تعديلاً إدارياً');
select throws_ok(
  $$select public.submit_employee_day_mark('acce5500-0000-4000-8000-000000000202', 'leave',
      'تحديد يوم', 'اختبار الصلاحية',
      jsonb_build_object('startDate', (now() at time zone 'Africa/Cairo')::date,
                         'endDate', (now() at time zone 'Africa/Cairo')::date, 'leaveType', 'casual'))$$,
  '42501', null, 'المدير المباشر لا يحدد يوماً لمرؤوسه');
select throws_ok(
  $$select public.get_employee_monthly_attendance_statement('acce5500-0000-4000-8000-000000000204',
      extract(year from now())::int, extract(month from now())::int)$$,
  '42501', null, 'المدير المباشر لا يرى كشف من ليس تحته');
reset role;

-- =====================================================================
-- (3) الموظف العادي: لا تحديد ذاتي لأيامه، ولا موجز الإدارة
-- =====================================================================
select pg_temp.act_as('acce5500-0000-4000-8000-000000000102');
set local role authenticated;
select throws_ok(
  $$select public.submit_employee_day_mark('acce5500-0000-4000-8000-000000000202', 'leave',
      'تحديد يوم', 'اختبار الصلاحية',
      jsonb_build_object('startDate', (now() at time zone 'Africa/Cairo')::date,
                         'endDate', (now() at time zone 'Africa/Cairo')::date, 'leaveType', 'unpaid'))$$,
  '42501', null, 'الموظف لا يحدد ليومه إجازة بدون راتب متجاوزاً التقديم الذاتي');
select throws_ok(
  $$select public.generate_executive_daily_digest(null)$$,
  '42501', null, 'الموظف لا يقرأ موجز الإدارة');
reset role;

-- =====================================================================
-- (4) الموارد البشرية (attendance.day.override): تعدّل أيام غيرها
-- =====================================================================
select pg_temp.act_as('acce5500-0000-4000-8000-000000000105');
set local role authenticated;
select is(
  public.get_employee_monthly_attendance_statement('acce5500-0000-4000-8000-000000000202',
    extract(year from now())::int, extract(month from now())::int)->'capabilities'->>'canEditDays',
  'true', 'الموارد البشرية لها محرّر الأيام');
select lives_ok(
  $$select public.set_employee_attendance_day_admin('acce5500-0000-4000-8000-000000000202',
      (now() at time zone 'Africa/Cairo')::date - 1, 'work', '09:00', '17:00', false, false, 'اختبار الصلاحية', null, null)$$,
  'الموارد البشرية تعدّل يوم موظف');
select lives_ok(
  $$select public.clear_employee_attendance_day_admin('acce5500-0000-4000-8000-000000000202',
      (now() at time zone 'Africa/Cairo')::date - 1)$$,
  'الموارد البشرية تلغي التعديل الإداري');
reset role;

-- =====================================================================
-- (5) دوال بلا فحص هوية: لا ينفذها الموظفون
-- =====================================================================
select ok(not has_function_privilege('authenticated',
  'public.apply_leave_ledger_entry(uuid,uuid,integer,text,numeric,text,uuid,text,jsonb)', 'execute'),
  'الموظف لا يضيف لنفسه رصيد إجازات (apply_leave_ledger_entry)');
select ok(not has_function_privilege('authenticated',
  'public.admin_activate_employee_after_password_set(uuid)', 'execute'),
  'الموظف لا يعيد تفعيل حساب موقوف');
select ok(not has_function_privilege('authenticated', 'public.auto_notify_late_attendance()', 'execute')
      and not has_function_privilege('authenticated', 'public.backfill_request_managers()', 'execute'),
  'الكرون والصيانة ليست للموظفين');
select ok(has_function_privilege('service_role',
  'public.admin_activate_employee_after_password_set(uuid)', 'execute'),
  'service_role (Edge Function admin-set-password) يفعّل الحساب');
select ok(
  (select prosrc from pg_proc where oid = 'public.get_penalty_disputes(text)'::regprocedure)
    like '%d.employee_id = public.current_employee_id()%',
  'الموظف يرى طعون غراماته فقط');

select * from finish();
rollback;
