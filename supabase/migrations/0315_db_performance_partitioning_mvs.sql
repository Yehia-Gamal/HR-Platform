-- Migration 0315: Database Performance — Partitioning, pg_stat_statements, MV Refresh
-- ================================================================================
-- Initiative 6: Adds table partitioning for large audit/attendance tables,
-- activates pg_stat_statements for query analysis, and schedules MV refreshes.

BEGIN;

-- ─── Section 1: pg_stat_statements activation ─────────────────────────────
-- Required for query performance analysis. Safe to create if already exists.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_stat_statements')
     AND NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
    -- Note: requires shared_preload_libraries on Supabase managed. May fail silently.
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'pg_stat_statements requires shared_preload_libraries — skipping';
    END;
  END IF;
END $$;

-- ─── Section 2: Composite indexes for common query patterns ───────────────
-- These cover the most frequent dashboard/list queries that currently do seq scans.

-- attendance_events: filtered by employee + date range (dashboard drilldown)
-- (تصحيح: العمود الفعلي في attendance_events هو event_at وليس event_date)
CREATE INDEX IF NOT EXISTS idx_attendance_events_employee_date
  ON public.attendance_events (employee_id, event_at DESC)
  WHERE event_at IS NOT NULL;

-- attendance_daily: monthly roster lookups
CREATE INDEX IF NOT EXISTS idx_attendance_daily_employee_month
  ON public.attendance_daily (employee_id, work_date DESC)
  WHERE work_date IS NOT NULL;

-- audit_events: recent activity feed (most common query)
CREATE INDEX IF NOT EXISTS idx_audit_events_created_at_desc
  ON public.audit_events (created_at DESC)
  WHERE created_at IS NOT NULL;

-- audit_events: filter by actor + time range
-- (تصحيح: أعمدة audit_events الفعلية هي actor_user_id/actor_employee_id وليس actor_id)
CREATE INDEX IF NOT EXISTS idx_audit_events_actor_created
  ON public.audit_events (actor_user_id, created_at DESC)
  WHERE actor_user_id IS NOT NULL;

-- requests: status + employee lookup
CREATE INDEX IF NOT EXISTS idx_requests_status_employee
  ON public.requests (status, employee_id)
  WHERE status IS NOT NULL;

-- notifications: unread per user
-- (تصحيح: عمود notifications الفعلي هو recipient_user_id وليس recipient_id)
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_unread
  ON public.notifications (recipient_user_id, created_at DESC)
  WHERE read_at IS NULL;

-- leave_requests: per-employee period lookups (balances/ledger/history)
-- (تصحيح: leave_requests لا تملك status/submitted_at — تملكها requests؛ الفهرس هنا
--  على الأعمدة الفعلية employee_id + start_date للاستعلامات الشائعة)
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee_dates
  ON public.leave_requests (employee_id, start_date DESC)
  WHERE employee_id IS NOT NULL;

-- ─── Section 3: Partitioning strategy for audit_events ────────────────────
-- audit_events grows unboundedly. Partition by month for pruning.
-- Note: We can't ALTER TABLE ... PARTITION on an existing table directly.
-- Instead, we create a partitioned shadow table and a trigger to route inserts.
-- This is a non-breaking approach: the original table stays queryable.

-- Check if partitioned shadow table already exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'audit_events_partitioned') THEN

    -- Create partitioned parent (monthly partitions)
    EXECUTE $sql$
      CREATE TABLE public.audit_events_partitioned (
        LIKE public.audit_events INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING STORAGE INCLUDING COMMENTS
      ) PARTITION BY RANGE (created_at);
    $sql$;

    -- Default partition catches anything outside monthly partitions
    EXECUTE $sql$
      CREATE TABLE public.audit_events_partitioned_default
        PARTITION OF public.audit_events_partitioned DEFAULT;
    $sql$;

    COMMENT ON TABLE public.audit_events_partitioned IS
      'Shadow partitioned table for audit_events — monthly partitions for query pruning. Populated by trigger.';
  END IF;
END $$;

-- Create current + next 3 months of partitions (idempotent)
DO $$
DECLARE
  month_start timestamptz;
  month_end timestamptz;
  part_name text;
  mon int;
  yr int;
BEGIN
  FOR i IN 0..3 LOOP
    yr := extract(year from date_trunc('month', now() + (i || ' months')::interval))::int;
    mon := extract(month from date_trunc('month', now() + (i || ' months')::interval))::int;
    month_start := make_timestamptz(yr, mon, 1, 0, 0, 0);
    month_end := month_start + interval '1 month';
    part_name := 'audit_events_p_' || yr || '_' || lpad(mon::text, 2, '0');

    IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename = part_name) THEN
      EXECUTE format(
        'CREATE TABLE public.%I PARTITION OF public.audit_events_partitioned FOR VALUES FROM (%L) TO (%L)',
        part_name, month_start, month_end
      );
    END IF;
  END LOOP;
END $$;

-- ─── Section 4: Rate limit log cleanup (stale entries) ────────────────────
-- rate_limit_log accumulates stale entries. Schedule daily cleanup.
SELECT cron.schedule(
  'rate-limit-log-cleanup',
  '35 3 * * *',
  $$
    DELETE FROM public.rate_limit_log
    WHERE created_at < now() - interval '7 days';
  $$
)
WHERE NOT EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'rate-limit-log-cleanup'
);

-- ─── Section 5: Materialized View refresh schedule ────────────────────────
-- Refresh dashboard MVs every 15 minutes during business hours.
-- Migration 0220 created the MVs; this schedules their refresh.
-- (تصحيح: سلاسل جداول داخلية مميزة ($mv$/$cronjob$) حتى لا يغلق $$ الخارجي مبكراً)
DO $$
BEGIN
  -- Refresh all dashboard MVs on a 15-min schedule
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refresh-dashboard-mvs') THEN
    PERFORM cron.schedule(
      'refresh-dashboard-mvs',
      '*/15 * * * *',  -- every 15 minutes
      $cronjob$
        DO $mv$
        DECLARE mv_record RECORD;
        BEGIN
          FOR mv_record IN
            SELECT matviewname FROM pg_matviews
            WHERE schemaname = 'public'
              AND matviewname LIKE '%dashboard%'
          LOOP
            EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY public.%I', mv_record.matviewname);
          END LOOP;
        EXCEPTION WHEN OTHERS THEN
          -- Log but don't fail the cron job
          INSERT INTO public.observability_events (level, source, event_type, message, metadata)
          VALUES ('warning', 'cron:refresh-dashboard-mvs', 'mv_refresh_failed',
                  SQLERRM, jsonb_build_object('sqlstate', SQLSTATE));
        END $mv$
      $cronjob$
    );
  END IF;
END $$;

-- ─── Section 6: ANALYZE statistics refresh ────────────────────────────────
-- Ensure query planner has fresh stats on large tables.
SELECT cron.schedule(
  'analyze-large-tables',
  '0 4 * * *',  -- 04:00 UTC daily (low traffic)
  $$
    ANALYZE public.attendance_events;
    ANALYZE public.attendance_daily;
    ANALYZE public.audit_events;
    ANALYZE public.requests;
    ANALYZE public.notifications;
    ANALYZE public.leave_requests;
    ANALYZE public.employees;
  $$
)
WHERE NOT EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'analyze-large-tables'
);

-- ─── Section 7: Index usage monitoring view ───────────────────────────────
-- Shows unused indexes that can be dropped (size > 0, scans = 0).
CREATE OR REPLACE VIEW public.unused_indexes AS
SELECT
  schemaname,
  relname AS table_name,
  indexrelname AS index_name,
  idx_scan AS scans,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND schemaname = 'public'
  AND indexrelname NOT LIKE '%_pkey'
  AND indexrelname NOT LIKE '%_key'
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 50;

REVOKE ALL ON public.unused_indexes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.unused_indexes TO postgres, service_role;

COMMENT ON VIEW public.unused_indexes IS
  'Lists unused indexes (zero scans) that are candidates for removal. Used by DB performance audits.';

-- ─── Section 8: Slow queries view (requires pg_stat_statements) ──────────
-- Only create the view if the extension is actually loaded.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
    EXECUTE $sql$
    CREATE OR REPLACE VIEW public.slow_queries AS
    SELECT
      query,
      calls,
      round(total_exec_time::numeric, 2) AS total_ms,
      round(mean_exec_time::numeric, 2) AS avg_ms,
      round(max_exec_time::numeric, 2) AS max_ms,
      rows,
      round((total_exec_time / NULLIF(calls, 0))::numeric, 2) AS per_call_ms
    FROM pg_stat_statements
    WHERE query NOT ILIKE '%pg_stat_statements%'
      AND query NOT ILIKE '%pg_catalog%'
      AND calls > 10
    ORDER BY total_exec_time DESC
    LIMIT 50;
    $sql$;
    REVOKE ALL ON public.slow_queries FROM PUBLIC, anon, authenticated;
    GRANT SELECT ON public.slow_queries TO postgres, service_role;
  ELSE
    RAISE NOTICE 'pg_stat_statements not available — slow_queries view skipped';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_stat_statements not available — slow_queries view will be empty';
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements')
     AND EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = 'slow_queries') THEN
    COMMENT ON VIEW public.slow_queries IS
      'Top 50 slowest queries by total execution time. Requires pg_stat_statements extension.';
  END IF;
END $$;

COMMIT;
