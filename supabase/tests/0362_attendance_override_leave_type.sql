-- 0362: حفظ نوع الإجازة في attendance_day_overrides وإرجاعه في كشف الشهر
-- (Migration 0362). يثبت أن:
--   (1) عمود leave_type موجود من نوع text مع قيد check بالقيم المدعومة.
--   (2) set_employee_attendance_day_admin يخزّن leave_type ويحدّثه.
--   (3) _build_attendance_statement يرجّع adminOverride.leaveType لكل يوم.
--   (4) أيام العمل leave_type = null، والنوع غير المدعوم يُرفض (22023).
--   (5) منطق backfill يملأ leave_type من طلب الإجازة المعتمد المغطي لليوم.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(15);

-- =====================================================================
-- Fixture: كيان + إدارة + موظف هدف + مشرف admin (full-access) + رصيد سنوي.
-- =====================================================================
do $fixture$
declare
  v_le      uuid := 'd3620000-0000-4000-8000-000000000001';
  v_dept    uuid := 'd3620000-0000-4000-8000-000000000002';
  v_emp     uuid := 'd3620000-0000-4000-8000-000000000010';
  v_admin   uuid := 'd3620000-0000-4000-8000-000000000011';
  v_user_a  uuid := 'd3620000-0000-4000-8000-000000000021';
  v_admin_role uuid;
  v_annual  uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0362', 'كيان 0362');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0362', 'إدارة 0362');

  insert into auth.users(id, email, aud, role) values
    (v_user_a, 'adm-0362@test.local', 'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, status, is_active, birth_date, hire_date) values
    (v_emp,   null,   'E-0362-A', 'هدف إجازة إدارية 0362', v_dept, 'active', true, '1990-01-01', '2020-01-01'),
    (v_admin, v_user_a, 'E-0362-B', 'مشرف التصحيح 0362',  v_dept, 'active', true, '1985-01-01', '2015-01-01');

  insert into public.profiles(id, employee_id, status) values
    (v_user_a, v_admin, 'active');

  select id into v_admin_role from public.roles where slug = 'admin';
  insert into public.user_roles(user_id, role_id) values (v_user_a, v_admin_role)
    on conflict (user_id, role_id) do nothing;

  -- المشرف مدير مباشر للهدف (معتمِد موثوق لطلب الإجازة).
  insert into public.manager_relations(employee_id, manager_employee_id, relation_type,
    effective_from, effective_to)
  values (v_emp, v_admin, 'primary', '2026-01-01', null);

  -- رصيد سنوي يتحمل خصم يوم واحد عند الاعتماد.
  select id into v_annual from public.leave_types where code = 'annual';
  perform public.ensure_leave_account(v_emp, v_annual, 2026);
  perform public.apply_leave_ledger_entry(
    v_emp, v_annual, 2026, 'opening', 10,
    'test:0362:open-annual', null, 'رصيد اختباري 0362');
end $fixture$;

-- =====================================================================
-- (1) العمود والقيد.
-- =====================================================================
select has_column('public','attendance_day_overrides','leave_type',
  'عمود leave_type موجود في attendance_day_overrides');

select col_type_is('public','attendance_day_overrides','leave_type','text',
  'نوع العمود leave_type هو text');

select lives_ok(
  $$ insert into public.attendance_day_overrides(
       employee_id, work_date, day_type, leave_type,
       reason, is_active, created_by)
     values ('d3620000-0000-4000-8000-000000000010', '2026-08-10', 'leave', 'sick',
       'إجازة مرضية مكتوبة مباشرة للاختبار', true, 'd3620000-0000-4000-8000-000000000021') $$,
  'القيد يقبل قيمة leave_type مدعومة (sick)');

select throws_ok(
  $$ insert into public.attendance_day_overrides(
       employee_id, work_date, day_type, leave_type,
       reason, is_active, created_by)
     values ('d3620000-0000-4000-8000-000000000010', '2026-08-11', 'leave', 'bogus',
       'نوع إجازة غير مدعوم مكتوب مباشرة', true, 'd3620000-0000-4000-8000-000000000021') $$,
  '23514', null,
  'القيد يرفض قيمة leave_type غير مدعومة (bogus → 23514)');

-- =====================================================================
-- (2) المسار الإداري: حفظ leave_type وتحديثه.
-- =====================================================================
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"d3620000-0000-4000-8000-000000000021","role":"authenticated"}', false);
select set_config('request.jwt.claim.sub',
  'd3620000-0000-4000-8000-000000000021', false);

select is(
  (public.set_employee_attendance_day_admin(
     'd3620000-0000-4000-8000-000000000010', '2026-08-03',
     'leave', null, null, false, false,
     'تعديل إداري لإجازة سنوية معتمدة', null, 'annual')->>'ok'),
  'true',
  'الترميز الإداري ليوم إجازة سنوية ينجح');

select is(
  (public.set_employee_attendance_day_admin(
     'd3620000-0000-4000-8000-000000000010', '2026-08-03',
     'leave', null, null, false, false,
     'تعديل إداري لإجازة سنوية معتمدة', null, 'annual')->>'leaveType'),
  'annual',
  'الاستجابة تعيد leaveType = annual');

reset role;
select is(
  (select leave_type from public.attendance_day_overrides
    where employee_id = 'd3620000-0000-4000-8000-000000000010'
      and work_date = '2026-08-03'),
  'annual',
  'leave_type مخزّن في صف الترميز (annual)');

select is(
  (select d->'adminOverride'->>'leaveType'
   from jsonb_array_elements(
     public._build_attendance_statement('d3620000-0000-4000-8000-000000000010', 2026, 8)->'days') d
   where d->>'date' = '2026-08-03'),
  'annual',
  'كشف الشهر يرجّع adminOverride.leaveType = annual لليوم المرموز');

-- تحديث نفس اليوم إلى casual → يُحدَّث leave_type وليس فقط day_type.
set local role authenticated;
select is(
  (public.set_employee_attendance_day_admin(
     'd3620000-0000-4000-8000-000000000010', '2026-08-03',
     'leave', null, null, false, false,
     'تعديل إداري يغير نوع الإجازة إلى عارضة', null, 'casual')->>'leaveType'),
  'casual',
  'إعادة الترميز لنفس اليوم تغيّر leaveType = casual');

reset role;
select is(
  (select d->'adminOverride'->>'leaveType'
   from jsonb_array_elements(
     public._build_attendance_statement('d3620000-0000-4000-8000-000000000010', 2026, 8)->'days') d
   where d->>'date' = '2026-08-03'),
  'casual',
  'الكشف بعد التحديث يرجّع adminOverride.leaveType = casual');

-- =====================================================================
-- (3) يوم عمل عادي: leave_type = null في العمود والكشف.
-- =====================================================================
set local role authenticated;
select is(
  (public.set_employee_attendance_day_admin(
     'd3620000-0000-4000-8000-000000000010', '2026-08-04',
     'work', null, null, true, true,
     'ترميز يوم عمل عادي بدون حضور', null, null)->>'ok'),
  'true',
  'الترميز الإداري ليوم عمل ينجح');

reset role;
select is(
  (select leave_type from public.attendance_day_overrides
    where employee_id = 'd3620000-0000-4000-8000-000000000010'
      and work_date = '2026-08-04'),
  null,
  'يوم عمل: leave_type = null في العمود');

select is(
  (select d->'adminOverride'->>'leaveType'
   from jsonb_array_elements(
     public._build_attendance_statement('d3620000-0000-4000-8000-000000000010', 2026, 8)->'days') d
   where d->>'date' = '2026-08-04'),
  null,
  'يوم عمل: adminOverride.leaveType = null في الكشف');

-- =====================================================================
-- (4) النوع غير المدعوم يُرفض قبل أي أثر.
-- =====================================================================
set local role authenticated;
select throws_ok($q$
  select public.set_employee_attendance_day_admin(
    'd3620000-0000-4000-8000-000000000010', '2026-08-05',
    'leave', null, null, false, false,
    'سبب اختباري كافٍ للرفض', null, 'bogus')
$q$, '22023', null, 'نوع إجازة غير مدعوم يُرفض (22023)');

-- =====================================================================
-- (5) منطق backfill: يملأ leave_type من طلب إجازة معتمد يغطي اليوم.
-- =====================================================================
reset role;
do $backfill$
declare
  v_req uuid;
  v_lt  uuid;
begin
  select id into v_lt from public.leave_types where code = 'sick';
  perform public.ensure_leave_account('d3620000-0000-4000-8000-000000000010', v_lt, 2026);
  perform public.apply_leave_ledger_entry(
    'd3620000-0000-4000-8000-000000000010', v_lt, 2026, 'opening', 10,
    'test:0362:open-sick', null, 'رصيد اختباري sick');
  insert into public.requests(request_type, employee_id, status, title, reason, payload)
    values ('leave', 'd3620000-0000-4000-8000-000000000010', 'approved',
            'إجازة مرضية معتمدة 0362', 'سبب اختباري معتمد', '{}'::jsonb)
    returning id into v_req;
  insert into public.leave_requests(request_id, employee_id, leave_type_id,
    start_date, end_date, days_count, duration_unit)
    values (v_req, 'd3620000-0000-4000-8000-000000000010', v_lt,
            '2026-08-12', '2026-08-12', 1, 'day');
  insert into public.attendance_day_overrides(
    employee_id, work_date, day_type, leave_type, reason, is_active, created_by)
    values ('d3620000-0000-4000-8000-000000000010', '2026-08-12', 'leave', null,
            'ترميز إجازة قبل backfill بدون نوع', true, null);
end $backfill$;

update public.attendance_day_overrides o
   set leave_type = lt.code
  from public.leave_requests lr
  join public.requests r on r.id = lr.request_id and r.status = 'approved'
  join public.leave_types lt on lt.id = lr.leave_type_id
 where o.leave_type is null
   and o.day_type in ('leave','absent')
   and lr.employee_id = o.employee_id
   and o.work_date between lr.start_date and lr.end_date;

select is(
  (select leave_type from public.attendance_day_overrides
    where employee_id = 'd3620000-0000-4000-8000-000000000010'
      and work_date = '2026-08-12'),
  'sick',
  'backfill يملأ leave_type = sick من طلب الإجازة المعتمد المغطي لليوم');

select * from finish();
rollback;
