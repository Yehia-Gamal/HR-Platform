-- ==============================================================================
-- Migration 0618: Fix Honor Board Canonical Calculation & Data Shape
-- 1. Restores canonical honoree object structure:
--    ('rank', 'name', 'full_name_ar', 'employee_id', 'department', 'photo_url',
--     'score', 'metric', 'achievement', 'present_days', 'work_days', 'late_minutes',
--     'extra_days', 'period', 'category')
-- 2. Corrects attendance ranking logic:
--    - Calculates actual attendance (present, attended, excused, mission, missing_checkout, late)
--    - Requires genuine check-in / work minutes for extra non-workday credit
--    - Deducts realistic late minutes ratio without giving 0-attendance staff 20 points
--    - Excludes clinic staff, executives, test accounts, and exempt staff
-- 3. Restores full categories: attendance, missions, locations, reports
-- 4. Preserves clinic staff privacy exemption (returns [] for clinic staff callers)
-- ==============================================================================

create or replace function public.get_honor_board(
  p_period text default 'month'::text,
  p_category text default 'attendance'::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today  date := (now() at time zone 'Africa/Cairo')::date;
  v_start  date;
  v_result jsonb;
  v_me     uuid := public.current_employee_id();
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  -- تيم العيادات (غير المديرين) محجوبة عنهم لوحة الشرف
  if public.is_clinic_staff_exempt(v_me) then
    return '[]'::jsonb;
  end if;

  if p_period = 'week' then
    -- السبت = 6 في extract(dow): يبدأ الأسبوع دائماً من السبت
    v_start := v_today - ((extract(dow from v_today)::int + 1) % 7);
  else
    v_start := date_trunc('month', v_today)::date;
  end if;

  if p_category = 'attendance' then
    with days as (
      select d::date as day,
             (extract(dow from d) <> 5
              and not exists (
                select 1 from public.public_holidays h
                where h.is_active
                  and d::date between h.holiday_date and coalesce(h.end_date, h.holiday_date)
              )) as is_workday
      from generate_series(v_start, v_today, interval '1 day') d
    ),
    staff as (
      select e.id, e.full_name_ar, e.photo_url, e.hire_date,
             coalesce(dp.name, 'الإدارة العامة') as department
      from public.employees e
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not coalesce(e.is_attendance_exempt, false)
        and not public.is_employee_attendance_exempt(e.id)
        and not public.is_employee_executive(e.id)
        and not public.is_clinic_staff_exempt(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
    ),
    grid as (
      select s.id as employee_id, dy.day, dy.is_workday, ad.status,
             coalesce(ad.late_minutes, 0) as late_minutes,
             coalesce(ad.work_minutes, 0) as work_minutes,
             ad.first_check_in
      from staff s
      cross join days dy
      left join public.attendance_daily ad on ad.employee_id = s.id and ad.work_date = dy.day
      where s.hire_date is null or dy.day >= s.hire_date
    ),
    per_emp as (
      select g.employee_id,
             count(*) filter (where g.is_workday and (g.day < v_today or g.status is not null)) as workdays,
             count(*) filter (where g.is_workday and g.status = 'on_leave') as leave_days,
             count(*) filter (where g.is_workday and (
               g.status in ('present','attended','excused','mission','missing_checkout','late')
               or g.first_check_in is not null
             )) as present_days,
             count(*) filter (where not g.is_workday and (
               g.first_check_in is not null or g.work_minutes > 0
             )) as extra_days,
             coalesce(sum(g.late_minutes) filter (where g.is_workday and (
               g.status in ('present','attended','excused','mission','missing_checkout','late')
               or g.first_check_in is not null
             )), 0) as late_minutes
      from grid g
      group by g.employee_id
    ),
    scored as (
      select s.*, p.*,
             greatest(p.workdays - p.leave_days, 0) as expected,
             case when p.workdays - p.leave_days > 0
                  then greatest(0, least(
                    p.present_days::numeric / (p.workdays - p.leave_days),
                    1
                  ) - (p.late_minutes::numeric / (greatest(p.workdays - p.leave_days, 1) * 480.0)))
                  else 0 end as ratio
      from per_emp p join staff s on s.id = p.employee_id
      where p.present_days > 0
    ),
    ranked as (
      select row_number() over (
               order by ratio desc, present_days desc, late_minutes asc, extra_days desc, full_name_ar asc
             ) as rank,
             sc.*
      from scored sc
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'name', full_name_ar,
        'full_name_ar', full_name_ar,
        'employee_id', employee_id,
        'department', department,
        'photo_url', photo_url,
        'score', round(ratio * 100)::int,
        'metric', round(ratio * 100)::int || '% انضباط',
        'achievement',
          case
            when present_days >= expected and late_minutes = 0
              then 'حضور كامل ' || present_days || ' من ' || expected || ' يوم عمل بدون أي تأخير'
            when present_days >= expected
              then 'حضور كامل ' || present_days || ' من ' || expected || ' يوم عمل (تأخير '
                   || public._ar_count(late_minutes, 'دقيقة', 'دقيقتان', 'دقائق', 'دقيقة') || ')'
            else 'حضور ' || present_days || ' من ' || expected || ' يوم عمل'
                 || case when late_minutes > 0
                         then ' (تأخير ' || public._ar_count(late_minutes, 'دقيقة', 'دقيقتان', 'دقائق', 'دقيقة') || ')'
                         else '' end
          end
          || case when extra_days > 0
                  then ' + ' || public._ar_count(extra_days, 'يوم إضافي', 'يومان إضافيان', 'أيام إضافية', 'يوماً إضافياً')
                  else '' end,
        'present_days', present_days,
        'work_days', expected,
        'late_minutes', late_minutes,
        'extra_days', extra_days,
        'period', p_period,
        'category', p_category
      ) order by rank
    ), '[]'::jsonb)
    into v_result
    from (select * from ranked order by rank limit 10) t;

  elsif p_category = 'missions' then
    with field as (
      select r.employee_id,
             greatest((r.payload->>'startDate')::date, v_start) as s,
             least(coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date), v_today) as e
      from public.requests r
      where r.request_type in ('mission', 'convoy', 'fundraising')
        and r.status = 'approved'
        and r.payload ? 'startDate'
        and (r.payload->>'startDate')::date <= v_today
        and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date) >= v_start
    ),
    per_emp as (
      select employee_id, count(*) as missions, sum(e - s + 1) as field_days
      from field group by employee_id
    ),
    ranked as (
      select row_number() over (order by p.missions desc, p.field_days desc, e.full_name_ar asc) as rank,
             e.id as employee_id, e.full_name_ar, coalesce(dp.name, 'الإدارة العامة') as department, e.photo_url,
             p.missions, p.field_days
      from per_emp p
      join public.employees e on e.id = p.employee_id
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_employee_executive(e.id)
        and not public.is_clinic_staff_exempt(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'name', full_name_ar,
        'full_name_ar', full_name_ar,
        'employee_id', employee_id,
        'department', department,
        'photo_url', photo_url,
        'score', missions * 10,
        'metric', public._ar_count(missions, 'مأمورية', 'مأموريتان', 'مأموريات', 'مأمورية'),
        'achievement', public._ar_count(missions, 'مأمورية ميدانية معتمدة', 'مأموريتان ميدانيتان معتمدتان', 'مأموريات ميدانية معتمدة', 'مأمورية ميدانية معتمدة')
                       || ' بإجمالي ' || public._ar_count(field_days, 'يوم عمل ميداني', 'يوما عمل ميداني', 'أيام عمل ميداني', 'يوم عمل ميداني'),
        'completed_missions', missions,
        'field_days', field_days,
        'period', p_period,
        'category', p_category
      ) order by rank
    ), '[]'::jsonb)
    into v_result
    from (select * from ranked order by rank limit 10) t;

  elsif p_category = 'locations' then
    with loc_data as (
      select lr.employee_id,
             count(*) as total_requests,
             count(*) filter (where lr.status = 'completed') as completed,
             count(*) filter (where lr.status in ('pending','active') and lr.expires_at < now()) as expired,
             avg(extract(epoch from (lr.responded_at - lr.requested_at)) / 60.0)
               filter (where lr.status = 'completed' and lr.responded_at is not null) as avg_response_minutes
      from public.live_location_requests lr
      where lr.requested_at >= v_start
        and lr.requested_at <= now()
      group by lr.employee_id
    ),
    ranked as (
      select row_number() over (
               order by ld.completed desc,
                        coalesce(ld.avg_response_minutes, 999) asc,
                        ld.expired asc,
                        e.full_name_ar asc
             ) as rank,
             e.id as employee_id,
             e.full_name_ar,
             coalesce(dp.name, 'الإدارة العامة') as department,
             e.photo_url,
             ld.total_requests,
             ld.completed,
             ld.expired,
             round(coalesce(ld.avg_response_minutes, 0)::numeric, 1) as avg_min
      from loc_data ld
      join public.employees e on e.id = ld.employee_id
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_employee_executive(e.id)
        and not public.is_clinic_staff_exempt(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
        and ld.completed > 0
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'name', full_name_ar,
        'full_name_ar', full_name_ar,
        'employee_id', employee_id,
        'department', department,
        'photo_url', photo_url,
        'score', completed * 10,
        'metric', completed || '/' || total_requests || ' استجابة',
        'achievement', 'استجاب لـ ' || completed || ' من ' || total_requests || ' طلب موقع'
                       || case when avg_min > 0
                               then ' (متوسط ' || avg_min || ' دقيقة)'
                               else '' end
                       || case when expired > 0
                               then ' — ' || expired || ' منتهية'
                               else '' end,
        'total_requests', total_requests,
        'completed', completed,
        'expired', expired,
        'period', p_period,
        'category', p_category
      ) order by rank
    ), '[]'::jsonb)
    into v_result
    from (select * from ranked order by rank limit 10) t;

  else
    -- التقارير اليومية (reports)
    with per_emp as (
      select employee_id, count(*) as reports, count(distinct report_date) as report_days
      from public.daily_reports
      where report_date between v_start and v_today
      group by employee_id
    ),
    ranked as (
      select row_number() over (order by p.reports desc, p.report_days desc, e.full_name_ar asc) as rank,
             e.id as employee_id,
             e.full_name_ar, coalesce(dp.name, 'الإدارة العامة') as department, e.photo_url,
             p.reports, p.report_days
      from per_emp p
      join public.employees e on e.id = p.employee_id
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_employee_executive(e.id)
        and not public.is_clinic_staff_exempt(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'name', full_name_ar,
        'full_name_ar', full_name_ar,
        'employee_id', employee_id,
        'department', department,
        'photo_url', photo_url,
        'score', reports * 5,
        'metric', public._ar_count(reports, 'تقرير', 'تقريران', 'تقارير', 'تقريراً'),
        'achievement', 'رفع ' || public._ar_count(reports, 'تقرير يومي', 'تقريرين يوميين', 'تقارير يومية', 'تقريراً يومياً')
                       || ' في ' || public._ar_count(report_days, 'يوم', 'يومين', 'أيام', 'يوماً'),
        'reports', reports,
        'report_days', report_days,
        'period', p_period,
        'category', p_category
      ) order by rank
    ), '[]'::jsonb)
    into v_result
    from (select * from ranked order by rank limit 10) t;
  end if;

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;

revoke execute on function public.get_honor_board(text, text) from public, anon;
grant execute on function public.get_honor_board(text, text) to authenticated, service_role;
