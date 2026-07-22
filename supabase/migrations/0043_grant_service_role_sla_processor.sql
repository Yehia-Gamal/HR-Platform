-- Migration 0043: grant service_role execution on the request-SLA processor.
--
-- Runtime defect found during pgTAP verification (tests/0014 test 12):
-- migration 0026 revoked EXECUTE on public.process_request_sla(integer) from
-- public and authenticated, but never granted it to service_role. Because the
-- revoke from PUBLIC removes the default grant for every role, the scheduled
-- SLA worker (service_role) could not execute the processor at runtime.
-- The function already enforces its own guard internally
-- (auth.role() = 'service_role' or full-access), so this grant only restores
-- the intended caller without widening access for authenticated/anon.

begin;

revoke execute on function public.process_request_sla(integer) from public, authenticated, anon;
grant execute on function public.process_request_sla(integer) to service_role;

commit;
