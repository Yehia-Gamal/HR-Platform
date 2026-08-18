-- 0354: عقد إصلاحات الغياب المعلّق وسلسلة الاعتماد (Migration 0354).
-- يغطي: توسيع أنواع سير العمل، عدم فرض سير عمل افتراضي بمراجعة HR للتشغيل،
-- المعتمِد البديل (fallback) عند غياب المدير المباشر، عرض «بانتظار الاعتماد»
-- في كشف الشهر، وتفعيل إعفاء الفاندي بعد الاعتماد.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- =====================================================================
-- Fixture: كيان + إدارة + موظف بلا مدير + HR-manager نشط + طلبات معلقة.
-- =====================================================================
do $fixture$
declare
  v_le      uuid := 'd3500000-0000-4000-8000-000000000001';
  v_dept    uuid := 'd3500000-0000-4000-8000-000000000002';
  v_emp     uuid := 'd3500000-0000-4000-8000-000000000010';
  v_hr      uuid := 'd3500000-0000-4000-8000-000000000011';
  v_user_e  uuid := 'd3500000-0000-4000-8000-000000000021';
  v_user_h  uuid := 'd3500000-0000-4000-8000-000000000022';
  v_hr_role uuid;
  v_lt      uuid;
  v_req1    uuid;
  v_req3    uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0353', 'كيان 0353');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0353', 'إدارة 0353');

  insert into auth.users(id, email, aud, role) values
    (v_user_e, 'emp-0353@test.local', 'authenticated', 'authenticated'),
    (v_user_h, 'hr-0353@test.local',  'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, status, is_active, birth_date, hire_date) values
    (v_emp, v_user_e, 'E-0353-A', 'موظف طلبات معلقة', v_dept, 'active', true, '1990-01-01', '2020-01-01'),
    (v_hr,  v_user_h, 'E-0353-B', 'HR موظف 0353',    v_dept, 'active', true, '1985-01-01', '2015-01-01');

  insert into public.profiles(id, employee_id, status) values
    (v_user_e, v_emp, 'active'),
    (v_user_h, v_hr,  'active');

  select id into v_hr_role from public.roles where slug = 'hr-manager';
  insert into public.user_roles(user_id, role_id) values (v_user_h, v_hr_role)
    on conflict (user_id, role_id) do nothing;

  -- إجازة معلقة: 2026-07-02 (خميس)
  insert into public.requests(request_type, employee_id, status, title, payload)
    values ('leave', v_emp, 'pending', 'إجازة معلقة 0353', '{}'::jsonb)
    returning id into v_req1;
  select id into v_lt from public.leave_types where code = 'casual';
  insert into public.leave_requests(request_id, employee_id, leave_type_id,
    start_date, end_date, days_count)
    values (v_req1, v_emp, v_lt, '2026-07-02', '2026-07-02', 1);

  -- مأمورية معلقة: 2026-07-06 (اثنين)
  insert into public.requests(request_type, employee_id, status, title, payload)
    values ('mission', v_emp, 'pending', 'مأمورية معلقة 0353',
            jsonb_build_object('startDate','2026-07-06','endDate','2026-07-06'));

  -- فاندي سيُعتمد في نهاية الاختبار: 2026-07-13 (اثنين)
  insert into public.requests(request_type, employee_id, status, title, payload)
    values ('fundraising', v_emp, 'pending', 'فاندي 0353',
            jsonb_build_object('startDate','2026-07-13','endDate','2026-07-13'))
    returning id into v_req3;

  perform set_config('app.t0353_req3', v_req3::text, false);
end $fixture$;

-- جلسة الموظف (لعمليات auth.uid في الدوال)
select set_config('request.jwt.claims',
  '{"sub":"d3500000-0000-4000-8000-000000000021","role":"authenticated"}', false);
select set_config('request.jwt.claim.sub',
  'd3500000-0000-4000-8000-000000000021', false);

-- =====================================================================
-- (1) أنواع سير العمل الموسّعة: يقبل fundraising ويرفض الأنواع الغريبة.
-- =====================================================================
select lives_ok(
  $$ insert into public.workflow_definitions(code, name_ar, request_type,
       version, is_active, is_default)
     values ('WF-FUNDI-T', 'سير فاندي اختباري', 'fundraising', 1, true, false) $$,
  'CHECK سير العمل يقبل نوع fundraising');

select throws_ok(
  $$ insert into public.workflow_definitions(code, name_ar, request_type,
       version, is_active, is_default)
     values ('WF-BOGUS', 'سير باطل', 'bogus', 1, true, false) $$,
  '23514', null,
  'CHECK سير العمل يرفض نوعًا غير معروف');

-- =====================================================================
-- (2) التشغيل يُعتمد بخطوة واحدة من المدير المباشر أو البديل — بلا
--     مراجعة HR إلزامية تبقيه معلّقًا. (0366/0367 أضافت مسارًا ثلاثيًا
--     بخطوة HR اختيارية؛ الشرط هنا: لا خطوة HR إلزامية في سير التشغيل).
-- =====================================================================
select is(
  (select count(*)::int
     from public.workflow_steps ws
     join public.workflow_definitions wd on wd.id = ws.definition_id
    where wd.request_type in ('mission','convoy','fundraising')
      and wd.is_default and wd.is_active
      and ws.approver_role_slug in ('hr-manager','hr-specialist')
      and not coalesce(ws.is_optional, false)),
  0,
  'لا خطوة HR إلزامية في سير التشغيل (مأمورية/قافلة/فاندي)');

-- =====================================================================
-- (3) المعتمِد البديل: موظف بلا مدير → HR-manager صاحب requests.approve.
-- =====================================================================
select is(
  public.resolve_request_approver(
    'd3500000-0000-4000-8000-000000000010'::uuid, '2026-07-01'::date),
  'd3500000-0000-4000-8000-000000000011'::uuid,
  'موظف بلا مدير مباشر → معتمِد بديل (HR-manager)');

select ok(
  public.resolve_request_approver(
    'd3500000-0000-4000-8000-000000000011'::uuid, '2026-07-01'::date) is null,
  'لا تُرجع الدالة الموظف نفسه معتمِدًا بديلاً');

-- =====================================================================
-- (4) كشف الشهر: الطلبات المعلّقة تُغيّي الغياب وتُعرض «بانتظار الاعتماد».
-- =====================================================================
select ok(
  (select (d->>'status') = 'بانتظار اعتماد إجازة'
     and (d->>'hasPendingLeave')::boolean
     and not (d->>'isAbsent')::boolean
   from jsonb_array_elements(
     public._build_attendance_statement('d3500000-0000-4000-8000-000000000010', 2026, 7)->'days') d
   where d->>'date' = '2026-07-02'),
  'يوم إجازة معلقة يظهر «بانتظار اعتماد إجازة» وليس غيابًا');

select ok(
  (select (d->>'status') = 'بانتظار اعتماد مأمورية'
     and (d->>'hasPendingMission')::boolean
   from jsonb_array_elements(
     public._build_attendance_statement('d3500000-0000-4000-8000-000000000010', 2026, 7)->'days') d
   where d->>'date' = '2026-07-06'),
  'يوم مأمورية معلقة يظهر «بانتظار اعتماد مأمورية»');

select is(
  (public._build_attendance_statement('d3500000-0000-4000-8000-000000000010', 2026, 7)
    ->'summary'->>'pendingDays')::int,
  3,
  'summary.pendingDays = 3 (إجازة + مأمورية + فاندي معلقون)');

select ok(
  (select (d->>'isAbsent')::boolean and (d->>'status') = 'غائب دون إذن'
   from jsonb_array_elements(
     public._build_attendance_statement('d3500000-0000-4000-8000-000000000010', 2026, 7)->'days') d
   where d->>'date' = '2026-07-08'),
  'يوم بلا طلب يبقى غيابًا (السلوك الأصلي محفوظ)');

-- =====================================================================
-- (5) اعتماد طلب فاندي يُنشئ حضورًا في attendance_daily (تريغر 0317+).
-- =====================================================================
select lives_ok(
  $q$ update public.requests
      set status = 'approved'
      where id = nullif(current_setting('app.t0353_req3', true), '')::uuid $q$,
  'اعتماد طلب الفاندي لا يفشل');

select ok(
  exists(
    select 1 from public.attendance_daily
    where employee_id = 'd3500000-0000-4000-8000-000000000010'
      and work_date = '2026-07-13' and status = 'on_leave'),
  'اعتماد الفاندي يعلّم يوم 07-13 on_leave (لا غياب — 0429)');

-- =====================================================================
-- (6) دالة مدخلات KPI ما زالت بالتواقيع الصحيحة.
-- =====================================================================
select has_function('public','refresh_kpi_attendance_inputs',array['uuid'],
  'refresh_kpi_attendance_inputs(uuid) موجودة');

select * from finish();
rollback;
