-- =====================================================================
-- 0578: منع التعديل الذاتي على أيام الحضور + احتساب «حاضر» دون شرط 8 ساعات
-- ---------------------------------------------------------------------
-- التحقق:
--   1) محرّر الأيام canEditDays يستثني الذات
--   2) set_employee_attendance_day_admin يستثني الذات
--   3) clear_employee_attendance_day_admin يستثني الذات
--   4) decide_attendance_correction يمنع اعتماد الموظف على تصحيحه
--   5) شرط «أقل من 8 ساعات» أُسقط من حالة الحضور
--   6) لا mojibake في مصادر v287
--   7) service_role ما زال يملك EXECUTE على set/clear (مسار الأتمتة)
--   8) authenticated ما زال يملك EXECUTE على decide
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(8);

-- helper: نص دالة واحدة بالمعرّف الظاهر
create or replace function pg_temp.f_src(p_name text, p_args text)
returns text language sql as $$
  select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = p_name
    and pg_get_function_identity_arguments(p.oid) = p_args;
$$;

-- =====================================================================
-- 1) canEditDays يستثني الذات
-- =====================================================================
select ok(
  pg_temp.f_src('_build_attendance_statement_v287',
                'p_employee_id uuid, p_year integer, p_month integer')
    like '%p_employee_id is distinct from public.current_employee_id()%',
  '0578: canEditDays لا يمنح الموظف محرّر أيامه');

-- =====================================================================
-- 2) set_employee_attendance_day_admin يستثني الذات
-- =====================================================================
select ok(
  pg_temp.f_src('set_employee_attendance_day_admin',
                'p_employee_id uuid, p_work_date date, p_day_type text, p_check_in time without time zone, p_check_out time without time zone, p_clear_check_in boolean, p_clear_check_out boolean, p_reason text, p_notes text, p_leave_type text')
    like '%p_employee_id is distinct from public.current_employee_id()%',
  '0578: التعديل الإداري المباشر يستثني الذات');

-- =====================================================================
-- 3) clear_employee_attendance_day_admin يستثني الذات
-- =====================================================================
select ok(
  pg_temp.f_src('clear_employee_attendance_day_admin',
                'p_employee_id uuid, p_work_date date')
    like '%p_employee_id is distinct from public.current_employee_id()%',
  '0578: إلغاء التعديل الإداري يستثني الذات');

-- =====================================================================
-- 4) decide_attendance_correction يمنع الاعتماد الذاتي
-- =====================================================================
select ok(
  pg_temp.f_src('decide_attendance_correction',
                'p_id uuid, p_decision text, p_note text')
    like '%v_row.employee_id is distinct from public.current_employee_id()%',
  '0578: الموظف لا يعتمد تصحيح حضوره بنفسه');

-- =====================================================================
-- 5) شرط «أقل من الدوام» أُسقط من حالة الحضور
-- =====================================================================
select ok(
  pg_temp.f_src('_build_attendance_statement_v287',
                'p_employee_id uuid, p_year integer, p_month integer')
    not like '%v_work_minutes < v_required_minutes%',
  '0578: البصمتان الكاملتان تُحسبان حاضراً مهما كانت الساعات');

-- =====================================================================
-- 6) لا mojibake
-- =====================================================================
select is(
  pg_temp.f_src('_build_attendance_statement_v287',
                'p_employee_id uuid, p_year integer, p_month integer')
    ~ '(Ø|Ù|ðŸ|â€)',
  false,
  '0578: لا فساد UTF-8 في مصادر v287');

-- =====================================================================
-- 7) service_role يحتفظ بـ EXECUTE على set/clear
-- =====================================================================
select is(
  pg_catalog.has_function_privilege(
    'service_role',
    'public.set_employee_attendance_day_admin(uuid,date,text,time,time,boolean,boolean,text,text,text)',
    'EXECUTE'),
  true,
  '0578: service_role ينفذ التعديل الإداري');

-- =====================================================================
-- 8) authenticated يحتفظ بـ EXECUTE على decide
-- =====================================================================
select is(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.decide_attendance_correction(uuid,text,text)',
    'EXECUTE'),
  true,
  '0578: authenticated يمتلك EXECUTE على اعتماد التصحيح');

select * from finish();
rollback;
