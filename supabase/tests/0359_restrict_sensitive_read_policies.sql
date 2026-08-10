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
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = e.tablename
      and cmd = 'SELECT'
      and qual = 'true'
  ),
  format('%s: لا توجد سياسة قراءة بـ using(true)', e.tablename)
)
from existing_sensitive e;

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = e.tablename
      and cmd = 'SELECT'
      and qual is not null
      and qual <> 'true'
  ),
  format('%s: توجد سياسة قراءة مقيدة', e.tablename)
)
from existing_sensitive e;

-- =====================================================================
-- فحص وظيفي: جدول reference (branches) لا يزال يسمح بـ using(true)
-- =====================================================================
select ok(
  (select count(*)::integer from pg_policies
   where schemaname='public' and tablename='branches' and cmd='SELECT'
     and qual = 'true') >= 1,
  'branches (جدول مرجعي) يحتفظ بسياسة using(true)'
);

rollback;
