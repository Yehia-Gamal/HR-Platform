-- Migration 0079: Reapply Fixes for Attendance Functions
-- Resolves PGRST203 and e.legal_entity_id

-- 1. Reload PostgREST schema cache securely
NOTIFY pgrst, 'reload schema';

-- 2. Clean up ALL old variations of record_attendance_event
DROP FUNCTION IF EXISTS public.record_attendance_event(
  uuid, text, double precision, double precision, numeric, text, text, uuid, boolean
);
DROP FUNCTION IF EXISTS public.record_attendance_event(
  uuid, text, double precision, double precision, numeric, text, text, uuid, boolean, boolean
);
DROP FUNCTION IF EXISTS public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean
);
DROP FUNCTION IF EXISTS public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean
);

-- 3. Recreate record_attendance_event properly
CREATE OR REPLACE FUNCTION public.record_attendance_event(
  p_employee_id       uuid,
  p_event_type        text,
  p_latitude          double precision,
  p_longitude         double precision,
  p_accuracy_meters   double precision,
  p_biometric_method  text    DEFAULT 'passkey',
  p_selfie_path       text    DEFAULT NULL,
  p_passkey_credential_id uuid DEFAULT NULL,
  p_verified          boolean DEFAULT false,
  p_is_mock           boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_event_type NOT IN ('CHECK_IN', 'CHECK_OUT') THEN
    RAISE EXCEPTION 'invalid event type' USING errcode = '22023';
  END IF;

  INSERT INTO public.attendance_events (
    employee_id, event_type, latitude, longitude, accuracy_meters,
    biometric_method, selfie_path, passkey_credential_id, verified,
    is_mock, recorded_at, created_by
  ) VALUES (
    p_employee_id, p_event_type, p_latitude, p_longitude, p_accuracy_meters,
    p_biometric_method, p_selfie_path, p_passkey_credential_id, p_verified,
    p_is_mock, now(), auth.uid()
  ) RETURNING id INTO v_id;

  PERFORM public.log_audit_event(
    'attendance.' || lower(p_event_type),
    'security',
    'info',
    'attendance_events',
    v_id,
    'تسجيل حضور/انصراف من خلال الواجهة الخلفية',
    NULL,
    jsonb_build_object('method', p_biometric_method, 'verified', p_verified)
  );

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.record_attendance_event IS
  'RPC: Recording attendance events strictly for Edge Function calls.';

REVOKE ALL ON FUNCTION public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean
) TO service_role;


-- 4. Recreate get_my_attendance_services properly fixing e.legal_entity_id
DROP FUNCTION IF EXISTS public.get_my_attendance_services(date, date);

CREATE OR REPLACE FUNCTION public.get_my_attendance_services(
  p_from date default current_date - 31,
  p_to date default current_date + 45
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
  v_emp uuid := public.current_employee_id();
BEGIN
  IF v_emp IS NULL THEN RAISE EXCEPTION 'NO_EMPLOYEE'; END IF;
  IF p_to < p_from OR p_to-p_from > 370 THEN RAISE EXCEPTION 'INVALID_RANGE'; END IF;

  RETURN jsonb_build_object(
    'schedule', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id',d.id,
        'workDate',d.work_date,
        'dayStatus',d.day_status,
        'shiftId',d.shift_id,
        'shiftName',s.name,
        'startTime',coalesce(d.start_override,s.start_time),
        'endTime',coalesce(d.end_override,s.end_time),
        'workSiteId',d.work_site_id,
        'notes',d.notes
      ) ORDER BY d.work_date)
      FROM public.roster_days d
      LEFT JOIN public.shifts s ON s.id=d.shift_id
      JOIN public.work_rosters r ON r.id=d.roster_id
      WHERE d.employee_id=v_emp AND d.work_date BETWEEN p_from AND p_to
        AND d.day_status<>'cancelled' AND r.status='published'
    ),'[]'::jsonb),
    'corrections', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id',c.id,
        'workDate',c.work_date,
        'type',c.correction_type,
        'reason',c.reason,
        'status',c.status,
        'requestedCheckIn',c.requested_check_in,
        'requestedCheckOut',c.requested_check_out,
        'requestedStatus',c.requested_status,
        'reviewNote',c.review_note,
        'createdAt',c.created_at
      ) ORDER BY c.created_at DESC)
      FROM public.attendance_corrections c
      WHERE c.employee_id=v_emp AND c.work_date BETWEEN p_from AND p_to
    ),'[]'::jsonb),
    'periods', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id',p.id,'periodMonth',p.period_month,'status',p.status,'closedAt',p.closed_at
      ) ORDER BY p.period_month DESC)
      FROM public.attendance_periods p
      JOIN public.employees e ON e.id=v_emp
      LEFT JOIN public.branches b ON b.id=e.branch_id
      WHERE p.period_month BETWEEN date_trunc('month',p_from)::date AND date_trunc('month',p_to)::date
        AND (p.branch_id IS NULL OR p.branch_id=e.branch_id)
        AND (p.legal_entity_id IS NULL OR p.legal_entity_id=b.legal_entity_id)
    ),'[]'::jsonb),
    'lastUpdatedAt',now()
  );
END $$;

REVOKE ALL ON FUNCTION public.get_my_attendance_services(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_attendance_services(date, date) TO authenticated;
