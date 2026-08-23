begin;

-- Migration 0454: سياسة أرشفة أحداث الحضور
-- attendance_events تنمو بلا حدود؛ ننقل الأحداث الأقدم من المدة المحددة
-- (افتراضياً 25 شهراً — يحفظ سنتين كاملتين للتدقيق) إلى جدول أرشفة منفصل:
-- مقفول بالكامل أمام المستخدمين، ويُدار عبر service_role ودالة مجدولة.

-- ① جدول الأرشفة — نفس البنية دون قيود خارجية
create table if not exists public.attendance_events_archive (
  like public.attendance_events including defaults including generated including identity
);

-- إزالة أي قيود خارجية ورثها LIKE — الأرشيف مستقل عن الجداول الحية
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.attendance_events_archive'::regclass
      and contype = 'f'
  loop
    execute format('alter table public.attendance_events_archive drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.attendance_events_archive enable row level security;
revoke all on public.attendance_events_archive from public, anon, authenticated;

-- ② دالة النقل — دفعات محدودة، قابلة لإعادة التشغيل، تعيد عدد الصفوف المنقولة
create or replace function public.archive_old_attendance_events(
  p_older_than_months int default 25,
  p_batch_size int default 5000
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cutoff timestamptz := date_trunc('month', now()) - make_interval(months => greatest(p_older_than_months, 1));
  v_moved int := 0;
  v_batch int;
begin
  if p_batch_size < 100 or p_batch_size > 50000 then
    raise exception 'INVALID_BATCH' using errcode = '22023';
  end if;

  loop
    with moved as (
      delete from public.attendance_events
      where id in (
        select id from public.attendance_events
        where event_at < v_cutoff
        order by event_at
        limit p_batch_size
      )
      returning *
    )
    insert into public.attendance_events_archive select * from moved;

    get diagnostics v_batch = row_count;
    v_moved := v_moved + v_batch;
    exit when v_batch < p_batch_size;
  end loop;

  return v_moved;
end;
$$;

revoke all on function public.archive_old_attendance_events(int, int) from public, anon;
-- التشغيل عبر cron/الخدمة الخلفية فقط
grant execute on function public.archive_old_attendance_events(int, int) to service_role;

comment on function public.archive_old_attendance_events is
  '0454: نقل أحداث الحضور الأقدم من المدة المحددة إلى الأرشيف — دفعات آمنة وقابلة لإعادة التشغيل.';

-- ③ جدولة شهرية عبر pg_cron عند توفره (اليوم 1 من كل شهر 03:00)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('archive-attendance-events')
    where exists (select 1 from cron.job where jobname = 'archive-attendance-events');
    perform cron.schedule(
      'archive-attendance-events',
      '0 3 1 * *',
      $cron$ select public.archive_old_attendance_events() $cron$
    );
  end if;
end $$;

commit;
