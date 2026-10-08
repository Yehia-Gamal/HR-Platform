begin;

-- ============================================================================
-- 0661: التقرير الشهري التنفيذي الشامل (بند 6 من المرحلة الثانية)
--        المصدر المعتمد للحضور attendance_day_facts، مع إحصائيات الطلبات
--        والمأموريات والغرامات وسرعة الاعتماد وتوزيع الأقسام، مع جدول الكرون.
-- ============================================================================

create table if not exists public.executive_monthly_reports (
  id uuid primary key default gen_random_uuid(),
  report_year int not null check (report_year between 2020 and 2100),
  report_month int not null check (report_month between 1 and 12),
  generated_at timestamptz not null default now(),
  generated_by uuid references auth.users(id),
  report_data jsonb not null,
  is_final boolean not null default false,
  constraint executive_monthly_reports_year_month_key unique (report_year, report_month)
);

alter table public.executive_monthly_reports enable row level security;

drop policy if exists executive_monthly_reports_read on public.executive_monthly_reports;
create policy executive_monthly_reports_read on public.executive_monthly_reports
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.current_is_executive_secretary()
    or public.current_has_active_role(array['executive', 'executive-director', 'hr-manager'])
    or public.has_any_permission(array['reports.executive.read', 'reports.attendance.read'])
  );

create or replace function public.generate_executive_monthly_report(
  p_year int,
  p_month int,
  p_save boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_start_date date;
  v_end_date   date;
  v_today      date := (now() at time zone 'Africa/Cairo')::date;
  v_query_end  date;
  v_result     jsonb;
  v_is_final   boolean := false;
  v_inserted_id uuid;
begin
  if not (
    coalesce(auth.role(), '') = 'service_role'
    or coalesce(current_setting('role', true), '') = 'service_role'
    or (coalesce(current_setting('role', true), '') = 'none' and session_user = 'postgres')
    or public.current_is_executive_secretary()
    or public.current_has_active_role(array['executive', 'executive-director', 'hr-manager'])
    or public.has_any_permission(array['reports.executive.read', 'reports.attendance.read', 'performance.kpi.report.read'])
    or public.current_is_full_access()
  ) then
    raise exception 'EXECUTIVE_REPORT_FORBIDDEN' using errcode = '42501';
  end if;

  if p_year < 2020 or p_year > 2100 or p_month < 1 or p_month > 12 then
    raise exception 'INVALID_YEAR_OR_MONTH' using errcode = '22023';
  end if;

  v_start_date := make_date(p_year, p_month, 1);
  v_end_date   := (v_start_date + interval '1 month - 1 day')::date;
  v_query_end  := least(v_end_date, v_today);

  -- إذا انتهى الشهر تماماً يعتبر التقرير نهائياً
  if v_end_date < v_today then
    v_is_final := true;
  end if;

  with facts as (
    select * from public.attendance_day_facts(v_start_date, v_query_end)
  ),
  att_summary as (
    select
      count(distinct f.employee_id)::int as active_employees_count,
      count(*)::int as total_calendar_days,
      count(*) filter (where f.expected)::int as required_days,
      count(*) filter (where f.attended)::int as attended_days,
      count(*) filter (where f.absent)::int as absent_days,
      count(*) filter (where f.attended and f.late_minutes > 0)::int as late_days,
      count(*) filter (where f.leave_like)::int as leave_days,
      count(*) filter (where f.offsite)::int as offsite_days,
      coalesce(sum(f.late_minutes), 0)::int as total_late_minutes,
      round(coalesce(100.0 * count(*) filter (where f.attended) / nullif(count(*) filter (where f.expected), 0), 0.0)::numeric, 1)::float as attendance_rate
    from facts f
  ),
  dept_stats as (
    select
      coalesce(d.name, 'غير محدد') as department_name,
      count(distinct f.employee_id)::int as employees_count,
      count(*) filter (where f.expected)::int as required_days,
      count(*) filter (where f.attended)::int as attended_days,
      count(*) filter (where f.absent)::int as absent_days,
      count(*) filter (where f.attended and f.late_minutes > 0)::int as late_days,
      coalesce(sum(f.late_minutes), 0)::int as total_late_minutes,
      round(coalesce(100.0 * count(*) filter (where f.attended) / nullif(count(*) filter (where f.expected), 0), 0.0)::numeric, 1)::float as attendance_rate
    from facts f
    join public.employees e on e.id = f.employee_id
    left join public.departments d on d.id = e.department_id
    group by d.name
    order by count(distinct f.employee_id) desc
  ),
  req_summary as (
    select
      count(*)::int as total_requests,
      count(*) filter (where r.status = 'approved')::int as approved_count,
      count(*) filter (where r.status = 'rejected')::int as rejected_count,
      count(*) filter (where r.status = 'pending')::int as pending_count,
      count(*) filter (where r.status = 'cancelled')::int as cancelled_count,
      count(*) filter (where r.request_type = 'leave')::int as leave_requests,
      count(*) filter (where r.request_type in ('mission', 'external_mission', 'administrative_mission'))::int as mission_requests,
      count(*) filter (where r.request_type in ('convoy', 'field_convoy'))::int as convoy_requests,
      count(*) filter (where r.request_type in ('late_permit', 'early_permit', 'permit', 'permission'))::int as permit_requests,
      count(*) filter (where r.request_type in ('fundraising', 'fandy', 'fundi'))::int as fundraising_requests
    from public.requests r
    where r.created_at >= v_start_date::timestamptz
      and r.created_at < (v_end_date + 1)::timestamptz
  ),
  mission_stats as (
    select
      count(*)::int as total_executions,
      count(*) filter (where m.status in ('completed', 'closed'))::int as completed_count,
      count(*) filter (where m.auto_closed_at is not null)::int as auto_closed_count,
      count(*) filter (where m.report is not null and length(trim(m.report)) > 0)::int as reported_count
    from public.mission_executions m
    where m.started_at >= v_start_date::timestamptz
      and m.started_at < (v_end_date + 1)::timestamptz
  ),
  penalty_stats as (
    select
      count(*)::int as total_penalties,
      count(*) filter (where p.status = 'paid')::int as paid_count,
      count(*) filter (where p.status in ('pending_payment', 'doubled', 'suspended'))::int as unpaid_count,
      coalesce(sum(p.current_amount), 0)::numeric as total_amount,
      coalesce(sum(p.current_amount) filter (where p.status = 'paid'), 0)::numeric as paid_amount
    from public.instant_attendance_penalties p
    where p.work_date >= v_start_date
      and p.work_date <= v_end_date
  ),
  sla_stats as (
    select
      count(s.id)::int as total_decisions,
      round(coalesce(avg(greatest(0.0, extract(epoch from (s.acted_at - s.created_at)) / 3600.0)), 0.0)::numeric, 1)::float as avg_turnaround_hours,
      round(coalesce(percentile_cont(0.5) within group (order by greatest(0.0, extract(epoch from (s.acted_at - s.created_at)) / 3600.0)), 0.0)::numeric, 1)::float as median_turnaround_hours,
      count(*) filter (where s.escalated_at is not null)::int as escalated_count
    from public.request_steps s
    where s.acted_at is not null
      and s.status in ('approved', 'rejected')
      and s.acted_at >= v_start_date::timestamptz
      and s.acted_at < (v_end_date + 1)::timestamptz
  )
  select jsonb_build_object(
    'period', jsonb_build_object(
      'year', p_year,
      'month', p_month,
      'startDate', v_start_date,
      'endDate', v_end_date,
      'effectiveEndDate', v_query_end,
      'isFinal', v_is_final
    ),
    'attendance', (select to_jsonb(a) from att_summary a),
    'departments', coalesce((select jsonb_agg(to_jsonb(d)) from dept_stats d), '[]'::jsonb),
    'requests', (select to_jsonb(r) from req_summary r),
    'missions', (select to_jsonb(m) from mission_stats m),
    'penalties', (select to_jsonb(p) from penalty_stats p),
    'sla', (select to_jsonb(s) from sla_stats s),
    'generatedAt', now()
  ) into v_result;

  if p_save then
    insert into public.executive_monthly_reports (
      report_year,
      report_month,
      generated_at,
      generated_by,
      report_data,
      is_final
    )
    values (
      p_year,
      p_month,
      now(),
      auth.uid(),
      v_result,
      v_is_final
    )
    on conflict (report_year, report_month) do update
      set generated_at = excluded.generated_at,
          generated_by = excluded.generated_by,
          report_data  = excluded.report_data,
          is_final     = excluded.is_final
    returning id into v_inserted_id;
  end if;

  return v_result;
end;
$$;

create or replace function public.get_executive_monthly_report(
  p_year int,
  p_month int
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_saved jsonb;
begin
  if not (
    coalesce(auth.role(), '') = 'service_role'
    or coalesce(current_setting('role', true), '') = 'service_role'
    or (coalesce(current_setting('role', true), '') = 'none' and session_user = 'postgres')
    or public.current_is_executive_secretary()
    or public.current_has_active_role(array['executive', 'executive-director', 'hr-manager'])
    or public.has_any_permission(array['reports.executive.read', 'reports.attendance.read', 'performance.kpi.report.read'])
    or public.current_is_full_access()
  ) then
    raise exception 'EXECUTIVE_REPORT_FORBIDDEN' using errcode = '42501';
  end if;

  select report_data into v_saved
  from public.executive_monthly_reports
  where report_year = p_year and report_month = p_month;

  if v_saved is not null then
    return v_saved;
  end if;

  -- إذا لم يكن محفوظاً يتم توليده آنياً
  return public.generate_executive_monthly_report(p_year, p_month, false);
end;
$$;

create or replace function public.cron_generate_previous_month_executive_report(p_force boolean default false)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now        timestamp := now() at time zone 'Africa/Cairo';
  v_today      date := v_now::date;
  v_prev_month date := (date_trunc('month', v_today) - interval '1 day')::date;
  v_year       int := extract(year from v_prev_month)::int;
  v_month      int := extract(month from v_prev_month)::int;
begin
  if auth.uid() is not null and not public.current_is_full_access() then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- جدول مزدوج (02:00 و03:00 UTC): يُشغّل بعد الساعة 04:00 فجراً بتوقيت القاهرة
  if not p_force and extract(hour from v_now) < 4 then
    return 0;
  end if;

  -- منع التكرار: إذا كان التقرير النهائي موجوداً بالفعل للشهر السابق فلا داعي لإعادة توليده
  if not p_force and exists (
    select 1 from public.executive_monthly_reports
    where report_year = v_year and report_month = v_month and is_final = true
  ) then
    return 0;
  end if;

  perform public.generate_executive_monthly_report(v_year, v_month, true);
  return 1;
end;
$$;

revoke all on function public.generate_executive_monthly_report(int, int, boolean) from public, anon;
grant execute on function public.generate_executive_monthly_report(int, int, boolean) to authenticated;

revoke all on function public.get_executive_monthly_report(int, int) from public, anon;
grant execute on function public.get_executive_monthly_report(int, int) to authenticated;

revoke all on function public.cron_generate_previous_month_executive_report(boolean) from public, anon;
grant execute on function public.cron_generate_previous_month_executive_report(boolean) to service_role;

-- جدول الكرون: أول يوم من كل شهر الساعة 02:00 و03:00 UTC
do $$
begin
  if exists (select 1 from cron.job where jobname = 'hr_executive_monthly_report') then
    perform cron.unschedule('hr_executive_monthly_report');
  end if;
end;
$$;
select cron.schedule('hr_executive_monthly_report', '0 2,3 1 * *', $c$select public.cron_generate_previous_month_executive_report()$c$);

commit;
