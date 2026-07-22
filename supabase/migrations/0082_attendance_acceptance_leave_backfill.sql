-- 0082: Make verified, in-complex attendance final and visible immediately.
-- Also opens the current-year leave entitlement for every existing employee
-- and for employees created in the future.

DROP FUNCTION IF EXISTS public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean
);

CREATE OR REPLACE FUNCTION public.record_attendance_event(
  p_employee_id uuid,
  p_event_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_biometric_method text DEFAULT 'passkey',
  p_selfie_path text DEFAULT NULL,
  p_passkey_credential_id uuid DEFAULT NULL,
  p_verified boolean DEFAULT false,
  p_is_mock boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_event_id uuid;
  v_assignment public.shift_assignments%rowtype;
  v_geofence public.geofences%rowtype;
  v_shift public.shifts%rowtype;
  v_roster_shift_id uuid;
  v_roster_geofence_id uuid;
  v_now timestamptz := now();
  v_work_date date := (v_now AT TIME ZONE 'Africa/Cairo')::date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
BEGIN
  IF COALESCE(
       current_setting('request.jwt.claim.role', true),
       current_setting('role', true),
       current_user
     ) NOT IN ('service_role', 'postgres', 'supabase_admin')
     AND current_user <> 'service_role' THEN
    RAISE EXCEPTION 'attendance_trusted_server_required' USING errcode = '42501';
  END IF;

  IF p_event_type NOT IN ('CHECK_IN', 'CHECK_OUT') THEN
    RAISE EXCEPTION 'invalid_event_type' USING errcode = '22023';
  END IF;
  IF p_employee_id IS NULL OR NOT p_verified THEN
    RAISE EXCEPTION 'attendance_identity_not_verified' USING errcode = '28000';
  END IF;
  IF p_is_mock THEN
    RAISE EXCEPTION 'attendance_mock_location_rejected' USING errcode = '22023';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL OR p_accuracy_meters IS NULL THEN
    RAISE EXCEPTION 'attendance_location_required' USING errcode = '22023';
  END IF;

  IF p_passkey_credential_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.passkey_credentials pc
    WHERE pc.id = p_passkey_credential_id
      AND pc.employee_id = p_employee_id
      AND pc.status = 'active'
      AND pc.trusted = true
  ) THEN
    RAISE EXCEPTION 'attendance_passkey_not_trusted' USING errcode = '28000';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.attendance_events ae
    WHERE ae.employee_id = p_employee_id
      AND ae.event_type = p_event_type
      AND ae.event_at > v_now - interval '60 seconds'
  ) THEN
    RAISE EXCEPTION 'duplicate_attendance_event' USING errcode = '23505';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.attendance_daily
    WHERE employee_id = p_employee_id
      AND work_date = v_work_date
      AND is_finalized = true
  ) THEN
    RAISE EXCEPTION 'attendance_period_finalized' USING errcode = '55000';
  END IF;

  SELECT ae.event_type INTO v_last_event_type
  FROM public.attendance_events ae
  WHERE ae.employee_id = p_employee_id
    AND (ae.event_at AT TIME ZONE 'Africa/Cairo')::date = v_work_date
    AND ae.status IN ('accepted', 'adjusted')
  ORDER BY ae.event_at DESC
  LIMIT 1;
  IF p_event_type = 'CHECK_OUT'
     AND v_last_event_type IS DISTINCT FROM 'CHECK_IN' THEN
    RAISE EXCEPTION 'attendance_check_in_required' USING errcode = '22023';
  END IF;
  IF p_event_type = 'CHECK_IN' AND v_last_event_type = 'CHECK_IN' THEN
    RAISE EXCEPTION 'attendance_check_out_required' USING errcode = '22023';
  END IF;

  -- A published roster is the most specific assignment for the current day.
  SELECT rd.shift_id, rd.geofence_id
    INTO v_roster_shift_id, v_roster_geofence_id
  FROM public.roster_days rd
  JOIN public.work_rosters wr ON wr.id = rd.roster_id AND wr.status = 'published'
  WHERE rd.employee_id = p_employee_id
    AND rd.work_date = v_work_date
    AND rd.day_status = 'scheduled'
  ORDER BY wr.published_at DESC NULLS LAST
  LIMIT 1;

  SELECT * INTO v_assignment
  FROM public.shift_assignments sa
  WHERE sa.employee_id = p_employee_id
    AND sa.is_active = true
    AND sa.effective_from <= v_work_date
    AND (sa.effective_to IS NULL OR sa.effective_to >= v_work_date)
  ORDER BY sa.effective_from DESC
  LIMIT 1;

  IF v_roster_geofence_id IS NOT NULL THEN
    SELECT * INTO v_geofence FROM public.geofences
    WHERE id = v_roster_geofence_id AND is_active = true;
  ELSIF v_assignment.geofence_id IS NOT NULL THEN
    SELECT * INTO v_geofence FROM public.geofences
    WHERE id = v_assignment.geofence_id AND is_active = true;
  END IF;

  IF v_geofence.id IS NULL THEN
    RAISE EXCEPTION 'attendance_geofence_not_configured' USING errcode = '55000';
  END IF;

  v_distance := public.geo_distance_meters(
    p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
  )::numeric(12,2);

  IF v_distance > v_geofence.radius_meters THEN
    RAISE EXCEPTION 'attendance_outside_complex' USING errcode = '22023';
  END IF;
  IF v_geofence.max_accuracy IS NOT NULL
     AND p_accuracy_meters > v_geofence.max_accuracy THEN
    RAISE EXCEPTION 'attendance_location_accuracy_too_low' USING errcode = '22023';
  END IF;

  IF COALESCE(v_roster_shift_id, v_assignment.shift_id) IS NOT NULL THEN
    SELECT * INTO v_shift FROM public.shifts
    WHERE id = COALESCE(v_roster_shift_id, v_assignment.shift_id);
  END IF;
  IF p_event_type = 'CHECK_IN' AND v_shift.id IS NOT NULL THEN
    v_late := public.calculate_late_minutes(
      v_now, v_shift.start_time, v_shift.grace_in_minutes, v_work_date
    );
  END IF;

  INSERT INTO public.attendance_events (
    employee_id, shift_assignment_id, geofence_id, event_type, event_at,
    latitude, longitude, accuracy_meters, distance_meters, status,
    late_minutes, requires_review, verification_status,
    passkey_credential_id, biometric_method, selfie_path, server_verified,
    is_mock_location, notes, source, created_by
  ) VALUES (
    p_employee_id, v_assignment.id, v_geofence.id, p_event_type, v_now,
    p_latitude, p_longitude, p_accuracy_meters, v_distance, 'accepted',
    v_late, false, 'passkey_verified',
    p_passkey_credential_id, COALESCE(p_biometric_method, 'passkey'),
    p_selfie_path, true, false,
    'inside_complex', 'mobile', NULL
  ) RETURNING id INTO v_event_id;

  SELECT min(event_at) FILTER (WHERE event_type = 'CHECK_IN'),
         max(event_at) FILTER (WHERE event_type = 'CHECK_OUT')
    INTO v_first_check_in, v_last_check_out
  FROM public.attendance_events
  WHERE employee_id = p_employee_id
    AND (event_at AT TIME ZONE 'Africa/Cairo')::date = v_work_date
    AND status IN ('accepted', 'adjusted');

  INSERT INTO public.attendance_daily (
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    work_minutes, late_minutes, status, is_finalized, created_by
  ) VALUES (
    p_employee_id, v_work_date, COALESCE(v_roster_shift_id, v_assignment.shift_id),
    v_first_check_in, v_last_check_out,
    CASE WHEN v_first_check_in IS NOT NULL AND v_last_check_out IS NOT NULL
      THEN GREATEST(0, floor(extract(epoch FROM (v_last_check_out - v_first_check_in)) / 60)::integer)
      ELSE 0 END,
    v_late,
    CASE
      WHEN v_first_check_in IS NULL THEN 'partial'
      WHEN v_late > 0 THEN 'late'
      ELSE 'present'
    END,
    false, NULL
  )
  ON CONFLICT ON CONSTRAINT attendance_daily_uq DO UPDATE SET
    shift_id = COALESCE(EXCLUDED.shift_id, attendance_daily.shift_id),
    first_check_in = COALESCE(EXCLUDED.first_check_in, attendance_daily.first_check_in),
    last_check_out = COALESCE(EXCLUDED.last_check_out, attendance_daily.last_check_out),
    work_minutes = EXCLUDED.work_minutes,
    late_minutes = GREATEST(attendance_daily.late_minutes, EXCLUDED.late_minutes),
    status = CASE
      WHEN attendance_daily.status IN ('on_leave', 'holiday', 'weekend') THEN attendance_daily.status
      WHEN EXCLUDED.first_check_in IS NULL THEN 'partial'
      WHEN GREATEST(attendance_daily.late_minutes, EXCLUDED.late_minutes) > 0 THEN 'late'
      ELSE 'present'
    END,
    updated_at = now()
  WHERE attendance_daily.is_finalized = false;

  UPDATE public.passkey_credentials SET last_used = v_now
  WHERE id = p_passkey_credential_id;

  PERFORM public.log_audit_event(
    'attendance.' || lower(p_event_type), 'security', 'info',
    'attendance_events', v_event_id, 'بصمة موثقة داخل نطاق المجمع', NULL,
    jsonb_build_object(
      'method', p_biometric_method,
      'insideComplex', true,
      'distanceMeters', v_distance,
      'geofenceId', v_geofence.id
    )
  );

  RETURN v_event_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean
) TO service_role;

-- Future employees receive their current-year statutory opening balances.
CREATE OR REPLACE FUNCTION public.tg_open_employee_leave_entitlement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.is_deleted = false AND NEW.status IN ('active', 'invited', 'onboarding') THEN
    PERFORM public.open_annual_leave_entitlement(
      NEW.id,
      extract(year FROM (now() AT TIME ZONE 'Africa/Cairo'))::integer
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employee_open_leave_entitlement ON public.employees;
CREATE TRIGGER trg_employee_open_leave_entitlement
AFTER INSERT ON public.employees
FOR EACH ROW EXECUTE FUNCTION public.tg_open_employee_leave_entitlement();

-- Idempotent backfill for every employee already registered in the application.
DO $$
DECLARE
  v_employee record;
  v_year integer := extract(year FROM (now() AT TIME ZONE 'Africa/Cairo'))::integer;
  v_ent jsonb;
  v_type record;
  v_units numeric;
BEGIN
  FOR v_employee IN
    SELECT id FROM public.employees
    WHERE is_deleted = false AND status IN ('active', 'invited', 'onboarding')
  LOOP
    v_ent := public.effective_annual_entitlement(v_employee.id, make_date(v_year, 1, 1));
    FOR v_type IN SELECT id, code FROM public.leave_types
      WHERE is_active AND code IN ('annual', 'casual', 'sick')
    LOOP
      v_units := CASE v_type.code
        WHEN 'annual' THEN (v_ent->>'annual')::numeric
        WHEN 'casual' THEN (v_ent->>'casual')::numeric
        WHEN 'sick' THEN 24
      END;
      PERFORM public.apply_leave_ledger_entry(
        v_employee.id, v_type.id, v_year, 'opening', v_units,
        format('leave:opening:%s:%s:%s', v_type.code, v_employee.id, v_year),
        NULL, 'فتح تلقائي لرصيد الإجازة السنوي',
        jsonb_build_object('entitlement', v_ent, 'backfilled', true)
      );
    END LOOP;
  END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
