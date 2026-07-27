-- Migration 0160: Security — search_path hardening on utility functions
-- Agent 11 (Database Security Continuous)
-- Root Cause: Four early utility functions (0001, 0010, 0011, 0058) were
--   created without SET search_path. While none are SECURITY DEFINER (so the
--   real-world exploit risk is minimal), defense-in-depth requires pinning
--   search_path on EVERY function to prevent schema-injection if a malicious
--   schema is ever added to a user's search_path.
-- Rollback: Simply DROP OR REPLACE these functions WITHOUT the search_path
--   clause — their bodies are unchanged, so no data impact.

-- ─────────────────────────────────────────────────────────────────────
-- 1. server_now() — originally 0001, never redefined
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.server_now()
RETURNS timestamptz
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $$ SELECT now(); $$;

COMMENT ON FUNCTION public.server_now() IS
  'Returns server UTC timestamp. Pinned search_path (0160 hardening).';


-- ─────────────────────────────────────────────────────────────────────
-- 2. set_updated_at() — trigger helper, last defined in 0011
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at() IS
  'Trigger helper: sets updated_at = now() on row UPDATE. Pinned search_path (0160 hardening).';


-- ─────────────────────────────────────────────────────────────────────
-- 3. tg_set_updated_at() — trigger helper, last defined in 0010
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tg_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tg_set_updated_at() IS
  'Trigger helper: sets updated_at = now() on row UPDATE. Pinned search_path (0160 hardening).';


-- ─────────────────────────────────────────────────────────────────────
-- 4. kpi_effective_deadline(kpi_cycles) — defined in 0058, never redefined
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.kpi_effective_deadline(p_cycle public.kpi_cycles)
RETURNS timestamptz
LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp
AS $$ SELECT coalesce(p_cycle.extended_until, p_cycle.deadline_at); $$;

COMMENT ON FUNCTION public.kpi_effective_deadline(public.kpi_cycles) IS
  'Returns effective KPI deadline (extended or original). Pinned search_path (0160 hardening).';


-- ─────────────────────────────────────────────────────────────────────
-- Reload PostgREST schema cache
-- ─────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
