-- =====================================================================
-- Migration 0693: Get My Permit Balance RPC
-- Description: Provides employee monthly permit quota (4 permits = 8 hours)
-- with used (approved/pending), remaining permits & hours, and active items.
-- =====================================================================

create or replace function public.get_my_permit_balance(
  p_month date default (now() at time zone 'Africa/Cairo')::date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_target_date date := coalesce(p_month, (now() at time zone 'Africa/Cairo')::date);
  v_month_start date := date_trunc('month', v_target_date)::date;
  v_month_end   date := (v_month_start + interval '1 month')::date;
  v_max_permits int := 4;
  v_used_approved int := 0;
  v_used_pending int := 0;
  v_total_used int := 0;
  v_remaining_permits int := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_me is null then
    return jsonb_build_object(
      'month', v_month_start,
      'max_permits', v_max_permits,
      'max_hours', v_max_permits * 2,
      'used_approved', 0,
      'used_pending', 0,
      'total_used', 0,
      'remaining_permits', v_max_permits,
      'remaining_hours', v_max_permits * 2,
      'minutes_per_permit', 120,
      'has_remaining', true,
      'items', '[]'::jsonb
    );
  end if;

  with all_permits as (
    -- 1) من جدول requests الموحّد
    select
      r.id as ref_id,
      'request' as source,
      coalesce(
        (r.payload->>'permitDate')::date,
        (r.payload->>'date')::date,
        (r.payload->>'startDate')::date,
        (r.created_at at time zone 'Africa/Cairo')::date
      ) as p_date,
      case
        when r.request_type = 'early_permit' or r.payload->>'permitKind' = 'early_departure' then 'early_departure'
        else 'late_arrival'
      end as p_kind,
      coalesce(nullif(r.payload->>'minutes', '')::int, 120) as p_minutes,
      r.status as p_status,
      coalesce(r.title, case when r.request_type = 'early_permit' or r.payload->>'permitKind' = 'early_departure' then 'إذن انصراف' else 'إذن حضور' end) as p_title,
      r.created_at
    from public.requests r
    where r.employee_id = v_me
      and r.status in ('approved', 'pending')
      and (
        r.request_type in ('late_permit', 'early_permit')
        or r.request_type = 'permit'
      )
      and coalesce(
        (r.payload->>'permitDate')::date,
        (r.payload->>'date')::date,
        (r.payload->>'startDate')::date,
        (r.created_at at time zone 'Africa/Cairo')::date
      ) >= v_month_start
      and coalesce(
        (r.payload->>'permitDate')::date,
        (r.payload->>'date')::date,
        (r.payload->>'startDate')::date,
        (r.created_at at time zone 'Africa/Cairo')::date
      ) < v_month_end

    union all

    -- 2) من جدول attendance_permits مع تفادي التكرار
    select
      p.id as ref_id,
      'attendance_permit' as source,
      p.permit_date as p_date,
      case when p.kind = 'departure' then 'early_departure' else 'late_arrival' end as p_kind,
      coalesce(nullif(p.grace_minutes, 0), 120) as p_minutes,
      p.status as p_status,
      case when p.kind = 'departure' then 'إذن انصراف مبكر' else 'إذن حضور متأخر' end as p_title,
      p.created_at
    from public.attendance_permits p
    where p.employee_id = v_me
      and p.status in ('approved', 'pending')
      and p.permit_date >= v_month_start
      and p.permit_date < v_month_end
      and not exists (
        select 1 from public.requests r2
        where r2.employee_id = v_me
          and r2.status in ('approved', 'pending')
          and (
            r2.request_type in ('late_permit', 'early_permit')
            or r2.request_type = 'permit'
          )
          and coalesce(
            (r2.payload->>'permitDate')::date,
            (r2.payload->>'date')::date,
            (r2.payload->>'startDate')::date,
            (r2.created_at at time zone 'Africa/Cairo')::date
          ) = p.permit_date
          and (
            case
              when r2.request_type = 'early_permit' or r2.payload->>'permitKind' = 'early_departure' then 'early_departure'
              else 'late_arrival'
            end
          ) = (case when p.kind = 'departure' then 'early_departure' else 'late_arrival' end)
      )
  )
  select
    coalesce(count(*) filter (where p_status = 'approved'), 0),
    coalesce(count(*) filter (where p_status = 'pending'), 0),
    count(*),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', ref_id,
          'date', p_date,
          'kind', p_kind,
          'kind_label', case when p_kind = 'early_departure' then 'إذن انصراف' else 'إذن حضور' end,
          'minutes', p_minutes,
          'status', p_status,
          'title', p_title
        ) order by p_date desc
      ),
      '[]'::jsonb
    )
  into v_used_approved, v_used_pending, v_total_used, v_items
  from all_permits;

  v_remaining_permits := greatest(0, v_max_permits - v_total_used);

  return jsonb_build_object(
    'month', v_month_start,
    'max_permits', v_max_permits,
    'max_hours', v_max_permits * 2,
    'used_approved', v_used_approved,
    'used_pending', v_used_pending,
    'total_used', v_total_used,
    'remaining_permits', v_remaining_permits,
    'remaining_hours', v_remaining_permits * 2,
    'minutes_per_permit', 120,
    'has_remaining', (v_remaining_permits > 0),
    'items', v_items
  );
end;
$$;

revoke all on function public.get_my_permit_balance(date) from public, anon;
grant execute on function public.get_my_permit_balance(date) to authenticated;
comment on function public.get_my_permit_balance(date) is
  '0693: حساب رصيد أذونات الموظف الشهري (4 أذونات = 8 ساعات) مع المستهلك والمتبقي وقيد الانتظار.';
