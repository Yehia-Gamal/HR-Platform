-- Migration 0045: restore base table privileges for the `authenticated`/`anon`
-- API roles so the existing Row-Level Security policies actually take effect,
-- while preserving the server-authoritative (RPC-only) tables.
--
-- Runtime defect found during pgTAP verification (tests/0027 persona RLS matrix,
-- assertion 1): every direct table access by an authenticated user failed with
-- `ERROR: permission denied for table employees` *before* RLS was ever evaluated.
--
-- Root cause: PostgreSQL applies table-level GRANTs first and Row-Level Security
-- second. The schema enables RLS on the public tables and defines 190+ SELECT /
-- 87 INSERT / 87 UPDATE / 77 DELETE / 62 ALL policies for `{authenticated}`, but
-- no migration ever granted the base table privileges to the `authenticated`
-- role (only the inherited REFERENCES/TRIGGER/TRUNCATE remained). As a result the
-- RLS policies were effectively dead: the API-facing `authenticated` role could
-- not read or write any public table directly, and every read only worked through
-- SECURITY DEFINER RPCs. This is the Supabase-standard access model
-- (grant privileges, let RLS filter rows), matching how `storage.objects` is
-- already granted to `authenticated` in the managed schema.
--
-- Fix: grant standard DML on all current and future public tables to
-- `authenticated` (and SELECT to `anon`), then RE-REVOKE the privileges on the
-- server-authoritative tables whose security relies on the *absence* of a direct
-- grant (writes flow only through SECURITY DEFINER RPCs / service_role). The
-- carve-out set is defined by the contract tests:
--   * attendance_events        — no direct INSERT/UPDATE/DELETE (tests/0010, 0027)
--   * passkey_credentials      — no direct INSERT/UPDATE/DELETE (tests/0010, 0012)
--   * webauthn_challenges      — no direct INSERT/UPDATE/DELETE (tests/0012)
--   * login_auth_attempts      — no SELECT for authenticated/anon  (tests/0025)
--   * credential_vault,
--     password_reset_requests  — RLS-enabled with no policy; also stripped of any
--                                direct authenticated/anon access for defense in depth.
--
-- Security preserved because:
--   * RLS stays enabled and remains the row gatekeeper for every granted table.
--   * `anon` gets SELECT only; no public policy targets anon, so RLS returns zero
--     rows for anonymous queries (persona tests assert 0-count, not an error).
--   * The carve-out tables keep their RPC-only / server-only write model.
--   * Sensitive writes still run through SECURITY DEFINER RPCs that enforce
--     has_permission / provisioning checks internally, plus RLS and BEFORE triggers.
--
-- Regression coverage: tests/0027 (23 assertions), tests/0010 (passkey/attendance
-- privilege absence), tests/0012 (passkey/webauthn privilege absence), tests/0025
-- (login_auth_attempts not readable) must all pass together.

begin;

-- 1) Base DML privileges for the API role; RLS still filters every row.
grant select, insert, update, delete on all tables in schema public to authenticated;

-- 2) Read-only for anon; RLS returns zero rows because no public policy targets anon.
grant select on all tables in schema public to anon;

-- 3) Sequences backing identity/serial columns so authenticated inserts can advance them.
grant usage, select on all sequences in schema public to authenticated;

-- 4) Future tables/sequences created in public inherit the same grants.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant select on tables to anon;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;

-- 5) Carve-outs: server-authoritative tables. Writes only via SECURITY DEFINER
--    RPCs / service_role, so strip direct write privileges from the API roles.
revoke insert, update, delete on public.attendance_events   from authenticated, anon;
revoke insert, update, delete on public.passkey_credentials from authenticated, anon;
revoke insert, update, delete on public.webauthn_challenges from authenticated, anon;

-- 6) Credential / secret ledgers: no direct API access at all (RLS also denies).
revoke select, insert, update, delete on public.login_auth_attempts    from authenticated, anon;
revoke select, insert, update, delete on public.credential_vault        from authenticated, anon;
revoke select, insert, update, delete on public.password_reset_requests from authenticated, anon;

commit;
