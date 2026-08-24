begin;

-- Migration 0456: اتجاه الحضور اليومي للملخص التنفيذي
-- سلسلة يومية (حاضر/متأخر/غائب) من attendance_daily لتغذية الرسم البياني
-- في الملخص التنفيذي. الدالة security invoker — RLS على attendance_daily
-- يقصر النتائج طبيعياً (التنفيذي يرى المنظمة، المدير فريقه).

create or replace function public.get_mobile_attendance_trend(
  p_days int default 14
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(t order by t.work_date), '[]'::jsonb)
  from (
    select d.work_date,
      count(*) filter (where d.status in ('present', 'partial'))::int as present,
      count(*) filter (where d.status = 'late')::int as late,
      count(*) filter (where d.status = 'absent')::int as absent
    from public.attendance_daily d
    where d.work_date > (now() at time zone 'Africa/Cairo')::date - greatest(p_days, 1)
      and d.work_date <= (now() at time zone 'Africa/Cairo')::date
      and d.status not in ('rest', 'holiday', 'cancelled')
    group by d.work_date
  ) t;
$$;

revoke all on function public.get_mobile_attendance_trend(int) from public, anon;
grant execute on function public.get_mobile_attendance_trend(int) to authenticated;

comment on function public.get_mobile_attendance_trend is
  '0456: سلسلة اتجاه الحضور اليومي (حاضر/متأخر/غائب) لآخر N يوم — RLS يطبق نطاق المستخدم.';

commit;
