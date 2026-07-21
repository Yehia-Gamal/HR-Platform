-- 0033: Observability & alerting runtime proof (migration 0054).
-- Proves the monitoring layer works at runtime: table + RLS, function gating,
-- alert detection with dedup, and occurrence counting. Runs in a transaction
-- and rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(11);

-- ── structure ────────────────────────────────────────────────────────────
select has_table('public','system_alerts','system_alerts table exists');
select has_column('public','system_alerts','alert_key','alert_key column exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.system_alerts'::regclass),
  'RLS is enabled on system_alerts');

-- ── function gating ──────────────────────────────────────────────────────
select has_function('public','get_system_health', array[]::text[],
  'get_system_health() exists');
select has_function('public','detect_and_raise_alerts', array[]::text[],
  'detect_and_raise_alerts() exists');
select ok(
  not has_function_privilege('authenticated',
    'public.detect_and_raise_alerts()','EXECUTE'),
  'authenticated cannot run the detector directly (server-only)');
select function_privs_are('public','detect_and_raise_alerts', array[]::text[],
  'service_role', array['EXECUTE'],
  'detector runnable by service_role');

-- seed a fatal error (as table owner in the test tx)
insert into public.app_error_events (level, source, message, environment, occurred_at)
  values ('fatal','server','test fatal for monitor','test', now());

-- baseline: no fatal alert yet
select is(
  (select count(*)::int from public.system_alerts where alert_key = 'errors_fatal' and status='open'),
  0, 'no fatal alert before first scan');

-- simulate service_role context (auth.role() reads request.jwt.claims) and run detector.
-- The detector is SECURITY DEFINER (owner=postgres), so its writes bypass RLS.
do $run$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.detect_and_raise_alerts();  -- scan 1
  perform public.detect_and_raise_alerts();  -- scan 2 (must dedup)
  perform set_config('request.jwt.claims', '', true);
end $run$;

-- exactly one open alert for the fatal key (dedup held across 2 scans)
select is(
  (select count(*)::int from public.system_alerts where alert_key = 'errors_fatal' and status='open'),
  1, 'repeated scans dedup into a single open alert');

select ok(
  (select occurrences from public.system_alerts where alert_key='errors_fatal' and status='open') >= 2,
  'occurrences increments on repeat detection');

-- get_system_health returns a jsonb object with the expected keys (as service_role)
create temporary table _health on commit drop as
  select public.get_system_health() as v
  from (select set_config('request.jwt.claims', '{"role":"service_role"}', true)) _;
select set_config('request.jwt.claims', '', true);

select ok(
  (select v ? 'open_alerts' and v ? 'errors' and v ? 'integration_queue' from _health),
  'get_system_health returns a structured snapshot');

select * from finish();
rollback;
