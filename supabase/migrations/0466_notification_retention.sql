-- =====================================================================
-- 0466: سياسة احتفاظ لسجل مهام الإشعارات الفاشلة
-- ---------------------------------------------------------------------
-- المشكلة: صفوف notification_jobs بحالة failed تبقى للأبد (51 صفًا
-- تاريخيًا من موجة token_missing حتى تاريخه) بلا أي تنظيف، فتتراكم
-- بلا فائدة تشغيلية وتشوّش قراءات المراقبة.
--
-- الحل:
--   1) purge_old_failed_notification_jobs(p_days => 30, p_batch => 1000):
--      حذف دفعات آمنة وقابل لإعادة التشغيل للصفوف الفاشلة الأقدم من
--      المدة المحددة (الحد الأدنى 7 أيام حفظًا لأثر التتبع).
--   2) تسجيل كل تشغيل في cron_health_log لرؤية تشغيلية موحدة.
--   3) جدولة يومية عبر pg_cron عند توفره (03:45 — خارج ازدحام 03:00).
-- الصلاحيات: service_role فقط (نموذج 0209/0454 المعتمد).
-- =====================================================================

begin;

create or replace function public.purge_old_failed_notification_jobs(
  p_days integer default 30,
  p_batch integer default 1000
)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_total   integer := 0;
  v_deleted integer := 0;
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
     and (auth.jwt() ->> 'role') is distinct from 'service_role' then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_days is null or p_days < 7 or p_days > 365 then
    raise exception 'INVALID_RETENTION' using errcode = '22023';
  end if;

  if p_batch is null or p_batch < 1 or p_batch > 10000 then
    raise exception 'INVALID_BATCH' using errcode = '22023';
  end if;

  loop
    delete from public.notification_jobs
    where id in (
      select id
      from public.notification_jobs
      where status = 'failed'
        and created_at < now() - make_interval(days => p_days)
      limit p_batch
    );
    get diagnostics v_deleted = row_count;
    v_total := v_total + v_deleted;
    exit when v_deleted = 0 or v_deleted < p_batch;
  end loop;

  insert into public.cron_health_log(job_name, rows_affected, status)
  values ('hr_notification_retention', v_total, 'ok');

  return v_total;

exception when others then
  insert into public.cron_health_log(job_name, rows_affected, status, detail)
  values ('hr_notification_retention', 0, 'error', sqlerrm);
  raise;
end;
$function$;

revoke all on function public.purge_old_failed_notification_jobs(integer, integer)
  from public, anon, authenticated;
grant execute on function public.purge_old_failed_notification_jobs(integer, integer)
  to service_role;

comment on function public.purge_old_failed_notification_jobs is
  '0466: حذف مهام الإشعارات الفاشلة الأقدم من p_days يوماً — دفعات آمنة وقابلة لإعادة التشغيل.';

-- جدولة يومية عبر pg_cron عند توفره (03:45)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('hr_notification_retention')
    where exists (select 1 from cron.job where jobname = 'hr_notification_retention');
    perform cron.schedule(
      'hr_notification_retention',
      '45 3 * * *',
      $cron$ select public.purge_old_failed_notification_jobs() $cron$
    );
  end if;
end $$;

commit;
