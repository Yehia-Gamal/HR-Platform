-- Migration 0205: Fix historical attendance records
-- Records created before mig 0201 geofence-fallback may have wrong
-- status / verification_status, causing monthly statements to show 0%.
--
-- Scope:
--   ① attendance_events from local_biometric source with status NOT IN
--      ('accepted','adjusted') → set to 'accepted' + 'biometric_verified'
--      UNLESS requires_review = true (genuine impossible-travel flag).
--   ② Fix verification_status on already-accepted biometric records.
--   ③ Rebuild attendance_daily rows for every affected (employee, work_date).

BEGIN;

-- ① Fix event status + verification for local-biometric records
--    that were incorrectly left as 'pending'/'flagged'/NULL.
UPDATE attendance_events
SET    status              = 'accepted',
       verification_status = 'biometric_verified',
       updated_at          = now()
WHERE  source = 'local_biometric'
  AND  status NOT IN ('accepted', 'adjusted')
  AND  requires_review IS NOT TRUE;

-- ② Also fix verification_status on records that ARE accepted
--    but have NULL/wrong verification_status (pre-0201 biometric path).
UPDATE attendance_events
SET    verification_status = 'biometric_verified',
       updated_at          = now()
WHERE  source = 'local_biometric'
  AND  status IN ('accepted', 'adjusted')
  AND  (verification_status IS NULL
        OR verification_status NOT IN ('biometric_verified', 'passkey_verified'));

-- ③ Rebuild attendance_daily for all employees who have local-biometric
--    events. Uses the same aggregation logic as record_attendance_local_biometric:
--    only events with status IN ('accepted','adjusted') count.
INSERT INTO attendance_daily (
  employee_id,
  work_date,
  first_check_in,
  last_check_out,
  work_minutes,
  late_minutes,
  status,
  is_finalized,
  updated_at
)
SELECT
  e.employee_id,
  e.work_date,
  MIN(e.event_at) FILTER (WHERE e.event_type = 'CHECK_IN'),
  MAX(e.event_at) FILTER (WHERE e.event_type = 'CHECK_OUT'),
  COALESCE(
    GREATEST(0, FLOOR(
      EXTRACT(EPOCH FROM (
        MAX(e.event_at) FILTER (WHERE e.event_type = 'CHECK_OUT')
        - MIN(e.event_at) FILTER (WHERE e.event_type = 'CHECK_IN')
      )) / 60
    )::integer),
    0
  ),
  0,  -- late_minutes: keep existing or default
  CASE
    WHEN COUNT(*) FILTER (WHERE e.event_type = 'CHECK_IN') = 0 THEN 'partial'
    ELSE 'present'
  END,
  false,
  now()
FROM (
  SELECT
    employee_id,
    event_type,
    event_at,
    (event_at AT TIME ZONE 'Africa/Cairo')::date AS work_date
  FROM attendance_events
  WHERE source = 'local_biometric'
    AND status IN ('accepted', 'adjusted')
) e
GROUP BY e.employee_id, e.work_date
HAVING COUNT(*) FILTER (WHERE e.event_type = 'CHECK_IN') > 0
ON CONFLICT ON CONSTRAINT attendance_daily_uq DO UPDATE SET
  first_check_in = COALESCE(EXCLUDED.first_check_in, attendance_daily.first_check_in),
  last_check_out = COALESCE(EXCLUDED.last_check_out, attendance_daily.last_check_out),
  work_minutes   = EXCLUDED.work_minutes,
  status         = CASE
    WHEN attendance_daily.status IN ('on_leave', 'holiday', 'weekend')
      THEN attendance_daily.status
    WHEN EXCLUDED.first_check_in IS NULL THEN 'partial'
    ELSE 'present'
  END,
  updated_at     = now()
WHERE attendance_daily.is_finalized = false;

COMMIT;
