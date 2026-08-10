-- =====================================================================
-- 0359: تقييد سياسات القراءة الواسعة على الجداول الحساسة
-- يؤكد: لا توجد سياسة SELECT بشرط using(true) على الجداول الحساسة،
-- وأن سياسة قراءة مقيدة موجودة.
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

-- قائمة الجداول الحساسة التي يجب ألا يكون لها قراءة باستخدام true
create temp table sensitive_tables (tablename text);
insert into sensitive_tables (tablename) values
  ('salary_components'), ('salary_structures'),
  ('payroll_instapay_batches'), ('payroll_instapay_items'),
  ('employee_penalties'),
  ('audit_findings'), ('internal_audits'), ('ai_use_cases'),
  ('automation_rules'), ('automation_runs'), ('corrective_actions'),
  ('data_assets'), ('data_quality_rules'), ('notification_jobs'),
  ('quality_cases'), ('service_catalog_items'), ('service_request_messages'),
  ('dispute_conflict_declarations'), ('dispute_session_attendance'),
  ('enterprise_incidents'), ('enterprise_meetings'), ('enterprise_projects'),
  ('enterprise_risks'), ('strategic_objectives'), ('objective_key_results'),
  ('meeting_agenda_items'), ('meeting_attendees'), ('meeting_decisions'),
  ('offboarding_clearance_items'), ('document_signature_requests'),
  ('project_tasks'), ('wellbeing_requests');

-- فقط الجداول الموجودة فعلاً
create temp table existing_sensitive as
select s.tablename
from sensitive_tables s
where to_regclass(format('public.%I', s.tablename)) is not null;

-- خطة ديناميكية: 2 تأكيد لكل جدول موجود + 1 (branches)
select plan(
  (select count(*)::int from existing_sensitive) * 2 + 1
);

-- لكل جدول:
--  1) لا توجد سياسة SELECT بشرط using(true)
--  2) توجد سياسة قراءة مقيدة (non-true quals)
do $$
declare
  v_t text;
  v_no_open integer;
  v_has_restricted integer;
  v_rel oid;
begin
  for v_t in select tablename from existing_sensitive loop
    select to_regclass(format('public.%I', v_t)) into v_rel;

    select count(*) into v_no_open
    from pg_policies
    where schemaname = 'public'
      and tablename = v_t
      and cmd = 'SELECT'
      and quals is not null
      and pg_get_expr(quals, v_rel) like '%true%';

    select count(*) into v_has_restricted
    from pg_policies
    where schemaname = 'public'
      and tablename = v_t
      and cmd = 'SELECT'
      and quals is not null
      and pg_get_expr(quals, v_rel) not like '%true%';

    perform ok(v_no_open = 0,
      format('%s: لا توجد سياسة قراءة بـ using(true)', v_t));
    perform ok(v_has_restricted >= 1,
      format('%s: توجد سياسة قراءة مقيدة', v_t));
  end loop;
end $$;

-- =====================================================================
-- فحص وظيفي: جدول reference (branches) لا يزال يسمح بـ using(true)
-- =====================================================================
select is(
  (select count(*)::integer from pg_policies
   where schemaname='public' and tablename='branches' and cmd='SELECT'
     and quals is not null
     and pg_get_expr(quals, 'public.branches'::regclass) like '%true%'),
  1, 'branches (جدول مرجعي) يحتفظ بسياسة using(true)'
);

rollback;
