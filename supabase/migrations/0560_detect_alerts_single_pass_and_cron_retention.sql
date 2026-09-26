-- =====================================================================
-- 0560: أكبر مستهلك لقاعدة البيانات — detect_and_raise_alerts
--
-- pg_stat_statements: هذه الدالة (cron كل 5 دقائق) استهلكت 48,602 ثانية
-- (~13.5 ساعة) — أكثر من كل الاستعلامات الأخرى مجتمعة؛ متوسط 2.3ث وأقصى 52ث.
--
-- القياس على الإنتاج: 1,269ms للدالة كاملة، منها ~1,100ms لفحص «فشل المهام
-- المجدولة»: LATERAL يمسح cron.job_run_details كاملاً (149,779 صفاً، 59MB، بلا
-- فهرس على jobid) مرة لكل مهمة. لا نستطيع فهرسته (ملك supabase_admin).
--
-- 1) إعادة إنشاء كنونية من 0483 (تحقّقنا: جسمها يطابق الإنتاج حرفياً) مع:
--    • مسح واحد DISTINCT ON بدل LATERAL لكل مهمة: 1,074ms → 299ms، نتيجة مطابقة.
--    • سجل التدقيق فقط عند رصد حالة (v_raised > 0).
-- 2) مهمة يومية تحذف سجلات cron.job_run_details الأقدم من 14 يوماً (توصية
--    Supabase؛ الجدول ينمو بلا حد — 80,720 صفاً أقدم من 14 يوماً الآن):
--    بعدها 202ms. سجلات التدقيق القديمة في audit_events لا تُحذف.
-- =====================================================================

begin;

create or replace function public.detect_and_raise_alerts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_raised integer := 0;
  v_val    numeric;
  v_rec    record;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- 4.1 [P0] طابور تكامل Dead-letter > 0
  select dead_letter into v_val from public.v_monitor_integration_queue;
  if coalesce(v_val,0) > 0 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('queue_dead_letter', 'P0', 'queue',
            'رسائل تكامل في Dead-letter',
            format('%s رسالة في dead_letter تحتاج تدخلًا يدويًا', v_val),
            v_val, 0, jsonb_build_object('table','integration_outbox'))
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.2 [P1] طابور تكامل failed متأخر (overdue > 20)
  select overdue into v_val from public.v_monitor_integration_queue;
  if coalesce(v_val,0) > 20 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('queue_overdue', 'P1', 'queue',
            'طابور تكامل متأخر عن المعالجة',
            format('%s رسالة تجاوزت موعد إعادة المحاولة بـ15 دقيقة', v_val),
            v_val, 20, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.3 [P0] أخطاء fatal في آخر ساعة
  select fatal_1h into v_val from public.v_monitor_errors;
  if coalesce(v_val,0) > 0 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('errors_fatal', 'P0', 'error',
            'أخطاء fatal في التطبيق',
            format('%s خطأ fatal خلال الساعة الأخيرة', v_val),
            v_val, 0, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.4 [P1] ارتفاع الأخطاء (error+ > 50/ساعة)
  select errors_1h into v_val from public.v_monitor_errors;
  if coalesce(v_val,0) > 50 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('errors_spike', 'P1', 'error',
            'ارتفاع معدّل الأخطاء',
            format('%s خطأ خلال الساعة الأخيرة (الحد 50)', v_val),
            v_val, 50, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.5 [P0] أحداث أمنية حرجة في آخر ساعة
  select critical_1h into v_val from public.v_monitor_security;
  if coalesce(v_val,0) > 0 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('security_critical', 'P0', 'security',
            'أحداث أمنية حرجة',
            format('%s حدث أمني بخطورة critical خلال الساعة الأخيرة', v_val),
            v_val, 0, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.6 [P1] إشعارات عالقة (queued > 30 دقيقة)
  select stuck into v_val from public.v_monitor_notifications;
  if coalesce(v_val,0) > 0 then
    insert into public.system_alerts as a
      (alert_key, severity, source, title, detail, metric_value, threshold, context)
    values ('notifications_stuck', 'P1', 'notification',
            'إشعارات عالقة في الطابور',
            format('%s إشعار في حالة queued لأكثر من 30 دقيقة', v_val),
            v_val, 0, '{}'::jsonb)
    on conflict (alert_key) where status = 'open'
    do update set last_seen_at = now(), occurrences = a.occurrences + 1,
                  metric_value = excluded.metric_value;
    v_raised := v_raised + 1;
  end if;

  -- 4.7 [P1] فشل مهام cron (آخر تشغيل failed) — إن توفّر cron
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      -- مسح واحد للجدول بدل مسح كامل لكل مهمة: cron.job_run_details بلا فهرس
      -- على jobid (ملكه supabase_admin فلا نستطيع فهرسته) — كان هذا الجزء وحده
      -- ~90% من زمن الدالة (1.1ث من 1.27ث). النتيجة مطابقة (تحقّقنا على الإنتاج).
      for v_rec in
        select j.jobname, d.status
        from (
          select distinct on (r.jobid) r.jobid, r.status
          from cron.job_run_details r
          order by r.jobid, r.start_time desc
        ) d
        join cron.job j on j.jobid = d.jobid
        where d.status = 'failed'
      loop
        insert into public.system_alerts as a
          (alert_key, severity, source, title, detail, context)
        values ('cron_failed:'||v_rec.jobname, 'P1', 'cron',
                'فشل مهمة مجدولة: '||v_rec.jobname,
                'آخر تشغيل للمهمة انتهى بحالة failed', jsonb_build_object('job', v_rec.jobname))
        on conflict (alert_key) where status = 'open'
        do update set last_seen_at = now(), occurrences = a.occurrences + 1;
        v_raised := v_raised + 1;
      end loop;
    exception
      when insufficient_privilege or undefined_table then
        null;  -- لا صلاحية cron.* في هذا الدور — نتجاوز بأمان فقط لهذه الحالة
      -- أي خطأ آخر (فشل كتابة/قفل/timeout) يُترك ليُطرح: لا نُخفي فشل التنبيهات كنجاح
    end;
  end if;

  -- سجل تشغيل الكاشف نفسه (تدقيق) — فقط عند رصد حالة: كل 5 دقائق بلا نتائج
  -- كانت 90% من audit_events (21,038 من 23,307، منها 427 فقط برصد فعلي)
  -- فتغمر أحداث التدقيق الحقيقية. تشغيل المهمة نفسه مسجَّل في cron.job_run_details.
  if v_raised > 0 then
  perform public.log_audit_event(
    'monitor.alerts.scan', 'system', 'info', 'system_alerts', null,
    'فحص التنبيهات الآلي', format('رُصدت/حُدِّثت %s حالة', v_raised),
    jsonb_build_object('raised', v_raised));
  end if;

  return v_raised;
end $$;

-- إعادة تثبيت المنح بعد CREATE OR REPLACE (للاحتياط؛ لا تتغير عادةً)
revoke execute on function public.detect_and_raise_alerts() from public, anon;

do $sched$
begin
  if exists (select 1 from cron.job where jobname = 'cron_run_details_retention') then
    perform cron.unschedule('cron_run_details_retention');
  end if;
  perform cron.schedule(
    'cron_run_details_retention',
    '17 1 * * *',  -- 04:17 بتوقيت القاهرة، خارج ساعات العمل
    $job$delete from cron.job_run_details where end_time < now() - interval '14 days'$job$
  );
end
$sched$;

commit;
