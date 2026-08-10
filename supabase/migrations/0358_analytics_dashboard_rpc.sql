-- Migration 0356: RPC موحّد للوحة التحليلات
-- يجمع: حركة الطلبات الشهرية + توزيع الأقسام + اتجاه الحضور الأسبوعي + متوسطات KPI
-- يُستدعى من AnalyticsDashboardPage عبر useAnalyticsDashboard hook.

create or replace function public.get_analytics_dashboard(
  p_months_back integer default 6
)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
  v_from_month   date;
  v_today        date;
  v_week_start   date;
  v_requests     jsonb;
  v_departments  jsonb;
  v_attendance   jsonb;
  v_kpi          jsonb;
begin
  if auth.uid() is null then
    raise exception 'ERR_UNAUTHENTICATED' using errcode = '28000';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_permission('reports.people.read')
    or public.has_permission('reports.hr.read')
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  v_today      := (now() at time zone 'Africa/Cairo')::date;
  v_from_month := date_trunc('month', v_today - (p_months_back || ' months')::interval)::date;
  v_week_start := v_today - extract(dow from v_today)::integer;

  -- ── 1. حركة الطلبات الشهرية ──────────────────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'month',        to_char(s.month, 'Mon YYYY'),
        'monthKey',     to_char(s.month, 'YYYY-MM'),
        'approved',     s.approved,
        'rejected',     s.rejected,
        'pending',      s.pending,
        'cancelled',    s.cancelled
      )
      order by s.month
    ),
    '[]'::jsonb
  )
  into v_requests
  from (
    select
      date_trunc('month', month)::date as month,
      sum(approved)   as approved,
      sum(rejected)   as rejected,
      sum(pending)    as pending,
      sum(cancelled)  as cancelled
    from public.mv_monthly_request_stats
    where month >= v_from_month
    group by date_trunc('month', month)
  ) s;

  -- ── 2. توزيع الموظفين حسب الأقسام ───────────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name',  h.department_name,
        'value', h.active_count
      )
      order by h.active_count desc
    ),
    '[]'::jsonb
  )
  into v_departments
  from public.mv_department_headcount h
  where h.active_count > 0;

  -- ── 3. اتجاه الحضور (7 أيام الماضية) ────────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name',    to_char(day_date, 'Dy'),
        'date',    day_date,
        'present', coalesce(present_count, 0),
        'late',    coalesce(late_count,    0),
        'absent',  coalesce(absent_count,  0)
      )
      order by day_date
    ),
    '[]'::jsonb
  )
  into v_attendance
  from (
    select
      d.day_date,
      count(*) filter (
        where ad.status in ('present', 'present_late')
          and ad.is_weekend = false
          and ad.is_holiday = false
      ) as present_count,
      count(*) filter (
        where ad.status = 'present_late'
          and ad.is_weekend = false
          and ad.is_holiday = false
      ) as late_count,
      count(*) filter (
        where ad.status in ('absent', 'absent_excused')
          and ad.is_weekend = false
          and ad.is_holiday = false
      ) as absent_count
    from generate_series(v_week_start, v_today, '1 day'::interval) as d(day_date)
    left join public.attendance_daily ad on ad.work_date = d.day_date::date
    where extract(isodow from d.day_date) not in (5, 6)   -- الجمعة والسبت راحة
    group by d.day_date
  ) w;

  -- ── 4. متوسطات KPI (آخر 6 دورات منتهية) ─────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'subject',    k.criterion_name,
        'actual',     round(k.avg_score::numeric, 1),
        'target',     k.max_score
      )
      order by k.criterion_name
    ),
    '[]'::jsonb
  )
  into v_kpi
  from (
    select
      kc.name_ar                                    as criterion_name,
      avg(kes.weighted_score / nullif(kc.weight, 0) * 100) as avg_score,
      100                                           as max_score
    from public.kpi_cycles c
    join public.kpi_evaluations ke  on ke.cycle_id = c.id
    join public.kpi_evaluation_scores kes on kes.evaluation_id = ke.id
    join public.kpi_criteria kc     on kc.id = kes.criterion_id
    where c.status in ('closed', 'locked')
      and c.period_month >= (v_today - '6 months'::interval)::date
      and ke.final_score is not null
    group by kc.name_ar
    having count(*) >= 3
  ) k;

  return jsonb_build_object(
    'monthlyRequests',       coalesce(v_requests,    '[]'::jsonb),
    'departmentDistribution',coalesce(v_departments, '[]'::jsonb),
    'attendanceTrend',       coalesce(v_attendance,  '[]'::jsonb),
    'kpiScores',             coalesce(v_kpi,         '[]'::jsonb),
    'generatedAt',           now() at time zone 'Africa/Cairo'
  );
end;
$$;

revoke all on function public.get_analytics_dashboard(integer) from public, anon;
grant execute on function public.get_analytics_dashboard(integer) to authenticated, service_role;

comment on function public.get_analytics_dashboard(integer) is
  'لوحة التحليلات الموحّدة: طلبات شهرية + توزيع أقسام + اتجاه حضور + متوسطات KPI.';
