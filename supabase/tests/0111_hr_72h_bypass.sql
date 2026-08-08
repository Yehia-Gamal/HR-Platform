-- 0111: تجاوز HR بعد 72 ساعة من انتهاء مهلة المدير (0317) — ميزة F1.
-- السيناريو: طلب في الخطوة الأولى (المدير المباشر) تجاوزت مهلته 72 ساعة،
-- فيأخذ HR-manager (بصلاحية requests.approve organization من 0317) القرار
-- تجاوزياً فيُغلق الطلب ويعتمد الخطوة الثانية تلقائياً.
-- كما يتحقق الاختبار من منع التجاوز قبل مرور 72 ساعة.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(10);

do $fixture$
declare
  v_le    uuid := 'd1500000-0000-4000-8000-000000000001';
  v_dept  uuid := 'd1500000-0000-4000-8000-000000000002';
  v_shift uuid := 'd1500000-0000-4000-8000-000000000003';
  v_emp   uuid := 'd1400000-0000-4000-8000-000000000001'; -- مقدم الطلب
  v_mgr   uuid := 'd1400000-0000-4000-8000-000000000002'; -- المدير المباشر (الخطوة 1)
  v_hr    uuid := 'd1400000-0000-4000-8000-000000000003'; -- HR-manager (يتجاوز)
  v_user_e uuid := 'd1300000-0000-4000-8000-000000000001';
  v_user_m uuid := 'd1300000-0000-4000-8000-000000000002';
  v_user_h uuid := 'd1300000-0000-4000-8000-000000000003';
  v_wf    uuid;
  v_req_a uuid; -- طلب تجاوزت مهلته 72 ساعة
  v_req_b uuid; -- طلب لم تتجاوز مهلته
  v_step2_a uuid;
  v_step2_b uuid;
  v_hr_role uuid;
begin
  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0111', 'كيان 0111');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0111', 'إدارة 0111');
  insert into public.shifts(id, code, name, start_time, end_time,
    crosses_midnight, break_minutes, grace_in_minutes, grace_out_minutes, is_active)
    values (v_shift, 'S-0111', 'وردية 0111', '09:00', '17:00', false, 0, 0, 0, true);

  insert into auth.users(id, email, aud, role)
    values
    (v_user_e, 'emp-0111@test.local', 'authenticated', 'authenticated'),
    (v_user_m, 'mgr-0111@test.local', 'authenticated', 'authenticated'),
    (v_user_h, 'hr-0111@test.local',  'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, status, is_active, hire_date)
    values
    (v_emp,  v_user_e, 'E-0111-A', 'موظف 0111',  v_dept, 'active', true, current_date - 400),
    (v_mgr,  v_user_m, 'E-0111-B', 'مدير 0111',  v_dept, 'active', true, current_date - 800),
    (v_hr,   v_user_h, 'E-0111-C', 'HR مدير 0111', v_dept, 'active', true, current_date - 900);

  insert into public.profiles(id, employee_id, status)
    values
    (v_user_e, v_emp, 'active'),
    (v_user_m, v_mgr, 'active'),
    (v_user_h, v_hr,  'active');

  -- علاقة إدارية: المدير يرأس مقدم الطلب
  insert into public.manager_relations(manager_employee_id, employee_id, relation_type)
    values (v_mgr, v_emp, 'primary');

  -- دور HR للمستخدم + الصلاحية (مُدرجة في 0317 — نضمنها للاختبار)
  select id into v_hr_role from public.roles where slug = 'hr-manager';
  insert into public.user_roles(user_id, role_id)
    values (v_user_h, v_hr_role)
    on conflict (user_id, role_id) do nothing;

  -- سير عمل من خطوتين: المدير المباشر → HR-manager
  insert into public.workflow_definitions(code, name_ar, request_type,
    version, is_active, is_default, auto_escalate, default_due_hours)
    values ('WF-0111', 'سير 0111', 'leave',
           1, true, false, true, 48)
    returning id into v_wf;

  insert into public.workflow_steps(definition_id, step_order, name_ar,
    approver_type, approver_permission, sla_hours, is_active)
    values (v_wf, 1, 'مراجعة المدير المباشر', 'direct_manager', null, 48, true);
  insert into public.workflow_steps(definition_id, step_order, name_ar,
    approver_type, approver_role_slug, approver_permission, sla_hours, is_active)
    values (v_wf, 2, 'اعتماد HR', 'role', 'hr-manager', 'requests.approve', 48, true);

  -- ── طلب أ: تجاوزت مهلة المدير 72 ساعة (due_at قبل 4 أيام) ──
  insert into public.requests(request_type, employee_id, manager_employee_id,
    workflow_definition_id, status, workflow_status, current_step_order, title, payload)
    values ('leave', v_emp, v_mgr, v_wf, 'pending', 'in_review', 1,
            'إجازة تجاوزت 72 ساعة',
            jsonb_build_object('leaveType','casual','startDate',current_date,'endDate',current_date))
    returning id into v_req_a;

  insert into public.request_steps(request_id, step_order, name_ar,
    assignee_employee_id, status, sla_hours, due_at)
    values (v_req_a, 1, 'مراجعة المدير المباشر', v_mgr, 'active', 48, now() - interval '4 days');
  insert into public.request_steps(request_id, step_order, name_ar,
    assignee_role_slug, status, sla_hours, due_at)
    values (v_req_a, 2, 'اعتماد HR', 'hr-manager', 'pending', 48, null)
    returning id into v_step2_a;

  insert into public.workflow_instances(definition_id, request_id, definition_version,
    status, current_step_order)
    values (v_wf, v_req_a, 1, 'running', 1);

  -- ── طلب ب: لم تتجاوز مهلة المدير (due_at بعد 48 ساعة) ──
  insert into public.requests(request_type, employee_id, manager_employee_id,
    workflow_definition_id, status, workflow_status, current_step_order, title, payload)
    values ('leave', v_emp, v_mgr, v_wf, 'pending', 'in_review', 1,
            'إجازة لم تتجاوز 72 ساعة',
            jsonb_build_object('leaveType','casual','startDate',current_date,'endDate',current_date))
    returning id into v_req_b;

  insert into public.request_steps(request_id, step_order, name_ar,
    assignee_employee_id, status, sla_hours, due_at)
    values (v_req_b, 1, 'مراجعة المدير المباشر', v_mgr, 'active', 48, now() + interval '2 days');
  insert into public.request_steps(request_id, step_order, name_ar,
    assignee_role_slug, status, sla_hours, due_at)
    values (v_req_b, 2, 'اعتماد HR', 'hr-manager', 'pending', 48, null)
    returning id into v_step2_b;

  insert into public.workflow_instances(definition_id, request_id, definition_version,
    status, current_step_order)
    values (v_wf, v_req_b, 1, 'running', 1);

  perform set_config('app.t0111_req_a', v_req_a::text, false);
  perform set_config('app.t0111_req_b', v_req_b::text, false);
  perform set_config('app.t0111_step2_a', v_step2_a::text, false);
  perform set_config('app.t0111_step2_b', v_step2_b::text, false);
end $fixture$;

-- =====================================================================
-- جلسة HR-manager: يتخذ القرار
-- =====================================================================
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d1300000-0000-4000-8000-000000000003","role":"authenticated"}',
  true);
select set_config(
  'request.jwt.claim.sub',
  'd1300000-0000-4000-8000-000000000003',
  true);

-- 1) HR غير full-access يملك صلاحية requests.approve بنطاق organization
select ok(
  public.can_access_employee(
    'd1400000-0000-4000-8000-000000000001', 'requests.approve'),
  'HR-manager يملك صلاحية requests.approve بنطاق organization (غير full-access)');

-- 2) تجاوز طلب تجاوزت مهلته 72 ساعة → موافقة
select lives_ok(
  $q$ select public.decide_request(
    nullif(current_setting('app.t0111_req_a', true), '')::uuid,
    'approve', 'تجاوز مدير') $q$,
  'HR يعتمد طلباً تجاوزت مهلة المدير 72 ساعة (تجاوز ناجح)');

select is(
  (select status from public.requests
    where id = nullif(current_setting('app.t0111_req_a', true), '')::uuid),
  'approved',
  'الطلب المتجاوز أصبح approved');

-- 3) الخطوة الثانية اعتُمدت تلقائياً (v_bypass_hr)
select is(
  (select status from public.request_steps
    where id = nullif(current_setting('app.t0111_step2_a', true), '')::uuid),
  'approved',
  'الخطوة الثانية اعتُمدت تلقائياً ضمن التجاوز');

-- 4) تسجيل إجراء التجاوز في سجل الإجراءات
select ok(
  exists (
    select 1 from public.request_actions
    where request_id = nullif(current_setting('app.t0111_req_a', true), '')::uuid
      and comment like '%تجاوز%'),
  'إجراء التجاوز مسجّل في request_actions بوصف «اعتماد تجاوزي»');

-- 5) طلب لم تتجاوز مهلته → رفض (لا تجاوز قبل 72 ساعة)
select throws_ok(
  $q$ select public.decide_request(
    nullif(current_setting('app.t0111_req_b', true), '')::uuid,
    'approve', 'محاولة مبكرة') $q$,
  '42501',
  null,
  'HR لا يستطيع تجاوز قبل مرور 72 ساعة على مهلة المدير');

-- 6) الطلب (ب) بقي معلقاً
select is(
  (select status from public.requests
    where id = nullif(current_setting('app.t0111_req_b', true), '')::uuid),
  'pending',
  'الطلب الذي لم تتجاوز مهلته يبقى pending بعد رفض المحاولة');

-- 7) الموافقة التجاوزية غيّرت حالة سير العمل إلى completed
select is(
  (select workflow_status from public.requests
    where id = nullif(current_setting('app.t0111_req_a', true), '')::uuid),
  'completed',
  'سير العمل اكتمل بعد التجاوز');

-- 8) إشعار مقدم الطلب صدر بموافقة — يُفحص بعد reset role لأن RLS
--    notifications تسمح فقط للمُستلم أو full-access.

reset role;

select ok(
  exists (
    select 1 from public.notifications n
    where n.recipient_employee_id = 'd1400000-0000-4000-8000-000000000001'
      and n.category = 'request'),
  'إشعار موافقة صدر لمقدم الطلب');

-- 9) مدير الخطوة الأولى (المدير المباشر) لم يعتمد — لم يُسجَّل له أي إجراء
select ok(
  not exists (
    select 1 from public.request_actions
    where request_id = nullif(current_setting('app.t0111_req_a', true), '')::uuid
      and actor_employee_id = 'd1400000-0000-4000-8000-000000000002'),
  'لا يوجد إجراء منسوب للمدير المباشر على الطلب المتجاوز');

select * from finish();
rollback;
