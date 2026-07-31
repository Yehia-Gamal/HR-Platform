-- =====================================================================
-- 0084: RLS على الجداول المالية — التحقق من حماية بيانات التعويضات والرواتب
-- 22 assertion في 6 فئات
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(22);

-- =====================================================================
-- تعطيل trigger الإشعارات لتجنب أخطاء الـ fixture
-- =====================================================================
do $$ begin
  execute 'alter table public.user_roles disable trigger trg_role_assignment_notify';
exception when undefined_object then null;
end $$;

-- =====================================================================
-- Fixture (superuser — قبل أي تبديل دور)
-- =====================================================================
do $fixture$
declare
  v_le     uuid := 'f1f1f1f1-0000-4000-8000-000000000000';
  v_dept   uuid := 'f1f1f1f1-0000-4000-8000-000000000010';
  v_user_a uuid := 'f1f1f1f1-0000-4000-8000-000000000001';
  v_user_b uuid := 'f1f1f1f1-0000-4000-8000-000000000002';
  v_emp_a  uuid := 'f1f1f1f1-0000-4000-8000-000000000011';
  v_emp_b  uuid := 'f1f1f1f1-0000-4000-8000-000000000012';
  v_role_emp uuid;
  v_struct uuid := 'f1f1f1f1-0000-4000-8000-000000000020';
  v_payrun uuid := 'f1f1f1f1-0000-4000-8000-000000000030';
  v_slip_a uuid := 'f1f1f1f1-0000-4000-8000-000000000031';
  v_slip_b uuid := 'f1f1f1f1-0000-4000-8000-000000000032';
  v_loan_b uuid := 'f1f1f1f1-0000-4000-8000-000000000040';
begin
  -- كيان قانوني + إدارة
  insert into public.legal_entities (id, code, name)
  values (v_le, 'F1-LE', 'كيان اختبار مالي');

  insert into public.departments (id, legal_entity_id, code, name)
  values (v_dept, v_le, 'F1-D1', 'إدارة اختبار مالي');

  -- مستخدمو المصادقة
  insert into auth.users (id, email, aud, role) values
    (v_user_a, 'f1-emp-a@test.local', 'authenticated', 'authenticated'),
    (v_user_b, 'f1-emp-b@test.local', 'authenticated', 'authenticated');

  -- موظفون
  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    (v_emp_a, v_user_a, 'F1-001', 'موظف أ المالي', v_dept, 'active', true),
    (v_emp_b, v_user_b, 'F1-002', 'موظف ب المالي', v_dept, 'active', true);

  -- ملفات التعريف
  insert into public.profiles (id, employee_id, status) values
    (v_user_a, v_emp_a, 'active'),
    (v_user_b, v_emp_b, 'active');

  -- إسناد دور موظف
  select id into v_role_emp from public.roles where slug = 'employee';
  insert into public.user_roles (user_id, role_id) values
    (v_user_a, v_role_emp),
    (v_user_b, v_role_emp);

  -- === بيانات مالية ===

  -- هيكل رواتب
  insert into public.salary_structures (id, code, name_ar, currency, effective_from)
  values (v_struct, 'F1-STR-84', 'هيكل اختبار مالي', 'EGP', '2026-01-01');

  -- مكون راتب
  insert into public.salary_components (structure_id, code, name_ar, component_type)
  values (v_struct, 'F1-BASIC-84', 'راتب أساسي اختبار', 'earning');

  -- تعويض الموظف أ
  insert into public.employee_compensation (employee_id, structure_id, base_salary, effective_from, status)
  values (v_emp_a, v_struct, 5000.00, '2026-01-01', 'active');

  -- مسير رواتب
  insert into public.payroll_runs (id, period_month, status)
  values (v_payrun, '2026-05-01', 'approved');

  -- كشوف رواتب (واحد لكل موظف)
  insert into public.payslips (id, payroll_run_id, employee_id, gross_amount, deduction_amount, net_amount, status) values
    (v_slip_a, v_payrun, v_emp_a, 5000, 500, 4500, 'approved'),
    (v_slip_b, v_payrun, v_emp_b, 6000, 600, 5400, 'approved');

  -- بنود كشوف الرواتب
  insert into public.payslip_lines (payslip_id, component_code, component_name, line_type, amount) values
    (v_slip_a, 'BASIC', 'راتب أساسي', 'earning', 5000),
    (v_slip_b, 'BASIC', 'راتب أساسي', 'earning', 6000);

  -- قرض للموظف ب
  insert into public.employee_loans (id, employee_id, loan_type, principal_amount, installment_amount, outstanding_amount, start_month, status)
  values (v_loan_b, v_emp_b, 'advance', 3000, 500, 3000, '2026-07-01', 'approved');

  -- قسط القرض
  insert into public.loan_installments (loan_id, due_month, amount, status)
  values (v_loan_b, '2026-07-01', 500, 'scheduled');
end
$fixture$;

-- =====================================================================
-- الفئة 1: RLS مُفعّل على كل الجداول المالية (8 اختبارات)
-- =====================================================================

select row_eq(
  $$select relrowsecurity from pg_class where relname = 'salary_structures'$$,
  row(true),
  '1.1 RLS مُفعّل على salary_structures'
);

select row_eq(
  $$select relrowsecurity from pg_class where relname = 'salary_components'$$,
  row(true),
  '1.2 RLS مُفعّل على salary_components'
);

select row_eq(
  $$select relrowsecurity from pg_class where relname = 'employee_compensation'$$,
  row(true),
  '1.3 RLS مُفعّل على employee_compensation'
);

select row_eq(
  $$select relrowsecurity from pg_class where relname = 'payroll_runs'$$,
  row(true),
  '1.4 RLS مُفعّل على payroll_runs'
);

select row_eq(
  $$select relrowsecurity from pg_class where relname = 'payslips'$$,
  row(true),
  '1.5 RLS مُفعّل على payslips'
);

select row_eq(
  $$select relrowsecurity from pg_class where relname = 'payslip_lines'$$,
  row(true),
  '1.6 RLS مُفعّل على payslip_lines'
);

select row_eq(
  $$select relrowsecurity from pg_class where relname = 'employee_loans'$$,
  row(true),
  '1.7 RLS مُفعّل على employee_loans'
);

select row_eq(
  $$select relrowsecurity from pg_class where relname = 'loan_installments'$$,
  row(true),
  '1.8 RLS مُفعّل على loan_installments'
);

-- =====================================================================
-- الفئة 2: موظف عادي لا يقرأ الجداول المالية الإدارية (6 اختبارات)
-- =====================================================================

-- تبديل السياق إلى الموظف أ (دور employee فقط — بلا صلاحيات مالية)
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f1f1f1f1-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'f1f1f1f1-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select is(
  (select count(*)::int from public.salary_structures),
  0,
  '2.1 الموظف العادي لا يقرأ هياكل الرواتب'
);

select is(
  (select count(*)::int from public.salary_components),
  0,
  '2.2 الموظف العادي لا يقرأ مكونات الرواتب'
);

select is(
  (select count(*)::int from public.employee_compensation),
  0,
  '2.3 الموظف العادي لا يقرأ بيانات التعويضات'
);

select is(
  (select count(*)::int from public.payroll_runs),
  0,
  '2.4 الموظف العادي لا يقرأ مسيرات الرواتب'
);

select is(
  (select count(*)::int from public.employee_loans),
  0,
  '2.5 الموظف العادي لا يقرأ القروض'
);

select is(
  (select count(*)::int from public.loan_installments),
  0,
  '2.6 الموظف العادي لا يقرأ أقساط القروض'
);

-- =====================================================================
-- الفئة 3: الموظف يقرأ كشف راتبه فقط (2 اختبار)
-- =====================================================================

-- لا يزال السياق = الموظف أ
select is(
  (select count(*)::int from public.payslips),
  1,
  '3.1 الموظف يقرأ كشف راتبه الخاص فقط'
);

select is(
  (select count(*)::int from public.payslip_lines),
  1,
  '3.2 الموظف يقرأ بنود كشف راتبه الخاص فقط'
);

-- =====================================================================
-- الفئة 4: الكتابة المباشرة ممنوعة على الجداول المالية (3 اختبارات)
-- =====================================================================

-- لا يزال السياق = الموظف أ
select throws_ok(
  $$insert into public.employee_compensation (employee_id, structure_id, base_salary, effective_from)
    values ('f1f1f1f1-0000-4000-8000-000000000012', 'f1f1f1f1-0000-4000-8000-000000000020', 9999, '2026-07-01')$$,
  '42501', null,
  '4.1 الموظف لا يستطيع إدراج تعويض مباشرة'
);

select throws_ok(
  $$insert into public.payroll_runs (period_month) values ('2026-07-01')$$,
  '42501', null,
  '4.2 الموظف لا يستطيع إنشاء مسير رواتب مباشرة'
);

select throws_ok(
  $$insert into public.employee_loans (employee_id, loan_type, principal_amount, installment_amount, outstanding_amount, start_month)
    values ('f1f1f1f1-0000-4000-8000-000000000011', 'advance', 1000, 100, 1000, '2026-08-01')$$,
  '42501', null,
  '4.3 الموظف لا يستطيع إدراج قرض مباشرة'
);

-- =====================================================================
-- الفئة 5: مستخدم مجهول لا يقرأ البيانات المالية (2 اختبار)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
set local role anon;

select throws_ok(
  $$select count(*) from public.employee_compensation$$,
  '42501', null,
  '5.1 المستخدم المجهول لا يملك صلاحية مباشرة على بيانات التعويضات'
);

select throws_ok(
  $$select count(*) from public.payslips$$,
  '42501', null,
  '5.2 المستخدم المجهول لا يملك صلاحية مباشرة على كشوف الرواتب'
);

-- =====================================================================
-- الفئة 6: حماية RPCs المالية (1 اختبار)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f1f1f1f1-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'f1f1f1f1-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.get_people_finance_catalog()$$,
  'P0001', null,
  '6.1 الموظف العادي لا يستطيع استدعاء كتالوج البيانات المالية'
);

-- =====================================================================
reset role;
select * from finish();
rollback;
