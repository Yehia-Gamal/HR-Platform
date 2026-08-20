-- =====================================================================
-- 0443: معالجة الملاحظات الأمنية والـ Database لتقرير الفحص الشامل
-- ---------------------------------------------------------------------
-- 1) تشديد سياسة RLS لـ learning_course_sessions:
--    إلغاء using(true) وحصر الوصول على المسجلين بالجلسة أو الإدارة.
-- 2) توحيد وتأكيد قيود CHECK لأنواع الطلبات السبعة:
--    (leave, mission, convoy, fundraising, late_permit, early_permit, attendance_correction)
-- 3) إضافة سياسة RLS صريحة لـ password_reset_requests لصالح service_role.
-- =====================================================================

begin;

-- ─── 1) تشديد RLS لجدول learning_course_sessions ───────────────────────

drop policy if exists learning_sessions_read on public.learning_course_sessions;

create policy learning_sessions_read on public.learning_course_sessions
  for select to authenticated using (
    exists (
      select 1 from public.learning_enrollments e
      where e.session_id = public.learning_course_sessions.id
        and e.employee_id = public.current_employee_id()
    )
    or public.current_is_full_access()
    or public.has_permission('learning.course.manage')
  );

-- ─── 2) تأكيد CHECK Constraints لجدول requests و workflow_definitions ──

alter table public.requests drop constraint if exists requests_request_type_check;
alter table public.requests
  add constraint requests_request_type_check
    check (request_type in (
      'leave',
      'mission',
      'convoy',
      'fundraising',
      'late_permit',
      'early_permit',
      'attendance_correction'
    ));

alter table public.workflow_definitions drop constraint if exists workflow_definitions_request_type_check;
alter table public.workflow_definitions
  add constraint workflow_definitions_request_type_check
    check (request_type in (
      'leave',
      'mission',
      'convoy',
      'fundraising',
      'late_permit',
      'early_permit',
      'attendance_correction',
      'attendance_permit',
      'generic'
    ));

-- ─── 3) إضافة سياسة RLS لـ password_reset_requests لصالح service_role ─

alter table public.password_reset_requests enable row level security;
alter table public.password_reset_requests force row level security;

drop policy if exists password_reset_requests_service on public.password_reset_requests;
create policy password_reset_requests_service on public.password_reset_requests
  for all to service_role using (true) with check (true);

commit;
