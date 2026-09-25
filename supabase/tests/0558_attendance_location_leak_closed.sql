-- =====================================================================
-- 0558: مواقع الموظفين وحالات الحسابات لا تُقرأ مباشرة إلا عبر الدوال المحمية
-- ---------------------------------------------------------------------
-- يثبت أن العروض المادية (بلا RLS) والعرض الحساس غير قابلة للقراءة من
-- anon أو authenticated — التسريب الذي أغلقه 0558 — وأن الدوال المحمية
-- ما زالت متاحة للمصادَقين (تفرض هي التخويل).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(10);

select ok(not has_table_privilege('authenticated', 'public.mv_executive_attendance_snapshot', 'SELECT'),
  'authenticated لا يقرأ mv_executive_attendance_snapshot مباشرة (مواقع GPS)');
select ok(not has_table_privilege('anon', 'public.mv_executive_attendance_snapshot', 'SELECT'),
  'anon لا يقرأ mv_executive_attendance_snapshot');
select ok(not has_table_privilege('authenticated', 'public.mv_executive_attendance_overview', 'SELECT'),
  'authenticated لا يقرأ mv_executive_attendance_overview مباشرة');
select ok(not has_table_privilege('anon', 'public.mv_executive_attendance_overview', 'SELECT'),
  'anon لا يقرأ mv_executive_attendance_overview');
select ok(not has_table_privilege('authenticated', 'public.v_employee_status_audit', 'SELECT'),
  'authenticated لا يقرأ v_employee_status_audit');
select ok(not has_function_privilege('anon', 'public.get_public_daily_reports_feed(integer, date)', 'EXECUTE'),
  'anon لا ينفّذ get_public_daily_reports_feed');

-- الطريق المشروع باقٍ (التخويل داخل الدوال)
select ok(has_function_privilege('authenticated', 'public.get_executive_attendance_overview(date)', 'EXECUTE'),
  'get_executive_attendance_overview متاحة للمصادَقين (تفرض الصلاحية داخلياً)');
select ok(has_function_privilege('authenticated', 'public.get_public_daily_reports_feed(integer, date)', 'EXECUTE'),
  'get_public_daily_reports_feed متاحة للمصادَقين');
select ok(not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'mission_executions_employee_idx'),
  'الفهرس المكرر على mission_executions محذوف');
select ok(exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'ix_mission_executions_employee'),
  'الفهرس المتبقي على mission_executions(employee_id) موجود');

select * from finish();
rollback;
