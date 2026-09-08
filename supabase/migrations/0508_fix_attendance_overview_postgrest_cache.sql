-- 0508: Force PostgREST schema reload for get_attendance_today_overview
-- PostgREST has a stale prepared statement referencing non-existent column ae.event_date
-- The function body already uses ae.event_at but the cache is not invalidated.
-- This migration forces a full function rebuild to bust PostgREST's prepared statement cache.

CREATE OR REPLACE FUNCTION public.get_attendance_today_overview(p_date date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
DECLARE
  v_total_active int;
  v_expected int;
  v_present int;
  v_late int;
  v_on_leave int;
  v_on_assignment int;
  v_not_checked_in int;
  v_absent int;
  v_is_friday boolean := (extract(isodow from p_date) = 5);
BEGIN
  IF NOT (
    public.current_is_full_access()
    OR public.current_has_active_role(ARRAY['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
    OR public.has_permission('attendance.record.read')
    OR public.has_permission('people.employee.read')
    OR current_user IN ('postgres', 'service_role')
  ) THEN
    RAISE EXCEPTION 'غير مصرح لك' USING errcode = '42501';
  END IF;

  SELECT count(*) INTO v_total_active
  FROM public.employees e
  WHERE e.status = 'active'
    AND NOT EXISTS (
      SELECT 1 FROM public.user_roles ur
      JOIN public.roles r ON r.id = ur.role_id
      WHERE ur.user_id = e.user_id
        AND r.slug IN ('executive','executive-director')
        AND (ur.effective_from IS NULL OR ur.effective_from <= now())
        AND (ur.effective_to IS NULL OR ur.effective_to > now())
    );

  SELECT count(distinct lr.employee_id) INTO v_on_leave
  FROM public.leave_requests lr
  JOIN public.requests req ON req.id = lr.request_id
  WHERE req.status = 'approved'
    AND p_date BETWEEN lr.start_date AND lr.end_date;

  SELECT count(distinct wa.responsible_employee_id) INTO v_on_assignment
  FROM public.work_assignments wa
  WHERE wa.status IN ('APPROVED','IN_PROGRESS')
    AND p_date BETWEEN wa.start_at::date AND wa.end_at::date;

  SELECT count(distinct ae.employee_id) INTO v_present
  FROM public.attendance_events ae
  WHERE ae.event_at::date = p_date AND ae.event_type = 'CHECK_IN';

  SELECT count(distinct ae.employee_id) INTO v_late
  FROM public.attendance_events ae
  WHERE ae.event_at::date = p_date
    AND ae.event_type = 'CHECK_IN'
    AND coalesce(ae.late_minutes, 0) > 0;

  IF v_is_friday THEN
    v_expected := coalesce(v_on_assignment, 0);
  ELSE
    v_expected := greatest(0, coalesce(v_total_active, 0) - coalesce(v_on_leave, 0) - coalesce(v_on_assignment, 0));
  END IF;

  v_not_checked_in := greatest(0, coalesce(v_expected, 0) - coalesce(v_present, 0));
  v_absent := v_not_checked_in;

  RETURN jsonb_build_object(
    'date', p_date,
    'totalActive', coalesce(v_total_active, 0),
    'expected', coalesce(v_expected, 0),
    'expectedToday', coalesce(v_expected, 0),
    'present', coalesce(v_present, 0),
    'late', coalesce(v_late, 0),
    'onLeave', coalesce(v_on_leave, 0),
    'onAssignment', coalesce(v_on_assignment, 0),
    'notCheckedIn', coalesce(v_not_checked_in, 0),
    'absent', coalesce(v_absent, 0),
    'isFriday', v_is_friday,
    'isWeekend', v_is_friday,
    'lastUpdatedAt', now(),
    'generatedAt', now()
  );
END;
$func$;

COMMENT ON FUNCTION public.get_attendance_today_overview(date) IS '0508: force rebuild to bust PostgREST prepared statement cache';

REVOKE ALL ON FUNCTION public.get_attendance_today_overview(date) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_attendance_today_overview(date) TO authenticated;
