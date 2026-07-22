-- =====================================================================
-- 0049: جدولة استدعاء دوال Edge عبر pg_net (notification + integration)
-- =====================================================================
-- المشكلة:
--   Migration 0047 جدول 4 مهام pg_cron تستدعي دوال قاعدة البيانات مباشرة،
--   لكن دالتين من نوع Edge Function تحتاجان استدعاء HTTP بترويسة x-cron-secret:
--     - notification-dispatcher  (إرسال الإشعارات المعلّقة)
--     - integration-outbox-worker (تسليم طابور التكامل الخارجي)
--   pg_cron وحده لا يستطيع استدعاء HTTP؛ نحتاج pg_net.
--
-- الحل (idempotent، آمن محليًا):
--   1) تفعيل pg_net إن توفّر (على Supabase المُدار متاح؛ محليًا قد يغيب فنتخطى).
--   2) جدولة مهمتي cron تستدعيان الدالتين عبر net.http_post كل دقيقتين.
--   3) السر ورابط المشروع يُقرآن من إعدادات قاعدة البيانات (GUC) وليس من نص
--      مكتوب داخل الترحيل:
--        app.settings.functions_base_url  → https://<ref>.supabase.co/functions/v1
--        app.settings.cron_secret         → قيمة CRON_SECRET
--      تُضبط عبر: alter database ... set app.settings.cron_secret = '...';
--      (لا تُوضع الأسرار في Git).
--   إن غابت الإعدادات أو غاب pg_net، تُتجاوز الجدولة دون كسر الترحيل، ويمكن
--   تشغيل الدالتين عبر مشغّل خارجي بنفس الترويسة.
-- =====================================================================

do $net$
declare
  v_has_net   boolean;
  v_base      text;
  v_secret    text;
  v_headers   jsonb;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_net') into v_has_net;
  if not v_has_net then
    raise notice 'pg_net غير متاح؛ تُشغّل دوال Edge عبر مشغّل خارجي بترويسة x-cron-secret.';
    return;
  end if;

  create extension if not exists pg_net;

  -- تأكّد من توفّر pg_cron أيضًا (0047)؛ إن غاب فلا شيء لنجدوله هنا
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron غير مفعّل؛ تُخطّى جدولة دوال Edge.';
    return;
  end if;

  v_base   := current_setting('app.settings.functions_base_url', true);
  v_secret := current_setting('app.settings.cron_secret', true);

  if v_base is null or v_base = '' or v_secret is null or v_secret = '' then
    raise notice 'إعدادات functions_base_url/cron_secret غير مضبوطة؛ تُخطّى جدولة دوال Edge. اضبطها ثم أعد تشغيل هذا البلوك.';
    return;
  end if;

  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'x-cron-secret', v_secret
  );

  -- إزالة أي جدولة سابقة بنفس الأسماء (idempotent)
  perform cron.unschedule(jobname)
  from cron.job
  where jobname in ('hr_notification_dispatch', 'hr_integration_outbox');

  -- notification-dispatcher: كل دقيقتين
  perform cron.schedule(
    'hr_notification_dispatch', '*/2 * * * *',
    format(
      $job$ select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb) $job$,
      v_base || '/notification-dispatcher', v_headers
    )
  );

  -- integration-outbox-worker: كل دقيقتين
  perform cron.schedule(
    'hr_integration_outbox', '*/2 * * * *',
    format(
      $job$ select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb) $job$,
      v_base || '/integration-outbox-worker', v_headers
    )
  );

  raise notice 'تمت جدولة مهمتي Edge (notification-dispatcher + integration-outbox-worker) عبر pg_net.';
end
$net$;

-- =====================================================================
-- نهاية Migration 0049
-- =====================================================================
