-- Test 0109: Database Performance Infrastructure
-- Verifies partitioning, indexes, monitoring views, and cron schedules.

BEGIN;
SELECT plan(10);

-- ─── Partitioned shadow table ────────────────────────────────────────────
SELECT has_table('public', 'audit_events_partitioned', 'audit_events_partitioned table exists');
SELECT has_table('public', 'audit_events_partitioned_default', 'default partition exists');

-- ─── Composite indexes ──────────────────────────────────────────────────
SELECT has_index('public', 'attendance_events', 'idx_attendance_events_employee_date', 'attendance_events employee+date index exists');
SELECT has_index('public', 'audit_events', 'idx_audit_events_created_at_desc', 'audit_events created_at index exists');
SELECT has_index('public', 'notifications', 'idx_notifications_recipient_unread', 'notifications unread index exists');

-- ─── Monitoring views ────────────────────────────────────────────────────
SELECT has_view('public', 'unused_indexes', 'unused_indexes view exists');
SELECT has_view('public', 'slow_queries', 'slow_queries view exists (may be empty without pg_stat_statements)');

-- ─── Cron schedules ──────────────────────────────────────────────────────
SELECT ok(
  EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refresh-dashboard-mvs'),
  'refresh-dashboard-mvs cron job exists'
);

SELECT ok(
  EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'analyze-large-tables'),
  'analyze-large-tables cron job exists'
);

SELECT ok(
  EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rate-limit-log-cleanup'),
  'rate-limit-log-cleanup cron job exists'
);

SELECT * FROM finish();
ROLLBACK;
