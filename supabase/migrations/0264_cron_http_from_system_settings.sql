-- =====================================================================
-- 0264: مهام cron HTTP تقرأ من system_settings بدل custom GUC
-- =====================================================================
-- على Supabase المدارة لا يمكن ضبط custom GUCs (app.settings.*) لأن
-- postgres ليس superuser (permission denied to set parameter). لذلك
-- تُحفظ قيمتا cron في public.system_settings وتُقرأ وقت تشغيل المهمة،
-- فيبقى تدوير السر مجرد UPDATE لصف دون إعادة جدولة، ومتطابقاً مع سر
-- Edge عبر x-cron-secret.
--
-- cron_secret يُزرع placeholder ولا يُستبدل إن وُجدت قيمة فعلية.
-- للبيئات الجديدة بعد تطبيق المهاجرة:
--   update public.system_settings
--      set value = '"<secret>"'::jsonb
--    where key = 'cron_secret';
-- ثم زامن سر Edge:
--   npx supabase secrets set CRON_SECRET=<secret> --project-ref <ref>
-- =====================================================================

insert into public.system_settings(key, value, value_type, group_name, label_ar, description, is_secret, is_editable)
values
  ('cron_functions_base_url',
   '"https://ujzzvqsodyhnnnpkoaml.supabase.co/functions/v1"'::jsonb,
   'string', 'cron', 'رابط دوال Edge',
   'أساس روابط دوال Edge لمهام cron عبر pg_net.', false, true),
  ('cron_secret',
   '"__REPLACE_ME__"'::jsonb,
   'string', 'cron', 'سر مهام cron',
   'قيمة ترويسة x-cron-secret المطابقة لسر Edge CRON_SECRET.', true, true)
on conflict (key) do update
  set group_name = excluded.group_name,
      description = excluded.description,
      value_type = excluded.value_type,
      is_secret = excluded.is_secret,
      is_editable = excluded.is_editable
  -- لا نستبدل قيمة cron_secret إن كانت غير placeholder (قد تكون حقيقية)
  where excluded.key = 'cron_functions_base_url'
     or public.system_settings.value = '"__REPLACE_ME__"'::jsonb;

do $cron_settings$
declare
  v_has_cron  boolean;
  v_has_pgnet boolean;
  v_url       text;
  v_secret    text;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_has_cron;
  if not v_has_cron then
    raise warning '[0264] pg_cron غير متاح؛ مهام HTTP لم تُجدول.';
    return;
  end if;

  select exists (select 1 from pg_available_extensions where name = 'pg_net') into v_has_pgnet;
  if not v_has_pgnet then
    raise warning '[0264] pg_net غير متاح؛ مهام HTTP تُجاوزت.';
    return;
  end if;

  select value #>> '{}' from public.system_settings where key = 'cron_functions_base_url' into v_url;
  select value #>> '{}' from public.system_settings where key = 'cron_secret' into v_secret;

  if v_url is null or v_secret is null or v_secret = '__REPLACE_ME__' then
    raise warning '[0264] cron_secret ما زال placeholder؛ المهام ستُجدول لكن نداءاتها ستفشل 401 حتى يُعيّن السر.';
  else
    raise notice '[0264] cron_secret مضبوط؛ المهام جاهزة.';
  end if;

  perform cron.schedule('hr_notification_dispatch', '* * * * *',
    $j$ select net.http_post(
      url := (select value #>> '{}' from public.system_settings where key = 'cron_functions_base_url') || '/notification-dispatcher',
      headers := jsonb_build_object('x-cron-secret', (select value #>> '{}' from public.system_settings where key = 'cron_secret')),
      body := '{"limit": 100}'::jsonb
    ); $j$);

  perform cron.schedule('hr_integration_outbox', '*/5 * * * *',
    $j$ select net.http_post(
      url := (select value #>> '{}' from public.system_settings where key = 'cron_functions_base_url') || '/integration-outbox-worker',
      headers := jsonb_build_object('x-cron-secret', (select value #>> '{}' from public.system_settings where key = 'cron_secret')),
      body := '{"limit": 50}'::jsonb
    ); $j$);

  perform cron.schedule('hr_scheduled_report_runner', '*/10 * * * *',
    $j$ select net.http_post(
      url := (select value #>> '{}' from public.system_settings where key = 'cron_functions_base_url') || '/scheduled-report-runner',
      headers := jsonb_build_object('x-cron-secret', (select value #>> '{}' from public.system_settings where key = 'cron_secret')),
      body := '{}'::jsonb
    ); $j$);

  perform cron.schedule('hr_retention_cleanup_storage', '0 3 * * *',
    $j$ select net.http_post(
      url := (select value #>> '{}' from public.system_settings where key = 'cron_functions_base_url') || '/retention-cleanup',
      headers := jsonb_build_object('x-cron-secret', (select value #>> '{}' from public.system_settings where key = 'cron_secret')),
      body := '{"dry_run": false}'::jsonb
    ); $j$);
end;
$cron_settings$;
