-- 0050: عقد كشف الحضور والانصراف الشهري (V12 §18, Migration 0127).
-- يتحقق من: وجود الدوال، الصلاحيات، صحة البنية، وسلوك البيانات.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- =====================================================================
-- بنية: الدوال موجودة بالتواقيع الصحيحة.
-- =====================================================================
select has_function('public','get_my_monthly_attendance_statement',
  array['integer','integer'],
  'RPC كشف الحضور الشخصي موجود');

select has_function('public','get_employee_monthly_attendance_statement',
  array['uuid','integer','integer'],
  'RPC كشف الحضور العام موجود');

select has_function('public','_build_attendance_statement',
  array['uuid','integer','integer'],
  'دالة بناء الكشف الداخلية موجودة');

-- =====================================================================
-- صلاحيات: الشخصي لـ authenticated، الداخلية محظورة.
-- =====================================================================
select function_privs_are('public','get_my_monthly_attendance_statement',
  array['integer','integer'],'authenticated',array['EXECUTE'],
  'كشف الحضور الشخصي متاح لـ authenticated');

select ok(
  not has_function_privilege('authenticated',
    'public._build_attendance_statement(uuid,integer,integer)','EXECUTE'),
  'الدالة الداخلية محظورة على authenticated');

-- =====================================================================
-- Fixture: كيان + موظف + حضور يومي + إجازة + تكليف عمل.
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'ff000000-0000-4000-8000-000000000000';
  v_dept uuid := 'ff000000-0000-4000-8000-000000000001';
  v_emp uuid := 'ff000000-0000-4000-8000-000000000010';
  v_lt uuid;
begin
  insert into public.legal_entities(id,code,name) values(v_le,'ATT-LE','كيان كشف');
  insert into public.departments(id,legal_entity_id,code,name) values(v_dept,v_le,'ATT-D','إدارة كشف');
  insert into public.employees(id,employee_code,full_name_ar,department_id,status,is_active,birth_date,hire_date)
    values(v_emp,'ATT-001','موظف كشف الحضور',v_dept,'active',true,'1990-01-01','2020-01-01');

  -- حضور ليوم عمل عادي (2026-07-01 أربعاء)
  insert into public.attendance_daily(employee_id,work_date,status,first_check_in,last_check_out,work_minutes,late_minutes)
    values(v_emp,'2026-07-01','present','2026-07-01 10:05:00+02','2026-07-01 18:10:00+02',485,5);

  -- يوم غياب (2026-07-02 خميس)
  insert into public.attendance_daily(employee_id,work_date,status,work_minutes)
    values(v_emp,'2026-07-02','absent',0);

  -- إجازة معتمدة (2026-07-06 أحد) — نضبطها on_leave
  insert into public.attendance_daily(employee_id,work_date,status)
    values(v_emp,'2026-07-06','on_leave');

  -- تكليف عمل (قافلة 2026-07-07 اثنين)
  insert into public.work_assignments(id,assignment_type,title,status,start_at,end_at,is_full_day,counts_as_work_day,created_by_employee_id)
    values('ff000000-0000-4000-8000-000000000099','CONVOY','قافلة طبية','APPROVED','2026-07-07 08:00:00+02','2026-07-07 18:00:00+02',true,true,v_emp);
  insert into public.work_assignment_participants(assignment_id,employee_id)
    values('ff000000-0000-4000-8000-000000000099',v_emp);
end $fixture$;

-- =====================================================================
-- تشغيل الكشف والتحقق من البنية والبيانات.
-- =====================================================================
-- الكشف يُرجع jsonb صالح
select ok(
  public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 7) is not null,
  'الكشف يُرجع بيانات (ليس null)');

-- البنية: يحتوي employee + period + days + summary
select ok(
  (public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 7) ? 'employee')
  and (public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 7) ? 'period')
  and (public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 7) ? 'days')
  and (public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 7) ? 'summary'),
  'الكشف يحتوي الأقسام الأربعة (employee/period/days/summary)');

-- عدد الأيام = 31 (يوليو)
select is(
  (public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 7)->'summary'->>'totalDays')::int,
  31, 'يوليو = 31 يومًا');

-- اسم الموظف
select is(
  public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 7)->'employee'->>'fullNameAr',
  'موظف كشف الحضور', 'اسم الموظف في الكشف');

-- يوم الحضور ظهر كـ "حاضر" أو "متأخر"
select ok(
  (select (d->>'status') in ('حاضر','متأخر')
   from jsonb_array_elements(
     public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-01'),
  'يوم 2026-07-01 يظهر كحاضر أو متأخر');

-- يوم القافلة ظهر كتكليف
select ok(
  (select (d->>'status') like '%قافلة%'
   from jsonb_array_elements(
     public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 7)->'days'
   ) d where d->>'date' = '2026-07-07'),
  'يوم 2026-07-07 يظهر كقافلة (تكليف عمل)');

-- شهر غير صالح يُرفض
select throws_ok(
  $$ select public._build_attendance_statement('ff000000-0000-4000-8000-000000000010', 2026, 13) $$,
  null, null,
  'شهر 13 يُرفض');

select * from finish();
rollback;
