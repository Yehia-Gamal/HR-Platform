-- 0228: secure password metadata, dispute directory, and materialized views.

BEGIN;

CREATE OR REPLACE FUNCTION public.clear_must_change_password()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'ERR_UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;

  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) - 'must_change_password'
  WHERE id = v_user_id;
END
$$;

REVOKE ALL ON FUNCTION public.clear_must_change_password() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.clear_must_change_password() FROM anon;
GRANT EXECUTE ON FUNCTION public.clear_must_change_password() TO authenticated;

-- Preserve the established jsonb contract used by the web client while adding
-- the missing server-side authorization check.
CREATE OR REPLACE FUNCTION public.get_dispute_participant_directory(
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_search text := NULLIF(trim(p_search), '');
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit, 100), 200));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'ERR_UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;

  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('relations.case.manage')
    OR public.has_permission('disputes.portal.access')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: صلاحية غير كافية للوصول لدليل المشاركين'
      USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', q.id,
          'name', q.full_name_ar,
          'employeeCode', q.employee_code,
          'department', q.department
        )
        ORDER BY q.full_name_ar
      ),
      '[]'::jsonb
    )
    FROM (
      SELECT e.id, e.full_name_ar, e.employee_code, d.name AS department
      FROM public.employees e
      LEFT JOIN public.departments d ON d.id = e.department_id
      WHERE e.status = 'active'
        AND e.is_active
        AND NOT e.is_deleted
        AND e.id IS DISTINCT FROM public.current_employee_id()
        AND (
          v_search IS NULL
          OR e.full_name_ar ILIKE '%' || public.escape_ilike(v_search) || '%'
          OR e.employee_code ILIKE '%' || public.escape_ilike(v_search) || '%'
        )
      ORDER BY e.full_name_ar
      LIMIT v_limit
    ) q
  );
END
$$;

REVOKE ALL ON FUNCTION public.get_dispute_participant_directory(text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_dispute_participant_directory(text, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_dispute_participant_directory(text, integer) TO authenticated;

-- Materialized views do not support RLS, so direct client access must be
-- removed and replaced with permission-checked RPCs.
DO $$
DECLARE
  v_view text;
BEGIN
  FOREACH v_view IN ARRAY ARRAY[
    'mv_daily_attendance_summary',
    'mv_department_headcount',
    'mv_monthly_request_stats'
  ]
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_matviews
      WHERE schemaname = 'public' AND matviewname = v_view
    ) THEN
      EXECUTE format(
        'REVOKE SELECT ON public.%I FROM PUBLIC, anon, authenticated',
        v_view
      );
    END IF;
  END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION public.read_daily_attendance_summary(
  p_from date DEFAULT CURRENT_DATE - 30,
  p_to date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'ERR_UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('attendance.record.read')
    OR public.has_permission('attendance.report.read')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.date DESC), '[]'::jsonb)
    FROM public.mv_daily_attendance_summary v
    WHERE v.date BETWEEN p_from AND p_to
  );
END
$$;

CREATE OR REPLACE FUNCTION public.read_department_headcount()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'ERR_UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('people.employee.read')
    OR public.has_permission('organization.structure.read')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.department_name), '[]'::jsonb)
    FROM public.mv_department_headcount v
  );
END
$$;

CREATE OR REPLACE FUNCTION public.read_monthly_request_stats(
  p_from date DEFAULT (date_trunc('month', CURRENT_DATE) - INTERVAL '5 months')::date,
  p_to date DEFAULT date_trunc('month', CURRENT_DATE)::date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'ERR_UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('requests.request.read')
    OR public.has_permission('reports.hr.read')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COALESCE(
      jsonb_agg(to_jsonb(v) ORDER BY v.month DESC, v.request_type),
      '[]'::jsonb
    )
    FROM public.mv_monthly_request_stats v
    WHERE v.month BETWEEN p_from AND p_to
  );
END
$$;

REVOKE ALL ON FUNCTION public.read_daily_attendance_summary(date, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.read_daily_attendance_summary(date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.read_daily_attendance_summary(date, date) TO authenticated;

REVOKE ALL ON FUNCTION public.read_department_headcount() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.read_department_headcount() FROM anon;
GRANT EXECUTE ON FUNCTION public.read_department_headcount() TO authenticated;

REVOKE ALL ON FUNCTION public.read_monthly_request_stats(date, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.read_monthly_request_stats(date, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.read_monthly_request_stats(date, date) TO authenticated;

COMMIT;
