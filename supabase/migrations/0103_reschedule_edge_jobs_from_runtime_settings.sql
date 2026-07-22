-- Migration 0103: schedule the production Edge workers after the runtime URL
-- and cron secret have been provisioned as database settings.

do $schedule$
declare
  v_base text := current_setting('app.settings.functions_base_url', true);
  v_secret text := current_setting('app.settings.cron_secret', true);
  v_headers jsonb;
  v_job text;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'pg_cron/pg_net unavailable; Edge jobs were not scheduled.';
    return;
  end if;

  if coalesce(v_base, '') = '' or coalesce(v_secret, '') = '' then
    raise notice 'Edge runtime URL or cron secret is unset; jobs were not scheduled.';
    return;
  end if;

  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'x-cron-secret', v_secret
  );

  foreach v_job in array array[
    'hr_notification_dispatch',
    'hr_integration_outbox',
    'hr_retention_cleanup_storage',
    'hr_scheduled_report_runner'
  ] loop
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = v_job;
  end loop;

  perform cron.schedule(
    'hr_notification_dispatch',
    '*/2 * * * *',
    format(
      $job$select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb)$job$,
      rtrim(v_base, '/') || '/notification-dispatcher',
      v_headers
    )
  );

  perform cron.schedule(
    'hr_integration_outbox',
    '*/2 * * * *',
    format(
      $job$select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb)$job$,
      rtrim(v_base, '/') || '/integration-outbox-worker',
      v_headers
    )
  );

  perform cron.schedule(
    'hr_retention_cleanup_storage',
    '10 2 * * *',
    format(
      $job$select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb)$job$,
      rtrim(v_base, '/') || '/retention-cleanup',
      v_headers
    )
  );

  perform cron.schedule(
    'hr_scheduled_report_runner',
    '*/15 * * * *',
    format(
      $job$select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb)$job$,
      rtrim(v_base, '/') || '/scheduled-report-runner',
      v_headers
    )
  );
end
$schedule$;
