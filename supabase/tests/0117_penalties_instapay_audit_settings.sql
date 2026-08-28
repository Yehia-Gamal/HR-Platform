-- 0117: الميزات المالية والأمنية الجديدة (0343 — F6/F7/F8).
-- يغطي:
--   * employee_penalties: إصدار مخالفة → قائمة → إسقاط (بصلاحية full-access).
--   * payroll_instapay_batches: توليد دفعة من دورة رواتب معتمدة + قائمة.
--   * get_audit_trail_page: قراءة سجل التدقيق مع فلاتر.
--   * get_editable_system_settings / update_system_settings: قراءة + تحديث.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(15);

do $fixture$
declare
  v_le   uuid := 'd2100000-0000-4000-8000-000000000011';
  v_dept uuid := 'd2100000-0000-4000-8000-000000000012';
  v_jt   uuid := 'd2100000-0000-4000-8000-000000000013';
  v_admin uuid := 'd2000000-0000-4000-8000-000000000011'; -- موظف admin
  v_emp  uuid := 'd2000000-0000-4000-8000-000000000012'; -- موظف يُخالف
  v_user_a uuid := 'd1900000-0000-4000-8000-000000000011';
  v_user_e uuid := 'd1900000-0000-4000-8000-000000000012';
  v_role uuid;
  v_run uuid;
begin
  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0117', 'كيان 0117');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0117', 'إدارة 0117');
  insert into public.job_titles(id, code, name)
    values (v_jt, 'JT-0117', 'وظيفة 0117');

  insert into auth.users(id, email, aud, role)
    values
    (v_user_a, 'admin-0117@test.local', 'authenticated', 'authenticated'),
    (v_user_e, 'emp-0117@test.local',  'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164)
    values
    (v_admin, v_user_a, 'E-0117-A', 'المسؤول 0117', v_dept, v_jt, 'active', true, current_date - 500, '+201000000011'),
    (v_emp,   v_user_e, 'E-0117-B', 'الموظف 0117',  v_dept, v_jt, 'active', true, current_date - 300, '+201000000012');

  insert into public.profiles(id, employee_id, status)
    values
    (v_user_a, v_admin, 'active'),
    (v_user_e, v_emp,   'active');

  -- دور admin بصلاحية كاملة للموظف المسؤول
  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin', 'أدمن', 'Admin', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin';
  insert into public.user_roles(user_id, role_id)
    values (v_user_a, v_role)
    on conflict do nothing;

  -- دورة رواتب معتمدة بصافي مستحق
  insert into public.payroll_runs(id, period_month, currency, status, totals, created_by)
    values (gen_random_uuid(), '2026-08-01', 'EGP', 'approved',
      jsonb_build_object('gross', 10000, 'net', 9000), auth.uid())
    returning id into v_run;

  insert into public.payslips(payroll_run_id, employee_id, gross_amount, deduction_amount, net_amount, status)
    values (v_run, v_emp, 10000, 1000, 9000, 'approved');

  perform set_config('app.t0117_employee', v_emp::text, false);
  perform set_config('app.t0117_admin', v_admin::text, false);
  perform set_config('app.t0117_run', v_run::text, false);
end $fixture$;

-- =====================================================================
-- جلسة المسؤول (full-access)
-- =====================================================================
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d1900000-0000-4000-8000-000000000011","role":"authenticated"}',
  true);
select set_config(
  'request.jwt.claim.sub',
  'd1900000-0000-4000-8000-000000000011',
  true);

-- 1) إصدار مخالفة
select lives_ok(
  $q$ select public.add_employee_penalty(
    nullif(current_setting('app.t0117_employee', true), '')::uuid,
    'late', 250, 'تأخير متكرر', null) $q$,
  'إصدار مخالفة مالية يُنفذ بنجاح');

select is(
  (select jsonb_array_length(public.get_employee_penalties(
     nullif(current_setting('app.t0117_employee', true), '')::uuid, null, null))),
  1,
  'قائمة المخالفات تعرض مخالفة واحدة للموظف');

select is(
  (select it->>'amount'
     from jsonb_array_elements(public.get_employee_penalties(
       nullif(current_setting('app.t0117_employee', true), '')::uuid, null, null)) it
     where it->>'employeeId' = nullif(current_setting('app.t0117_employee', true), '')::text),
  '250.00',
  'المخالفة تعرض المبلغ الصحيح');

-- 2) قائمة بفلتر الحالة
select is(
  (select jsonb_array_length(public.get_employee_penalties(null, 'issued', null))),
  1,
  'الفلترة حسب الحالة issued تعرض المخالفة');

select is(
  (select jsonb_array_length(public.get_employee_penalties(null, 'waived', null))),
  0,
  'الفلترة حسب الحالة waived لا تعرض شيئاً قبل الإسقاط');

-- 3) إسقاط المخالفة
select lives_ok(
  $q$ select public.waive_employee_penalty(
    (select id from public.employee_penalties limit 1), 'خطأ إداري') $q$,
  'إسقاط المخالفة يُنفذ بنجاح');

select is(
  (select status from public.employee_penalties limit 1),
  'waived',
  'حالة المخالفة تصبح waived بعد الإسقاط');

-- 4) توليد دفعة InstaPay من الدورة المعتمدة
select lives_ok(
  $q$ select public.generate_instapay_batch(
    nullif(current_setting('app.t0117_run', true), '')::uuid) $q$,
  'توليد دفعة InstaPay يُنفذ بنجاح');

select is(
  (select jsonb_array_length(public.list_instapay_batches(
     nullif(current_setting('app.t0117_run', true), '')::uuid))),
  1,
  'قائمة الدفعات تعرض دفعة واحدة لدورة الرواتب');

select is(
  (select it->>'itemCount'
     from jsonb_array_elements(public.list_instapay_batches(
       nullif(current_setting('app.t0117_run', true), '')::uuid)) it),
  '1',
  'الدفعة تحتوي عنصراً واحداً (قسيمة واحدة)');

-- 5) سجل التدقيق — سُجّل إصدار المخالفة وتوليد الدفعة
select ok(
  (select count(distinct it->>'eventType')
     from jsonb_array_elements(
       public.get_audit_trail_page(null, null, null, null, null, null, null, 20, 0) -> 'items') it
     where it->>'eventType' in ('penalty.issued', 'penalty.waived', 'instapay.batch_generated')) = 3,
  'سجل التدقيق يعرض أحداث إصدار وإسقاط المخالفة وتوليد الدفعة');

select ok(
  (select count(*) > 0
     from jsonb_array_elements(
       public.get_audit_trail_page(null, null, null, null, null, null, null, 50, 0) -> 'items') it
     where it->>'eventType' = 'penalty.issued'),
  'سجل التدقيق يعرض حدث إصدار المخالفة');

-- 6) إعدادات النظام — قراءة وتحديث
select ok(
  (select jsonb_array_length(public.get_editable_system_settings()) > 0),
  'هناك إعدادات نظام قابلة للتعديل');

select is(
  (select it->>'value'
     from jsonb_array_elements(public.get_editable_system_settings()) it
     where it->>'key' = 'leave_approval_escalation_hours'),
  '24',
  'قيمة مهلة التصعيد الافتراضية 24');

select public.update_system_settings(
  jsonb_build_object('leave_approval_escalation_hours', 48));

select is(
  (select it->>'value'
     from jsonb_array_elements(public.get_editable_system_settings()) it
     where it->>'key' = 'leave_approval_escalation_hours'),
  '48',
  'قيمة مهلة التصعيد أصبحت 48 بعد التحديث');

reset role;

select * from finish();
rollback;
