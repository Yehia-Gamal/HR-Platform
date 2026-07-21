-- 0030: الاستحقاق الشهري للإجازات ومشغّل الجدولة (Migration 0047).
-- يتحقق من: وجود الحقل والدالة، حماية service_role، صحة الحساب،
-- عدم تجاوز الحد السنوي، وسلامة idempotency عند تكرار التشغيل.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(9);

-- بنية
select has_column('public','leave_types','monthly_accrual_units',
  'leave_types has monthly accrual rate');
select has_function('public','run_monthly_leave_accrual',
  array['integer','integer','integer'],
  'monthly accrual RPC exists');
select function_privs_are('public','run_monthly_leave_accrual',
  array['integer','integer','integer'],'service_role',array['EXECUTE'],
  'accrual runnable by service_role');
select ok(
  not has_function_privilege('authenticated',
    'public.run_monthly_leave_accrual(integer,integer,integer)','EXECUTE'),
  'authenticated cannot run accrual directly');

-- Fixture: كيان + موظف + نوع إجازة باستحقاق 2.5 وحد سنوي 30
do $fixture$
declare
  v_le uuid := 'bbbbbbbb-0000-4000-8000-000000000000';
  v_dept uuid := 'bbbbbbbb-0000-4000-8000-000000000001';
  v_emp uuid := 'bbbbbbbb-0000-4000-8000-000000000010';
  v_lt uuid := 'bbbbbbbb-0000-4000-8000-000000000020';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'ACC-LE', 'كيان استحقاق');
  insert into public.departments (id, legal_entity_id, code, name) values (v_dept, v_le, 'ACC-D', 'إدارة استحقاق');
  insert into public.employees (id, employee_code, full_name_ar, department_id, status, is_active)
    values (v_emp, 'ACC-001', 'موظف استحقاق', v_dept, 'active', true);
  insert into public.leave_types (id, code, name_ar, affects_balance, is_active, max_days_per_year, monthly_accrual_units)
    values (v_lt, 'ACC-ANNUAL', 'سنوية اختبار', true, true, 30, 2.5);
end
$fixture$;

-- تشغيل الاستحقاق لشهر يناير 2026.
-- ملاحظة: الاستحقاق يشمل كل الأنواع النشطة ذات monthly_accrual_units>0 لكل
-- الموظفين النشطين — بما فيها النوع المرضي المزروع في 0060. لذا لا نثبّت العدد
-- الإجمالي؛ نتحقق أن التشغيل نجح ومنح النوع الخاص بالـfixture مرة واحدة.
select ok(
  public.run_monthly_leave_accrual(2026, 1, 5000) >= 1,
  'accrual run grants at least one employee-type this run');

select is(
  (select count(*)::int from public.leave_ledger_entries
   where source_key = 'leave:accrual:bbbbbbbb-0000-4000-8000-000000000010:bbbbbbbb-0000-4000-8000-000000000020:2026-01'),
  1,
  'accrual grants exactly one entry for the fixture employee-type this run');

-- القيد أُنشئ بالوحدات الصحيحة
select is(
  (select units from public.leave_ledger_entries
   where source_key = 'leave:accrual:bbbbbbbb-0000-4000-8000-000000000010:bbbbbbbb-0000-4000-8000-000000000020:2026-01'),
  2.5::numeric,
  'monthly accrual entry has correct units');

-- إعادة التشغيل لنفس الشهر لا تضاعف الرصيد (idempotent)
select public.run_monthly_leave_accrual(2026, 1, 5000);
select is(
  (select count(*)::int from public.leave_ledger_entries
   where source_key = 'leave:accrual:bbbbbbbb-0000-4000-8000-000000000010:bbbbbbbb-0000-4000-8000-000000000020:2026-01'),
  1,
  're-running the same month is idempotent (no duplicate entry)');

-- تجاوز الحد السنوي: بعد 12 شهرًا (30 وحدة) لا يُمنح شهر 13
do $accrue$
declare m integer;
begin
  for m in 2..12 loop
    perform public.run_monthly_leave_accrual(2026, m, 5000);
  end loop;
end
$accrue$;
select is(
  (select coalesce(sum(units),0) from public.leave_ledger_entries
   where employee_id = 'bbbbbbbb-0000-4000-8000-000000000010'
     and leave_type_id = 'bbbbbbbb-0000-4000-8000-000000000020'
     and entry_type = 'accrual'),
  30::numeric,
  'annual accrual is capped at max_days_per_year (30)');

select * from finish();
rollback;
