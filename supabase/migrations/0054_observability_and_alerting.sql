-- =====================================================================
-- 0051: طبقة المراقبة والتنبيهات (Observability & Alerting) — P1.7
-- =====================================================================
-- الهدف (من الخطة P1.7): سجلّات مهيكلة، أخطاء/كمون الدوال، طوابير
-- Dead-letter، حالة تسليم الإشعارات، أحداث أمنية، وتنبيهات للـ P0/P1 فقط
-- دون Spam. يبني على الجداول القائمة (app_error_events, security_events,
-- integration_outbox, notification_delivery_log) ولا يكرّرها.
--
-- المكوّنات:
--   1) جدول system_alerts (تنبيهات مُلتقطة، dedup عبر alert_key + نافذة).
--   2) عروض مراقبة (health snapshots) للـ full_access فقط عبر RLS.
--   3) get_system_health() — لقطة P0/P1 واحدة (service_role/full_access).
--   4) detect_and_raise_alerts() — يفحص الشذوذ ويكتب system_alerts (idempotent).
--   5) جدولة pg_cron كل 5 دقائق (حارس آمن محليًا).
-- كل الكتابة عبر SECURITY DEFINER؛ RLS يمنع الوصول المباشر لغير المصرّح.
-- =====================================================================

-- =====================================================================
-- 1) جدول التنبيهات
-- =====================================================================
create table if not exists public.system_alerts (
  id            uuid primary key default gen_random_uuid(),
  alert_key     text not null,                       -- مفتاح منطقي للـ dedup (مثال: cron_failed:hr_request_sla)
  severity      text not null default 'P1'
                  check (severity in ('P0','P1')),   -- P0/P1 فقط — لا Spam
  source        text not null default 'monitor'
                  check (source in ('monitor','cron','queue','notification','security','error','storage')),
  title         text not null,
  detail        text,
  metric_value  numeric,
  threshold     numeric,
  status        text not null default 'open'
                  check (status in ('open','acknowledged','resolved')),
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  occurrences   integer not null default 1 check (occurrences >= 1),
  acknowledged_by uuid references auth.users(id) on delete set null,
  acknowledged_at timestamptz,
  resolved_at   timestamptz,
  context       jsonb not null default '{}'::jsonb
);

comment on table public.system_alerts is
  'تنبيهات المراقبة (P0/P1 فقط). dedup: تنبيه مفتوح بنفس alert_key يُحدَّث (occurrences++/last_seen) بدل تكرار صف.';

-- فهرس فريد جزئي: تنبيه واحد "مفتوح" لكل alert_key (يمنع Spam)
create unique index if not exists ux_system_alerts_open_key
  on public.system_alerts(alert_key) where status = 'open';
create index if not exists ix_system_alerts_status_seen
  on public.system_alerts(status, last_seen_at desc);

alter table public.system_alerts enable row level security;

-- قراءة: full_access أو صاحب صلاحية مراقبة النظام فقط
drop policy if exists system_alerts_read on public.system_alerts;
create policy system_alerts_read on public.system_alerts
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['system.release.read','system.release.manage'])
  );

-- تحديث (acknowledge/resolve): نفس الصلاحية
drop policy if exists system_alerts_update on public.system_alerts;
create policy system_alerts_update on public.system_alerts
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['system.release.manage'])
  )
  with check (
    public.current_is_full_access()
    or public.has_any_permission(array['system.release.manage'])
  );

-- لا INSERT/DELETE مباشر — الكتابة عبر detect_and_raise_alerts() فقط (DEFINER)
revoke insert, delete on public.system_alerts from authenticated, anon;

-- =====================================================================
-- 2) عروض المراقبة (health snapshots)
-- =====================================================================

-- 2.1 حالة طوابير التكامل (dead-letter/failed/pending)
create or replace view public.v_monitor_integration_queue
with (security_invoker = true) as
  select
    count(*) filter (where status in ('pending','retrying'))       as pending,
    count(*) filter (where status = 'processing')                  as processing,
    count(*) filter (where status in ('failed','dead_letter'))     as failed,
    count(*) filter (where status = 'dead_letter')                 as dead_letter,
    count(*) filter (where status in ('pending','retrying')
                     and next_attempt_at < now() - interval '15 minutes') as overdue,
    max(attempts)                                                  as max_attempts_seen
  from public.integration_outbox;

-- 2.2 حالة تسليم الإشعارات (آخر ساعة)
create or replace view public.v_monitor_notifications
with (security_invoker = true) as
  select
    count(*) filter (where status = 'queued')                      as queued,
    count(*) filter (where status in ('sent','delivered'))         as delivered,
    count(*) filter (where status in ('failed','bounced'))         as failed,
    count(*) filter (where status = 'queued'
                     and created_at < now() - interval '30 minutes') as stuck
  from public.notification_delivery_log
  where created_at > now() - interval '24 hours';

-- 2.3 معدّل الأخطاء (آخر ساعة) حسب المستوى
create or replace view public.v_monitor_errors
with (security_invoker = true) as
  select
    count(*) filter (where level in ('error','fatal'))            as errors_1h,
    count(*) filter (where level = 'fatal')                       as fatal_1h,
    count(*) filter (where level = 'warning')                     as warnings_1h
  from public.app_error_events
  where occurred_at > now() - interval '1 hour';

-- 2.4 أحداث أمنية عالية الخطورة (آخر ساعة)
create or replace view public.v_monitor_security
with (security_invoker = true) as
  select
    count(*) filter (where severity in ('high','critical'))       as high_sev_1h,
    count(*) filter (where severity = 'critical')                 as critical_1h
  from public.security_events
  where occurred_at > now() - interval '1 hour';

-- least-privilege backstop: 0045 منح SELECT افتراضيًا لـ anon/authenticated على
-- كل الجداول/العروض اللاحقة. هذه العروض للمراقبة فقط — تُقرأ عبر get_system_health()
-- (DEFINER بمالك postgres) أو full_access. نسحب المنح الموروثة ونمنح service_role فقط.
revoke select on
  public.v_monitor_integration_queue,
  public.v_monitor_notifications,
  public.v_monitor_errors,
  public.v_monitor_security
from anon, authenticated;
grant select on
  public.v_monitor_integration_queue,
  public.v_monitor_notifications,
  public.v_monitor_errors,
  public.v_monitor_security
to service_role;

-- =====================================================================
-- 3) get_system_health() — لقطة واحدة
-- =====================================================================
create or replace function public.get_system_health()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_out       jsonb;
  v_cron      jsonb := '[]'::jsonb;
  v_has_cron  boolean;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access()
     and not public.has_any_permission(array['system.release.read','system.release.manage']) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- صحة pg_cron (إن وُجدت) — آخر تشغيل لكل مهمة
  select exists (select 1 from pg_extension where extname = 'pg_cron') into v_has_cron;
  if v_has_cron then
    begin
      select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_cron
      from (
        select j.jobname,
               d.status        as last_status,
               d.start_time    as last_run
        from cron.job j
        left join lateral (
          select status, start_time
          from cron.job_run_details r
          where r.jobid = j.jobid
          order by start_time desc
          limit 1
        ) d on true
        order by j.jobname
      ) t;
    exception
      when insufficient_privilege or undefined_table then
        v_cron := '[]'::jsonb;  -- لا صلاحية على cron.* في بعض الأدوار — فارغ صحيح
      when others then
        -- خطأ حقيقي (timeout/تغيّر مخطط) — لا نُخفيه كـ"لا مهام"، بل نُبرزه
        v_cron := jsonb_build_object('cron_error', sqlerrm);
    end;
  end if;

  v_out := jsonb_build_object(
    'generated_at', now(),
    'cron', v_cron,
    'integration_queue', (select row_to_json(q) from public.v_monitor_integration_queue q),
    'notifications',     (select row_to_json(n) from public.v_monitor_notifications n),
    'errors',            (select row_to_json(e) from public.v_monitor_errors e),
    'security',          (select row_to_json(s) from public.v_monitor_security s),
    'open_alerts', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'severity', severity, 'title', title, 'alert_key', alert_key,
        'occurrences', occurrences, 'last_seen_at', last_seen_at)), '[]'::jsonb)
      from public.system_alerts where status = 'open'
    )
  );
  return v_out;
end $$;

comment on function public.get_system_health() is
  'لقطة صحة النظام (cron/queues/errors/security/alerts). service_role أو full_access أو system.release.read.';

revoke execute on function public.get_system_health() from public, anon;
grant execute on function public.get_system_health() to authenticated, service_role;

-- =====================================================================
-- 4) detect_and_raise_alerts() — كاشف الشذوذ (يكتب system_alerts)
-- =====================================================================
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
      for v_rec in
        select j.jobname, d.status
        from cron.job j
        join lateral (
          select status from cron.job_run_details r
          where r.jobid = j.jobid order by start_time desc limit 1
        ) d on true
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

  -- سجل تشغيل الكاشف نفسه (تدقيق)
  perform public.log_audit_event(
    'monitor.alerts.scan', 'system', 'info', 'system_alerts', null,
    'فحص التنبيهات الآلي', format('رُصدت/حُدِّثت %s حالة', v_raised),
    jsonb_build_object('raised', v_raised));

  return v_raised;
end $$;

comment on function public.detect_and_raise_alerts() is
  'server-authored: يفحص شذوذ النظام ويكتب system_alerts (P0/P1، dedup عبر alert_key المفتوح). service_role/full_access.';

revoke execute on function public.detect_and_raise_alerts() from public, anon, authenticated;
grant execute on function public.detect_and_raise_alerts() to service_role;

-- =====================================================================
-- 5) resolve_stale_alerts() — يُغلق التنبيهات المفتوحة التي لم تُرَ مؤخرًا
-- =====================================================================
create or replace function public.resolve_stale_alerts(p_stale_minutes integer default 30)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_n integer;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  update public.system_alerts
     set status = 'resolved', resolved_at = now()
   where status = 'open'
     and last_seen_at < now() - make_interval(mins => greatest(5, p_stale_minutes));
  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function public.resolve_stale_alerts(integer) is
  'يغلق التنبيهات المفتوحة التي لم تُرصَد منذ p_stale_minutes (الحالة تعافت). service_role/full_access.';

revoke execute on function public.resolve_stale_alerts(integer) from public, anon, authenticated;
grant execute on function public.resolve_stale_alerts(integer) to service_role;

-- =====================================================================
-- 6) جدولة الكاشف عبر pg_cron (حارس آمن محليًا)
-- =====================================================================
do $mon$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'pg_cron غير متاح؛ يُشغّل detect_and_raise_alerts عبر مشغّل خارجي.';
    return;
  end if;
  create extension if not exists pg_cron;

  perform cron.unschedule(jobname) from cron.job
   where jobname in ('hr_monitor_alerts','hr_monitor_resolve');

  -- فحص التنبيهات كل 5 دقائق
  perform cron.schedule('hr_monitor_alerts', '*/5 * * * *',
    $job$ select public.detect_and_raise_alerts(); $job$);

  -- إغلاق التنبيهات المتعافية كل 15 دقيقة
  perform cron.schedule('hr_monitor_resolve', '*/15 * * * *',
    $job$ select public.resolve_stale_alerts(30); $job$);

  raise notice 'تمت جدولة مهمتي المراقبة (alerts/resolve).';
end
$mon$;

-- =====================================================================
-- نهاية Migration 0051
-- =====================================================================
