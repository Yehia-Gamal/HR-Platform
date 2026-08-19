-- 0434: اختبار تصنيف يوم «فاندي» في الكشف الشهري (v287)
--       + يوم القافلة يبقى «قافلة» (لا يظهر «فاندي» ولا «إجازة»)
-- Personas: HR (organization). كل شيء يُرجع (rollback).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(7);

-- =====================================================================
-- Fixture: كيان + إدارة + موظف + HR + أنواع إجازات
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'dddd0000-0000-4000-8000-000000000401';
  v_a  uuid := 'dddd0000-0000-4000-8000-000000000402';
begin
  insert into public.legal_entities (id, code, name) values (v_le, '434-LE', 'كيان اختبار 0434');
  insert into public.departments (id, legal_entity_id, code, name) values
    (v_a, v_le, '434-D', 'إدارة 0434');

  insert into public.leave_types (code, name_ar, is_paid, is_active, affects_balance, max_days_per_year)
  values
    ('annual', 'إجازة سنوية', true, true, true, 30),
    ('weekly_rest_comp', 'بدل راحة أسبوعي', true, true, false, 100)
  on conflict (code) do nothing;

  insert into auth.users (id, email, aud, role) values
    ('dddd0000-0000-4000-8000-000000000403', '0434-hr@test.local', 'authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('dddd0000-0000-4000-8000-000000000410', null, 'T434-EMP', 'موظف اختبار 0434', v_a, 'active', true),
    ('dddd0000-0000-4000-8000-000000000404', 'dddd0000-0000-4000-8000-000000000403', 'T434-HR', 'موارد بشرية 0434', v_a, 'active', true);

  insert into public.profiles (id, employee_id, status)
  values ('dddd0000-0000-4000-8000-000000000403', 'dddd0000-0000-4000-8000-000000000404', 'active');

  insert into public.roles (slug, name_ar, is_system, is_full_access)
  values ('hr-manager', 'مدير موارد بشرية', true, false)
  on conflict (slug) do nothing;

  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('dddd0000-0000-4000-8000-000000000403'::uuid, 'hr-manager')
  ) as t(u, slug)
  join public.roles r on r.slug = t.slug;

  insert into public.permissions (code, module, resource, action) values
    ('attendance.record.read', 'attendance', 'record', 'read')
  on conflict (code) do nothing;

  insert into public.role_permissions (role_id, permission_id, scope)
  select r.id, p.id, 'organization'
  from public.roles r, public.permissions p
  where r.slug = 'hr-manager' and p.code = 'attendance.record.read'
  on conflict (role_id, permission_id, scope) do nothing;
end $fixture$;

-- =====================================================================
-- أيام معتمدة: فاندي (20/21/2026) + قافلة (22/23/2026) من payload
-- ملاحظة: لا نستخدم الجمعة لأن الكشف يعرض الجمعة «راحة أسبوعية» أولاً
--         (سلوك مقصود — منح رصيد بدل الراحة يحدث على أي حال عبر الـ ledger).
-- =====================================================================
insert into public.requests (id, request_type, employee_id, status, workflow_status, title, payload)
values ('dddd0000-0000-4000-8000-000000000420', 'fundraising',
        'dddd0000-0000-4000-8000-000000000410', 'pending', 'submitted', 'فاندي 0434',
        '{"startDate":"2026-07-20","endDate":"2026-07-21","location":"المنيا"}');
update public.requests set status = 'approved' where id = 'dddd0000-0000-4000-8000-000000000420';

insert into public.requests (id, request_type, employee_id, status, workflow_status, title, payload)
values ('dddd0000-0000-4000-8000-000000000421', 'convoy',
        'dddd0000-0000-4000-8000-000000000410', 'pending', 'submitted', 'قافلة 0434',
        '{"startDate":"2026-07-22","endDate":"2026-07-23","location":"الريف الأوروبي"}');
update public.requests set status = 'approved' where id = 'dddd0000-0000-4000-8000-000000000421';

select is(
  (select count(*)::int from public.attendance_daily
   where employee_id = 'dddd0000-0000-4000-8000-000000000410'
     and work_date in ('2026-07-20','2026-07-21','2026-07-22','2026-07-23') and status = 'present'),
  4, '1. الأيام الأربعة المعتمدة معلّمة present (حضور عمل — لا غياب ولا إجازة)');

-- =====================================================================
-- الكشف الشهري (persona HR): التصنيف الصحيح
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"dddd0000-0000-4000-8000-000000000403","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'dddd0000-0000-4000-8000-000000000403', true);
end $$;
set local role authenticated;

select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('dddd0000-0000-4000-8000-000000000410', 2026, 7))->'days') x
   where x->>'date' = '2026-07-20'),
  'فاندي', '2. الكشف: يوم فاندي payload يُعرض فاندي (لا قافلة)');

select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('dddd0000-0000-4000-8000-000000000410', 2026, 7))->'days') x
   where x->>'date' = '2026-07-21'),
  'فاندي', '3. الكشف: اليوم الثاني للفاندي يُعرض فاندي');

select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('dddd0000-0000-4000-8000-000000000410', 2026, 7))->'days') x
   where x->>'date' = '2026-07-22'),
  'قافلة', '4. الكشف: يوم قافلة payload يُعرض قافلة (لا فاندي)');

select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('dddd0000-0000-4000-8000-000000000410', 2026, 7))->'days') x
   where x->>'date' = '2026-07-23'),
  'قافلة', '5. الكشف: اليوم الثاني للقافلة يُعرض قافلة');

select is(
  ((public.get_employee_monthly_attendance_statement('dddd0000-0000-4000-8000-000000000410', 2026, 7))->'summary'->>'convoyFundiDays')::int,
  4, '6. الكشف: convoyFundiDays = 4 (قافلة 2 + فاندي 2)');

-- =====================================================================
-- 7) الجمعة تبقى راحة أسبوعية حتى لو لم يكن هناك طلب
-- =====================================================================
select is(
  (select x->>'status' from jsonb_array_elements(
     (public.get_employee_monthly_attendance_statement('dddd0000-0000-4000-8000-000000000410', 2026, 7))->'days') x
   where x->>'date' = '2026-07-31'),
  'راحة أسبوعية', '7. الكشف: الجمعة تبقى راحة أسبوعية (سلوك قائم)');

rollback;