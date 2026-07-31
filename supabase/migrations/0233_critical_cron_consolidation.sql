-- =====================================================================
-- 0233: جدولة موحدة idempotent للمهام الحرجة + دالة فحص صحي (health)
-- =====================================================================
-- يعيد جدولة جميع مهام cron الحرجة بنمط واحد آمن، مع:
--   1. حارس fail-closed: إن لم يتوفر pg_cron/pg_net يُسجل warning بدل كسر الترحيل.
--   2. إعادة جدولة آمنة (unschedule ثم schedule) — idempotent بالكامل.
--   3. دالة verify_critical_cron_jobs() — تفحص المهام يومياً وتكتب system_alerts.
--   4. مهمة مراقبة ذاتية hr_cron_health_check يومياً 06:00.
-- آمن للـ re-run؛ لا يعدّل بيانات — يدير فقط cron.job.
-- =====================================================================

do $cron_maintenance$
declare
  v_has_cron boolean;
  v_has_pgnet boolean;
  v_url text;
  v_secret text;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_has_cron;
  if not v_has_cron then
    raise warning '[0233] pg_cron غير متاح؛ المهام الحرجة تُشغّل خارجيًا عبر Edge Functions.';
    return;
  end if;

  select exists (select 1 from pg_available_extensions where name = 'pg_net') into v_has_pgnet;

  create extension if not exists pg_cron;
  if v_has_pgnet then
    create extension if not exists pg_net;
  end if;

  -- إزالة المهام السابقة (idempotent)
  perform cron.unschedule(jobname)
  from cron.job
  where jobname in (
    'hr_request_sla','hr_leave_accrual','hr_scheduled_reports',
    'hr_notification_dispatch','hr_integration_outbox',
    'hr_retention_cleanup_storage','hr_scheduled_report_runner',
    'hr_cron_health_check'
  );

  -- مهام قاعدية (RPC مباشر)
  perform cron.schedule('hr_request_sla', '*/10 * * * *',
    $job$ select public.process_request_sla(500); $job$);
  perform cron.schedule('hr_leave_accrual', '30 0 1 * *',
    $job$ select public.run_monthly_leave_accrual(); $job$);
  perform cron.schedule('hr_scheduled_reports', '*/15 * * * *',
    $job$ select public.queue_due_scheduled_reports(); $job$);

  -- مهام Edge Functions عبر pg_net (app.settings.functions_base_url + app.settings.cron_secret)
  if v_has_pgnet then
    v_url    := current_setting('app.settings.functions_base_url', true);
    v_secret := current_setting('app.settings.cron_secret', true);

    if v_url is not null and length(trim(v_url)) > 0
       and v_secret is not null and length(trim(v_secret)) > 0 then
      raise notice '[0233] pg_net مع GUC متاح — جدولة مهام HTTP.';

      perform cron.schedule('hr_notification_dispatch', '* * * * *',
        $j$ select net.http_post(
          url := current_setting('app.settings.functions_base_url', true) || '/notification-dispatcher',
          headers := '{"x-cron-secret": "' || current_setting('app.settings.cron_secret', true) || '"}'::jsonb,
          body := '{"limit": 100}'::jsonb
        ); $j$);

      perform cron.schedule('hr_integration_outbox', '*/5 * * * *',
        $j$ select net.http_post(
          url := current_setting('app.settings.functions_base_url', true) || '/integration-outbox-worker',
          headers := '{"x-cron-secret": "' || current_setting('app.settings.cron_secret', true) || '"}'::jsonb,
          body := '{"limit": 50}'::jsonb
        ); $j$);

      perform cron.schedule('hr_scheduled_report_runner', '*/10 * * * *',
        $j$ select net.http_post(
          url := current_setting('app.settings.functions_base_url', true) || '/scheduled-report-runner',
          headers := '{"x-cron-secret": "' || current_setting('app.settings.cron_secret', true) || '"}'::jsonb,
          body := '{}'::jsonb
        ); $j$);

      perform cron.schedule('hr_retention_cleanup_storage', '0 3 * * *',
        $j$ select net.http_post(
          url := current_setting('app.settings.functions_base_url', true) || '/retention-cleanup',
          headers := '{"x-cron-secret": "' || current_setting('app.settings.cron_secret', true) || '"}'::jsonb,
          body := '{"dry_run": false}'::jsonb
        ); $j$);
    else
      raise warning '[0233] app.settings.functions_base_url/cron_secret غير مضبوطة — مهام HTTP تُجاوزت. عيّنها ثم أعد تشغيل 0233.';
    end if;
  end if;

  -- فحص صحي يومي
  perform cron.schedule('hr_cron_health_check', '0 6 * * *',
    $job$ select public.verify_critical_cron_jobs(); $job$);

  raise notice '[0233] اكتملت الجدولة الموحدة بنجاح.';
end
$cron_maintenance$;

-- =====================================================================
-- دالة التحقق الحرجة — تُستدعى يومياً ومن فحص خارجي
-- =====================================================================
create or replace function public.verify_critical_cron_jobs()
returns table(jobname text, active boolean, last_run timestamptz, last_run_status text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_missing text[];
  v_has_cron boolean;
begin
  if auth.role() <> 'service_role'
     and not public.current_is_full_access()
     and (auth.jwt() ->> 'role') is distinct from 'service_role' then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select exists (
    select 1 from pg_available_extensions
    where name = 'pg_cron' and installed_version is not null
  ) into v_has_cron;

  if not v_has_cron then
    insert into public.system_alerts (alert_key, severity, title, detail, source, first_seen_at, last_seen_at, status)
    values (
      'cron_pg_cron_unavailable','P0',
      'pg_cron غير مفعّل في بيئة الإنتاج',
      'لا يمكن جدولة المهام الحرجة (SLA/Accrual/Reports/Notifications). فعّل pg_cron أو وثّق بديل خارجي معتمد.',
      'cron', now(), now(), 'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(), occurrences = system_alerts.occurrences + 1;
    raise warning 'pg_cron غير مثبت.';
    return;
  end if;

  select array_agg(j.jobname) into v_missing
  from (
    values
      ('hr_request_sla'),('hr_leave_accrual'),('hr_scheduled_reports'),
      ('hr_notification_dispatch'),('hr_integration_outbox'),
      ('hr_retention_cleanup_storage'),('hr_scheduled_report_runner')
  ) as j(jobname)
  where not exists (select 1 from cron.job where jobname = j.jobname);

  if v_missing is not null and array_length(v_missing, 1) > 0 then
    insert into public.system_alerts (alert_key, severity, title, detail, source, first_seen_at, last_seen_at, context, status)
    values (
      'cron_critical_jobs_missing','P0',
      'مهام cron حرجة غير مجدولة',
      'المهام التالية مفقودة من cron.job ويتطلب إعادة تشغيل migration 0233: ' || array_to_string(v_missing, ', '),
      'cron', now(), now(),
      jsonb_build_object('category', 'cron_health', 'missing_jobs', to_jsonb(v_missing)),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(), context = excluded.context, occurrences = system_alerts.occurrences + 1;
    raise warning 'مهام cron غير مجدولة: %', v_missing;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now()
    where alert_key = 'cron_critical_jobs_missing' and status = 'open';
  end if;

  return query
  select
    c.jobname::text,
    c.active,
    cr.start_time as last_run,
    cr.status as last_run_status
  from cron.job c
  left join lateral (
    select start_time, status
    from cron.job_run_details
    where jobid = c.jobid
    order by start_time desc
    limit 1
  ) cr on true
  where c.jobname like 'hr_%'
  order by c.jobname;
end;
$$;

comment on function public.verify_critical_cron_jobs() is
  'تتحقق أن المهام الحرجة مجدولة فعلاً. تكتب system_alerts بنمط idempotent عند الفقد. تُستدعى يوميًا عبر cron.';

revoke all on function public.verify_critical_cron_jobs() from public;
revoke execute on function public.verify_critical_cron_jobs() from anon, authenticated;
grant execute on function public.verify_critical_cron_jobs() to service_role;

-- نهاية Migration 0233
