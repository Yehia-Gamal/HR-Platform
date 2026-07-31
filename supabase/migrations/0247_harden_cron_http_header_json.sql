-- =====================================================================
-- 0247: تقوية بناء ترويسة x-cron-secret لمهام HTTP cron
-- =====================================================================
-- في 0233 كانت ترويسة الطلب تُبنى بدمج نصي:
--   headers := '{"x-cron-secret": "' || current_setting(...) || '"}'::jsonb
-- إن احتوى السر على " أو \ ينكسر JSON أو يُحقن في الترويسة.
-- الإصلاح: إعادة جدولة المهام الأربع باستخدام jsonb_build_object الذي
-- يهرّب المحارف الخاصة بأمان. idempotent وآمن لإعادة التشغيل؛ لا يعدّل بيانات.
-- =====================================================================

do $cron_header_hardening$
declare
  v_has_cron  boolean;
  v_has_pgnet boolean;
  v_url       text;
  v_secret    text;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_has_cron;
  if not v_has_cron then
    raise warning '[0247] pg_cron غير متاح؛ لا مهام HTTP لإعادة جدولتها.';
    return;
  end if;

  select exists (select 1 from pg_available_extensions where name = 'pg_net') into v_has_pgnet;
  if not v_has_pgnet then
    raise warning '[0247] pg_net غير متاح؛ مهام HTTP تُجاوزت.';
    return;
  end if;

  v_url    := nullif(trim(current_setting('app.settings.functions_base_url', true)), '');
  v_secret := nullif(trim(current_setting('app.settings.cron_secret', true)), '');

  if v_url is null or v_secret is null then
    raise warning '[0247] functions_base_url/cron_secret غير مضبوطة — مهام HTTP لم تُعد جدولتها.';
    return;
  end if;

  raise notice '[0247] إعادة جدولة مهام HTTP cron بترويسة JSON آمنة.';

  perform cron.schedule('hr_notification_dispatch', '* * * * *',
    $j$ select net.http_post(
      url := current_setting('app.settings.functions_base_url', true) || '/notification-dispatcher',
      headers := jsonb_build_object('x-cron-secret', current_setting('app.settings.cron_secret', true)),
      body := '{"limit": 100}'::jsonb
    ); $j$);

  perform cron.schedule('hr_integration_outbox', '*/5 * * * *',
    $j$ select net.http_post(
      url := current_setting('app.settings.functions_base_url', true) || '/integration-outbox-worker',
      headers := jsonb_build_object('x-cron-secret', current_setting('app.settings.cron_secret', true)),
      body := '{"limit": 50}'::jsonb
    ); $j$);

  perform cron.schedule('hr_scheduled_report_runner', '*/10 * * * *',
    $j$ select net.http_post(
      url := current_setting('app.settings.functions_base_url', true) || '/scheduled-report-runner',
      headers := jsonb_build_object('x-cron-secret', current_setting('app.settings.cron_secret', true)),
      body := '{}'::jsonb
    ); $j$);

  perform cron.schedule('hr_retention_cleanup_storage', '0 3 * * *',
    $j$ select net.http_post(
      url := current_setting('app.settings.functions_base_url', true) || '/retention-cleanup',
      headers := jsonb_build_object('x-cron-secret', current_setting('app.settings.cron_secret', true)),
      body := '{"dry_run": false}'::jsonb
    ); $j$);
end;
$cron_header_hardening$;
