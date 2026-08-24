-- =====================================================================
-- 0467: توسيع فاحص صحة الـcron برصد تأخر الطوابير التشغيلية
-- ---------------------------------------------------------------------
-- الوضع السابق: verify_critical_cron_jobs يفحص فقط وجود المهام الحرجة
-- ونشاطها، ولا يلتقط «المهمة موجودة لكنها لا تنجز عملها».
--
-- الإضافات (نمط system_alerts نفسه: فتح/تحديث عند الخلل وحسمه عند العودة):
--   1) notification_dispatch_stalled  (P1): آخر تشغيل ناجح لـ
--      hr_notification_dispatch أقدم من 10 دقائق (تعمل كل دقيقة).
--   2) integration_outbox_lag         (P1): أقدم صف pending/retry في
--      integration_outbox أقدم من 15 دقيقة (العامل يعمل كل 5 دقائق).
--   3) notification_push_failures_spike (P2): تراكم 50+ مهمة push فاشلة
--      خلال آخر 7 أيام (مؤشر انقطاع توكنات FCM أو عطل تسليم).
-- التوقيع والمنح كما هما — CREATE OR REPLACE محافظ.
-- =====================================================================

begin;

create or replace function public.verify_critical_cron_jobs()
 returns table(jobname text, active boolean, last_run timestamptz, last_run_status text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_missing text[];
  v_has_cron boolean;
  v_dispatch_last_success timestamptz;
  v_outbox_oldest_pending timestamptz;
  v_failed_push_7d bigint;
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
     and not public.current_is_full_access()
     and (auth.jwt() ->> 'role') is distinct from 'service_role' then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select exists (
    select 1
    from pg_available_extensions
    where name = 'pg_cron' and installed_version is not null
  ) into v_has_cron;

  if not v_has_cron then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'cron_pg_cron_unavailable', 'P0',
      'pg_cron غير مفعّل في بيئة التشغيل',
      'لا يمكن جدولة المهام الحرجة حتى تفعيل pg_cron أو توثيق بديل خارجي معتمد.',
      'cron', jsonb_build_object('category', 'cron_health'), 'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          occurrences = public.system_alerts.occurrences + 1;
    return;
  end if;

  select array_agg(j.expected_jobname order by j.expected_jobname)
    into v_missing
  from (
    values
      ('hr_request_sla'),
      ('hr_leave_accrual'),
      ('hr_scheduled_reports'),
      ('hr_notification_dispatch'),
      ('hr_integration_outbox'),
      ('hr_retention_cleanup_storage'),
      ('hr_scheduled_report_runner')
  ) as j(expected_jobname)
  where not exists (
    select 1
    from cron.job cj
    where cj.jobname = j.expected_jobname
      and cj.active
  );

  if coalesce(cardinality(v_missing), 0) > 0 then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'cron_critical_jobs_missing', 'P0',
      'مهام cron حرجة غير مجدولة أو غير نشطة',
      'المهام المفقودة: ' || array_to_string(v_missing, ', '),
      'cron',
      jsonb_build_object('category', 'cron_health', 'missingJobs', to_jsonb(v_missing)),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          detail = excluded.detail,
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'cron_critical_jobs_missing' and status = 'open';
  end if;

  -- ── 0467: تأخر ساحب الإشعارات (يعمل كل دقيقة) ──────────────────────────
  select max(d.start_time)
    into v_dispatch_last_success
  from cron.job cj
  join cron.job_run_details d on d.jobid = cj.jobid
  where cj.jobname = 'hr_notification_dispatch'
    and d.status = 'succeeded';

  if coalesce(v_dispatch_last_success, '-infinity'::timestamptz)
       < now() - interval '10 minutes' then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'notification_dispatch_stalled', 'P1',
      'ساحب الإشعارات متوقف عن النجاح',
      'لم يسجّل hr_notification_dispatch أي تشغيل ناجح خلال آخر 10 دقائق؛ إشعارات الطابور قد تتأخر أو تتراكم.',
      'cron',
      jsonb_build_object(
        'category', 'queue_health',
        'lastSuccessAt', to_char(v_dispatch_last_success, 'YYYY-MM-DD"T"HH24:MI:SSOF')
      ),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'notification_dispatch_stalled' and status = 'open';
  end if;

  -- ── 0467: تأخر طابور التكاملات (العامل يعمل كل 5 دقائق) ────────────────
  select min(o.created_at)
    into v_outbox_oldest_pending
  from public.integration_outbox o
  where o.status in ('pending', 'retry');

  if coalesce(v_outbox_oldest_pending, '-infinity'::timestamptz)
       < now() - interval '15 minutes' then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'integration_outbox_lag', 'P1',
      'طابور التكاملات متأخر',
      'توجد صفوف integration_outbox بانتظار المعالجة منذ أكثر من 15 دقيقة — تحقق من worker أو نقطة الاستقبال.',
      'cron',
      jsonb_build_object(
        'category', 'queue_health',
        'oldestPendingAt', to_char(v_outbox_oldest_pending, 'YYYY-MM-DD"T"HH24:MI:SSOF')
      ),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'integration_outbox_lag' and status = 'open';
  end if;

  -- ── 0467: فيض إشعارات push الفاشلة خلال أسبوع ───────────────────────────
  select count(*)
    into v_failed_push_7d
  from public.notification_jobs j
  where j.status = 'failed'
    and j.channel = 'push'
    and j.created_at > now() - interval '7 days';

  if v_failed_push_7d >= 50 then
    insert into public.system_alerts(
      alert_key, severity, title, detail, source, context, status
    ) values (
      'notification_push_failures_spike', 'P2',
      'تراكم إشعارات push فاشلة',
      'فشل ' || v_failed_push_7d::text || ' إشعار push خلال آخر 7 أيام — غالباً غياب توكنات FCM صالحة أو عطل في التسليم.',
      'cron',
      jsonb_build_object('category', 'queue_health', 'failedCount7d', v_failed_push_7d),
      'open'
    )
    on conflict (alert_key) where status = 'open' do update
      set last_seen_at = now(),
          detail = excluded.detail,
          context = excluded.context,
          occurrences = public.system_alerts.occurrences + 1;
  else
    update public.system_alerts
    set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where alert_key = 'notification_push_failures_spike' and status = 'open';
  end if;

  return query
  select
    cj.jobname::text,
    cj.active,
    cr.start_time,
    cr.status::text
  from cron.job cj
  left join lateral (
    select d.start_time, d.status
    from cron.job_run_details d
    where d.jobid = cj.jobid
    order by d.start_time desc
    limit 1
  ) cr on true
  where cj.jobname like 'hr_%'
  order by cj.jobname;
end;
$function$;

commit;
