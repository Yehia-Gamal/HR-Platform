-- Fix PGRST203: Drop ALL overloads of record_attendance_event and recreate
-- with consistent types and proper grants.
--
-- Root cause: migration 0046 created the function with p_accuracy_meters NUMERIC,
-- migration 0073 did CREATE OR REPLACE with p_accuracy_meters DOUBLE PRECISION.
-- CREATE OR REPLACE only replaces when ALL param types match exactly, so two
-- overloads co-existed. PostgREST raised PGRST203 (ambiguous/no match).
-- Migration 0075 dropped the numeric overloads but the double-precision version
-- created by 0073 was missing the GRANT EXECUTE for service_role.

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
    'حضور بالبصمة',
    NULL,
    jsonb_build_object('method', p_biometric_method, 'verified', p_verified)
  );

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.record_attendance_event IS
  'RPC: يسجل حدث حضور/انصراف بالبصمة عبر Edge Function (service_role فقط).';

REVOKE ALL ON FUNCTION public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean
) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.record_attendance_event(
  uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean
) TO service_role;
