-- 0230: restore server-only RPC privileges and close self-read compensation gap.

BEGIN;

-- These functions are implementation details invoked by trusted wrappers,
-- scheduled jobs, or Edge Functions. Authenticated clients must not execute
-- them directly even when the function body performs additional checks.
REVOKE ALL ON FUNCTION public.record_attendance_event(uuid, text, double precision, double precision, numeric, text, text, uuid, boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_attendance_event(uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finalize_verified_attendance(uuid, uuid, uuid, uuid, uuid, uuid, text, double precision, double precision, double precision, bigint, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finalize_missing_checkouts() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.run_monthly_leave_accrual(integer, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.detect_and_raise_alerts() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.open_annual_leave_entitlement(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._build_attendance_statement(uuid, integer, integer) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.record_attendance_event(uuid, text, double precision, double precision, numeric, text, text, uuid, boolean, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_attendance_event(uuid, text, double precision, double precision, double precision, text, text, uuid, boolean, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.finalize_verified_attendance(uuid, uuid, uuid, uuid, uuid, uuid, text, double precision, double precision, double precision, bigint, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.finalize_missing_checkouts() TO service_role;
GRANT EXECUTE ON FUNCTION public.run_monthly_leave_accrual(integer, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.detect_and_raise_alerts() TO service_role;
GRANT EXECUTE ON FUNCTION public.open_annual_leave_entitlement(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public._build_attendance_statement(uuid, integer, integer) TO service_role;

-- can_access_employee() intentionally grants self visibility. Compensation and
-- loan policies must additionally require an explicit payroll permission, or
-- every employee can read their raw compensation row.
DROP POLICY IF EXISTS employee_compensation_select ON public.employee_compensation;
CREATE POLICY employee_compensation_select
  ON public.employee_compensation
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR (
      public.has_permission('payroll.structure.manage')
      AND public.can_access_employee(employee_id, 'payroll.structure.manage')
    )
  );

DROP POLICY IF EXISTS employee_loans_select ON public.employee_loans;
CREATE POLICY employee_loans_select
  ON public.employee_loans
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR (
      public.has_permission('payroll.structure.manage')
      AND public.can_access_employee(employee_id, 'payroll.structure.manage')
    )
  );

COMMIT;
