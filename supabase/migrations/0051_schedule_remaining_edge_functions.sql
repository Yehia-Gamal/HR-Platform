-- =====================================================================
-- 0051: إكمال جدولة دوال Edge المتبقية عبر pg_net
-- =====================================================================
-- المشكلة (فجوة تشغيلية مؤكّدة):
--   0049 جدول عبر pg_net دالتي Edge فقط:
--     - notification-dispatcher
--     - integration-outbox-worker
--   وبقيت دالتا Edge بلا مشغّل HTTP آلي:
--     - retention-cleanup       → تحذف ملفات فيديو الموقع الحي من Storage
--                                  (خصوصية/احتفاظ). دالة DB في 0047 تنظّف السجلات
--                                  العابرة فقط ولا تلمس ملفات Storage.
--     - scheduled-report-runner → تقرأ طابور التقارير المستحقة وتولّد نتائجها.
--                                  دالة DB queue_due_scheduled_reports في 0047 تضع
--                                  في الطابور فقط ولا تُنتج التقرير.
--   pg_cron وحده لا يستطيع استدعاء HTTP؛ نحتاج pg_net (كما في 0049).
--
-- الحل (idempotent، آمن محليًا):
--   يجدول مهمتي cron تستدعيان الدالتين عبر net.http_post بترويسة x-cron-secret.
--   السر ورابط المشروع يُقرآن من إعدادات قاعدة البيانات (GUC) لا من نص في Git:
--     app.settings.functions_base_url  → https://<ref>.supabase.co/functions/v1
--     app.settings.cron_secret         → قيمة CRON_SECRET
--   إن غاب pg_net/pg_cron أو الإعدادات، تُتجاوز الجدولة دون كسر الترحيل،
--   ويمكن تشغيل الدالتين عبر مشغّل خارجي بنفس الترويسة.
-- =====================================================================

do $net$
declare
  v_has_net boolean;
  v_base    text;
  v_secret  text;
  v_headers jsonb;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_net') into v_has_net;
  if not v_has_net then
    raise notice 'pg_net غير متاح؛ تُشغّل retention-cleanup و scheduled-report-runner عبر مشغّل خارجي بترويسة x-cron-secret.';
    return;
  end if;

  create extension if not exists pg_net;

  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron غير مفعّل؛ تُخطّى جدولة دوال Edge المتبقية.';
    return;
  end if;

  v_base   := current_setting('app.settings.functions_base_url', true);
  v_secret := current_setting('app.settings.cron_secret', true);

  if v_base is null or v_base = '' or v_secret is null or v_secret = '' then
    raise notice 'إعدادات functions_base_url/cron_secret غير مضبوطة؛ تُخطّى جدولة دوال Edge المتبقية. اضبطها ثم أعد تشغيل هذا البلوك.';
    return;
  end if;

  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'x-cron-secret', v_secret
  );

  -- إزالة أي جدولة سابقة بنفس الأسماء (idempotent)
  perform cron.unschedule(jobname)
  from cron.job
  where jobname in ('hr_retention_cleanup_storage', 'hr_scheduled_report_runner');

  -- retention-cleanup: حذف ملفات الفيديو المنتهية من Storage — يوميًا 02:10
  -- (بعد hr_retention_cleanup في 0047 الذي ينظّف السجلات 02:00)
  perform cron.schedule(
    'hr_retention_cleanup_storage', '10 2 * * *',
    format(
      $job$ select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb) $job$,
      v_base || '/retention-cleanup', v_headers
    )
  );

  -- scheduled-report-runner: توليد التقارير المستحقة من الطابور — كل 15 دقيقة
  -- (متزامن مع hr_scheduled_reports في 0047 الذي يملأ الطابور)
  perform cron.schedule(
    'hr_scheduled_report_runner', '*/15 * * * *',
    format(
      $job$ select net.http_post(url := %L, headers := %L::jsonb, body := '{}'::jsonb) $job$,
      v_base || '/scheduled-report-runner', v_headers
    )
  );

  raise notice 'تمت جدولة دوال Edge المتبقية (retention-cleanup + scheduled-report-runner) عبر pg_net.';
end
$net$;

-- =====================================================================
-- نهاية Migration 0051
-- =====================================================================
