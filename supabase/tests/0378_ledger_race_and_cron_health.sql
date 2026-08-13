begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(6);

-- Migration 0380: apply_leave_ledger_entry has advisory lock
select alike(
  (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='apply_leave_ledger_entry' limit 1),
  '%pg_advisory_xact_lock%',
  'apply_leave_ledger_entry should use advisory lock'
);

-- Migration 0380: consume branch checks reserved_units
select alike(
  (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='apply_leave_ledger_entry' limit 1),
  '%CONSUME_EXCEEDS_RESERVE%',
  'consume branch should guard against exceeding reserved units'
);

-- Migration 0381: cron_health_log table exists
select has_table('public', 'cron_health_log', 'cron_health_log table should exist');

-- Migration 0381: get_cron_health function exists
select has_function('public', 'get_cron_health', 'get_cron_health RPC should exist');

-- Migration 0381: process_request_sla logs to cron_health_log
select alike(
  (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='process_request_sla'),
  '%cron_health_log%',
  'process_request_sla should write to cron_health_log'
);

-- Migration 0380: idempotency uses found check (no 5s window)
select alike(
  (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='apply_leave_ledger_entry' limit 1),
  '%if found then%',
  'idempotency should use SELECT-based check not on conflict 5s window'
);

select finish();
rollback;
