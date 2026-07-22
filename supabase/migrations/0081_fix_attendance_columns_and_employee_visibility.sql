-- Migration 0081: Fix attendance column names + employee visibility
-- Fixes:
--   1. record_attendance_event: wrong column names (verified→server_verified, is_mock→is_mock_location, recorded_at→event_at)
--   2. get_location_directory: include invited/onboarding employees for full-access callers
--   3. request_live_location: accept non-active employees
--   4. handle_new_user trigger: stop creating ghost employee rows

-- ─────────────────────────────────────────────────────────────────────
-- 1. Fix record_attendance_event — correct column names
-- ─────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean
);
DROP FUNCTION IF EXISTS public.record_attendance_event(
  uuid, text, double precision, double precision, numeric, text, text, uuid, boolean
);
DROP FUNCTION IF EXISTS public.record_attendance_event(
  uuid, text, double precision, double precision, numeric, text, text, uuid, boolean, boolean
);

CREATE OR REPLACE FUNCTION public.record_attendance_event(
  p_employee_id         uuid,
  p_event_type          text,
  p_latitude            double precision,
  p_longitude           double precision,
  p_accuracy_meters     double precision,
  p_biometric_method    text    DEFAULT 'passkey',
  p_selfie_path         text    DEFAULT NULL,
  p_passkey_credential_id uuid DEFAULT NULL,
  p_verified            boolean DEFAULT false,
  p_is_mock             boolean DEFAULT false
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
    biometric_method, selfie_path, passkey_credential_id,
    server_verified, is_mock_location, event_at, created_by
  ) VALUES (
    p_employee_id, p_event_type, p_latitude, p_longitude, p_accuracy_meters,
    p_biometric_method, p_selfie_path, p_passkey_credential_id,
    p_verified, p_is_mock, now(), auth.uid()
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


-- ─────────────────────────────────────────────────────────────────────
-- 2. Fix get_location_directory — show invited/onboarding for full-access
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_location_directory(
  p_search text    default null,
  p_limit  integer default 100
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT (public.current_is_full_access() OR public.has_permission('live_location.request')) THEN
    RAISE EXCEPTION 'live location request permission required' USING errcode = '42501';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id',                  q.id,
      'name',                q.full_name_ar,
      'employeeCode',        q.employee_code,
      'jobTitle',            q.job_title,
      'department',          q.department,
      'lastLatitude',        q.latitude,
      'lastLongitude',       q.longitude,
      'lastAccuracy',        q.accuracy,
      'lastRecordedAt',      q.recorded_at,
      'activeRequestId',     q.active_request_id,
      'activeRequestStatus', q.active_request_status
    ) ORDER BY q.full_name_ar)
    FROM (
      SELECT
        e.id, e.full_name_ar, e.employee_code,
        jt.name  job_title,
        d.name   department,
        last_point.latitude, last_point.longitude,
        last_point.accuracy, last_point.recorded_at,
        active_req.id     active_request_id,
        active_req.status active_request_status
      FROM public.employees e
      LEFT JOIN public.job_titles  jt  ON jt.id = e.job_title_id
      LEFT JOIN public.departments d   ON d.id  = e.department_id
      LEFT JOIN LATERAL (
        SELECT l.latitude, l.longitude, l.accuracy, l.recorded_at
        FROM public.employee_locations l
        WHERE l.employee_id = e.id
        ORDER BY l.recorded_at DESC LIMIT 1
      ) last_point ON TRUE
      LEFT JOIN LATERAL (
        SELECT r.id, r.status
        FROM public.live_location_requests r
        WHERE r.employee_id = e.id
          AND r.status IN ('pending','accepted','active')
          AND (r.expires_at IS NULL OR r.expires_at > now())
        ORDER BY r.requested_at DESC LIMIT 1
      ) active_req ON TRUE
      WHERE e.status IN ('active', 'invited', 'onboarding')
        AND e.is_deleted = false
        AND e.id IS DISTINCT FROM public.current_employee_id()
        AND e.user_id IS NOT NULL
        AND (
          public.current_is_full_access()
          OR public.can_access_employee(e.id, 'live_location.request')
        )
        AND (
          COALESCE(TRIM(p_search), '') = ''
          OR e.full_name_ar    ILIKE '%' || TRIM(p_search) || '%'
          OR e.employee_code   ILIKE '%' || TRIM(p_search) || '%'
        )
      ORDER BY e.full_name_ar
      LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 300))
    ) q
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_location_directory(text, integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_location_directory(text, integer) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 3. Fix request_live_location — accept invited/onboarding employees
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.request_live_location(
  p_employee_id uuid,
  p_mode text,
  p_reason text default ''
)
RETURNS public.live_location_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_me            uuid    := public.current_employee_id();
  v_duration      integer;
  v_video_seconds integer := 0;
  v_row           public.live_location_requests;
  v_target_user   uuid;
  v_recent_count  integer;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'requester has no employee profile' USING errcode = '42501';
  END IF;
  IF NOT (public.current_is_full_access() OR public.can_access_employee(p_employee_id, 'live_location.request')) THEN
    RAISE EXCEPTION 'target outside permitted scope' USING errcode = '42501';
  END IF;
  IF p_employee_id = v_me THEN
    RAISE EXCEPTION 'cannot request own location' USING errcode = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.employees
    WHERE id = p_employee_id AND status IN ('active', 'invited', 'onboarding') AND user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'employee is not active or has no linked user account' USING errcode = 'P0002';
  END IF;

  -- Cooldown: max 1 request per 30 seconds per requester+target
  SELECT count(*) INTO v_recent_count
  FROM public.live_location_requests
  WHERE requested_by = v_me
    AND employee_id = p_employee_id
    AND requested_at > now() - interval '30 seconds';
  IF v_recent_count > 0 THEN
    RAISE EXCEPTION 'cooldown_active: please wait 30 seconds between requests' USING errcode = '22023';
  END IF;

  v_duration := CASE p_mode
    WHEN 'snapshot'       THEN 1
    WHEN 'video_5s'       THEN 2
    WHEN 'location_video' THEN 2
    WHEN 'track_5'        THEN 5
    WHEN 'track_10'       THEN 10
    WHEN 'track_15'       THEN 15
    WHEN 'track_30'       THEN 30
    ELSE NULL
  END;
  IF v_duration IS NULL THEN
    RAISE EXCEPTION 'invalid request mode' USING errcode = '22023';
  END IF;
  IF p_mode IN ('video_5s', 'location_video') THEN
    v_video_seconds := 5;
  END IF;

  -- Auto-cancel any previous active location request for this employee
  UPDATE public.live_location_requests
  SET status     = 'rejected',
      expires_at = now(),
      metadata   = jsonb_set(
                     COALESCE(metadata, '{}'::jsonb),
                     '{autoCancelledByNewRequest}', 'true'
                   )
  WHERE employee_id = p_employee_id
    AND status IN ('pending', 'accepted', 'active')
    AND (expires_at IS NULL OR expires_at > now());

  INSERT INTO public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  ) VALUES (
    p_employee_id, v_me,
    COALESCE(NULLIF(TRIM(p_reason), ''), NULL),
    'pending', 'verification',
    now(), now() + interval '5 minutes',
    v_duration,
    jsonb_build_object('mode', p_mode, 'videoSeconds', v_video_seconds),
    auth.uid()
  ) RETURNING * INTO v_row;

  SELECT user_id INTO v_target_user FROM public.employees WHERE id = p_employee_id;
  IF v_target_user IS NOT NULL THEN
    INSERT INTO public.notifications(
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, action_url, entity_type, entity_id, created_by
    ) VALUES (
      v_target_user, p_employee_id,
      'طلب تحقق من الموقع',
      'المدير يطلب التحقق من موقعك. يرجى الاستجابة فوراً.',
      'system', 'urgent',
      '/location-requests', 'live_location_request', v_row.id, auth.uid()
    );
  END IF;

  PERFORM public.log_audit_event(
    'live_location_requested',
    'security',
    'warning',
    'live_location_requests',
    v_row.id,
    'طلب موقع حي',
    NULL,
    jsonb_build_object('mode', p_mode, 'employeeId', p_employee_id)
  );

  PERFORM public.nudge_notification_dispatcher();

  RETURN v_row;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────
-- 4. Fix handle_new_user trigger — don't create ghost employee rows
-- ─────────────────────────────────────────────────────────────────────
-- The trigger creates an employee row with user_id=NULL on every auth.users
-- insert, which conflicts with provision_employee_record and creates
-- orphan rows. Replace with a no-op; provisioning is done explicitly via
-- admin-create-employee or provision_employee_record.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Intentionally empty: employee provisioning is handled explicitly
  -- by provision_employee_record / admin-create-employee edge function.
  RETURN new;
END;
$$;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
