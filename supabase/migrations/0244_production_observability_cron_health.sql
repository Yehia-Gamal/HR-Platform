-- Migration 0244: Production Observability — Cron Job Health Monitoring
-- ====================================================================
-- Adds health monitoring view and helper functions for pg_cron jobs.
-- Exposes last_run status to admin dashboards and alerting systems.

BEGIN;

-- ─── Cron health view ─────────────────────────────────────────────────────
-- Shows every scheduled job with its latest execution state.
CREATE OR REPLACE VIEW public.cron_job_health AS
WITH latest_runs AS (
  SELECT DISTINCT ON (jrd.jobid)
    jrd.jobid,
    jrd.status AS last_status,
    jrd.return_message AS last_message,
    jrd.start_time AS last_start,
    jrd.end_time AS last_end,
    EXTRACT(EPOCH FROM (jrd.end_time - jrd.start_time)) AS duration_seconds
  FROM cron.job_run_details jrd
  ORDER BY jrd.jobid, jrd.start_time DESC
),
failure_counts AS (
  SELECT
    jrd.jobid,
    COUNT(*) FILTER (WHERE jrd.status = 'failed') AS failures_24h
  FROM cron.job_run_details jrd
  WHERE jrd.start_time > now() - interval '24 hours'
  GROUP BY jrd.jobid
)
SELECT
  j.jobid,
  j.jobname,
  j.schedule,
  j.command,
  j.nodename,
  j.nodeport,
  j.database,
  j.username,
  j.active,
  lr.last_status,
  lr.last_message,
  lr.last_start,
  lr.last_end,
  lr.duration_seconds,
  COALESCE(fc.failures_24h, 0) AS failures_24h,
  -- Health classification
  CASE
    WHEN NOT j.active THEN 'disabled'
    WHEN lr.last_status IS NULL THEN 'never_run'
    WHEN lr.last_status = 'failed' THEN 'failing'
    WHEN COALESCE(fc.failures_24h, 0) >= 3 THEN 'unstable'
    ELSE 'healthy'
  END AS health_status
FROM cron.job j
LEFT JOIN latest_runs lr ON lr.jobid = j.jobid
LEFT JOIN failure_counts fc ON fc.jobid = j.jobid
ORDER BY j.jobid;

-- Restrict view to postgres/service_role only (cron schema is privileged)
REVOKE ALL ON public.cron_job_health FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.cron_job_health TO postgres, service_role;

COMMENT ON VIEW public.cron_job_health IS
  'Health status of all pg_cron jobs — consumed by observability dashboards and alerts.';

-- ─── Health summary RPC ───────────────────────────────────────────────────
-- Single-call summary used by the admin dashboard and Slack alerting.
CREATE OR REPLACE FUNCTION public.get_cron_health_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total_jobs', COUNT(*),
    'active', COUNT(*) FILTER (WHERE active),
    'failing', COUNT(*) FILTER (WHERE health_status = 'failing'),
    'unstable', COUNT(*) FILTER (WHERE health_status = 'unstable'),
    'healthy', COUNT(*) FILTER (WHERE health_status = 'healthy'),
    'never_run', COUNT(*) FILTER (WHERE health_status = 'never_run'),
    'disabled', COUNT(*) FILTER (WHERE health_status = 'disabled'),
    'checked_at', now(),
    'failures_24h_total', COALESCE(SUM(failures_24h), 0)
  )
  INTO result
  FROM public.cron_job_health;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_cron_health_summary() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_health_summary() TO postgres, service_role;

COMMENT ON FUNCTION public.get_cron_health_summary() IS
  'Aggregate health summary of pg_cron jobs. Used by admin dashboards and alert webhooks.';

-- ─── Detailed job list RPC ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_cron_job_health()
RETURNS SETOF public.cron_job_health
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
BEGIN
  RETURN QUERY SELECT * FROM public.cron_job_health;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_cron_job_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_job_health() TO postgres, service_role;

COMMENT ON FUNCTION public.get_cron_job_health() IS
  'Per-job health rows for observability dashboards.';

-- ─── Retention: purge old run details (keep 30 days) ─────────────────────
-- pg_cron's job_run_details grows unboundedly. Prune nightly.
-- Safe because we already capture health signals into the view above.
SELECT cron.schedule(
  'cron-run-details-cleanup',
  '15 3 * * *', -- 03:15 UTC daily
  $$
    DELETE FROM cron.job_run_details
    WHERE start_time < now() - interval '30 days';
  $$
)
WHERE NOT EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'cron-run-details-cleanup'
);

-- ─── Audit log table for observability events ─────────────────────────────
-- Centralized error table written by edge functions (via service_role).
CREATE TABLE IF NOT EXISTS public.observability_events (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at   timestamptz NOT NULL DEFAULT now(),
  level        text NOT NULL CHECK (level IN ('debug','info','warning','error','critical')),
  source       text NOT NULL, -- e.g., 'edge_function:verify-attendance-punch', 'web:admin', 'cron'
  event_type   text NOT NULL, -- e.g., 'error', 'performance', 'health_check'
  request_id   text,
  employee_id  uuid,
  user_id      uuid,
  message      text NOT NULL,
  error_name   text,
  error_stack  text,
  duration_ms  integer,
  metadata     jsonb DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS observability_events_created_at_idx
  ON public.observability_events (created_at DESC);
CREATE INDEX IF NOT EXISTS observability_events_level_idx
  ON public.observability_events (level) WHERE level IN ('error','critical');
CREATE INDEX IF NOT EXISTS observability_events_source_idx
  ON public.observability_events (source);

-- Only service_role can insert; admins (with proper RLS) can read.
ALTER TABLE public.observability_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.observability_events FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.observability_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.observability_events TO service_role;
GRANT SELECT ON TABLE public.observability_events TO authenticated;

DROP POLICY IF EXISTS service_role_all_access ON public.observability_events;
CREATE POLICY service_role_all_access
  ON public.observability_events
  FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- The project authorization model is role_permissions/has_permission(); there
-- is no public.user_permissions table.  Keep the table grant narrow and let RLS
-- authorize only full-access or explicitly permissioned administrators.
DROP POLICY IF EXISTS observability_read ON public.observability_events;
CREATE POLICY observability_read
  ON public.observability_events
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.has_permission('observability.read')
    OR public.has_permission('admin.observability')
  );

-- Auto-cleanup old events (keep 90 days)
SELECT cron.schedule(
  'observability-events-cleanup',
  '25 3 * * *',
  $$
    DELETE FROM public.observability_events
    WHERE created_at < now() - interval '90 days';
  $$
)
WHERE NOT EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'observability-events-cleanup'
);

COMMENT ON TABLE public.observability_events IS
  'Centralized event log for production observability — errors, performance markers, health checks.';

-- ─── pg_stat_statements activation check ──────────────────────────────────
-- Log a NOTICE if the extension is available but not loaded.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_stat_statements')
     AND NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
    RAISE NOTICE 'pg_stat_statements available but not loaded. Consider: CREATE EXTENSION pg_stat_statements;';
  END IF;
END $$;

COMMIT;
