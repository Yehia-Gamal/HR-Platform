-- 0237: إصلاح التكرار اللانهائي في سياسات RLS لجداول التكليفات
--
-- المشكلة (42P17 infinite recursion detected in policy for relation "work_assignments"):
--   سياسة work_assignments_select تستعلم عن work_assignment_participants،
--   وسياسة work_assignment_participants_select تستعلم عن work_assignments،
--   فينشأ تكرار متبادل بين السياستين يوقف أي استعلام SECURITY INVOKER
--   يلمس work_assignments (مثل get_attendance_today_overview في لوحة القيادة → 500).
--
-- الحل القياسي: نقل الاستعلام المتبادل داخل دوال SECURITY DEFINER تتجاوز RLS،
-- فيُكسر مسار التكرار مع الحفاظ على نفس منطق الصلاحيات تماماً.

BEGIN;

-- هل الموظف الحالي مشارك في تكليف معيّن؟ (يتجاوز RLS لكسر التكرار)
CREATE OR REPLACE FUNCTION public.is_assignment_participant(p_assignment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.work_assignment_participants p
    WHERE p.assignment_id = p_assignment_id
      AND (
        p.employee_id = public.current_employee_id()
        OR public.can_access_employee(p.employee_id)
      )
  );
$$;

REVOKE ALL ON FUNCTION public.is_assignment_participant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_assignment_participant(uuid) TO authenticated, service_role;

-- هل الموظف الحالي منشئ/مسؤول التكليف المرتبط بمشاركة؟ (يتجاوز RLS لكسر التكرار)
CREATE OR REPLACE FUNCTION public.owns_participant_assignment(p_assignment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.work_assignments a
    WHERE a.id = p_assignment_id
      AND (
        a.created_by_employee_id = public.current_employee_id()
        OR a.responsible_employee_id = public.current_employee_id()
      )
  );
$$;

REVOKE ALL ON FUNCTION public.owns_participant_assignment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owns_participant_assignment(uuid) TO authenticated, service_role;

-- إعادة كتابة سياسة القراءة على work_assignments دون استعلام مباشر عن الجدول الآخر
DROP POLICY IF EXISTS work_assignments_select ON public.work_assignments;
CREATE POLICY work_assignments_select ON public.work_assignments
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.has_any_permission(ARRAY[
        'assignments.mission.manage','assignments.convoy.manage',
        'assignments.fundraising.manage','operations.mission.manage','operations.convoy.manage'])
    OR created_by_employee_id = public.current_employee_id()
    OR responsible_employee_id = public.current_employee_id()
    OR public.is_assignment_participant(id)
  );

-- إعادة كتابة سياسة القراءة على work_assignment_participants دون استعلام مباشر عن الجدول الآخر
DROP POLICY IF EXISTS work_assignment_participants_select ON public.work_assignment_participants;
CREATE POLICY work_assignment_participants_select ON public.work_assignment_participants
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.has_any_permission(ARRAY[
        'assignments.mission.manage','assignments.convoy.manage','assignments.fundraising.manage'])
    OR employee_id = public.current_employee_id()
    OR public.can_access_employee(employee_id)
    OR public.owns_participant_assignment(assignment_id)
  );

COMMIT;
