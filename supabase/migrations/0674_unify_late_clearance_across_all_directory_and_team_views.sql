-- 0674_unify_late_clearance_across_all_directory_and_team_views.sql
-- Unify late clearance across all directory and team views:
-- When an employee completes 8 hours (480 minutes) of work or their status is 'present',
-- late status is completely cleared and marked as 'present' ('حاضر') with overtime tracking,
-- eliminating stale 'late' / 'متأخر' tags across:
-- 1) get_employees_enriched
-- 2) get_mobile_employee_directory
-- 3) get_my_mobile_team

-- 1) get_employees_enriched
CREATE OR REPLACE FUNCTION public.get_employees_enriched(
  p_search text DEFAULT NULL::text,
  p_status text DEFAULT NULL::text,
  p_limit integer DEFAULT 200
)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_search text := nullif(trim(lower(coalesce(p_search, ''))), '');
  v_is_org_admin boolean := false;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  v_is_org_admin := public.current_is_full_access()
    or public.has_permission('organization.org_chart.read');

  return coalesce((
    select jsonb_agg(row_data order by row_data->>'fullNameAr')
    from (
      select jsonb_build_object(
        'id', e.id,
        'employeeCode', e.employee_code,
        'fullNameAr', e.full_name_ar,
        'fullNameEn', e.full_name_en,
        'phoneE164', e.phone_e164,
        'status', e.status,
        'isActive', e.is_active,
        'photoUrl', e.photo_url,
        'departmentId', e.department_id,
        'department', coalesce(
          (
            select string_agg(d_sub.name, ' / ' order by ed_sub.is_primary desc, d_sub.name)
            from public.employee_departments ed_sub
            join public.departments d_sub on d_sub.id = ed_sub.department_id
            where ed_sub.employee_id = e.id
          ),
          d.name
        ),
        'teamId', e.team_id,
        'team', t.name,
        'branchId', e.branch_id,
        'branch', b.name,
        'jobTitle', jt.name,
        'createdAt', e.created_at,
        'statusToday', case
          when req.request_type = 'convoy' then 'convoy'
          when req.request_type = 'fundraising' then 'fundraising'
          when req.request_type = 'mission' then 'mission'
          when req.request_type = 'leave' then 'on_leave'
          when ad.status = 'on_leave' then 'on_leave'
          when ad.status in ('weekend','holiday') then ad.status
          when coalesce(ad.first_check_in, ae.event_at) is not null then
            case
              when ad.status = 'present'
                or coalesce(ad.work_minutes, 0) >= 480
                or (
                  ad.first_check_in is not null and ad.last_check_out is not null
                  and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
                )
                or (
                  ad.last_check_out is null
                  and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
                )
              then 'present'
              when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'late'
              else 'present'
            end
          when ad.status = 'absent' then 'absent'
          else 'not_recorded'
        end,
        'statusTodayLabel', case
          when req.request_type = 'convoy' then 'في قافلة'
          when req.request_type = 'fundraising' then 'في فاندي'
          when req.request_type = 'mission' then 'في مأمورية'
          when req.request_type = 'leave' then 'في إجازة'
          when ad.status = 'on_leave' then 'في إجازة'
          when ad.status = 'weekend' then 'إجازة أسبوعية'
          when ad.status = 'holiday' then 'عطلة رسمية'
          when coalesce(ad.first_check_in, ae.event_at) is not null then
            case
              when ad.status = 'present'
                or coalesce(ad.work_minutes, 0) >= 480
                or (
                  ad.first_check_in is not null and ad.last_check_out is not null
                  and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
                )
                or (
                  ad.last_check_out is null
                  and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
                )
              then
                case
                  when coalesce(ad.work_minutes, 0) > 480 or coalesce(ad.overtime_minutes, 0) > 0 then 'حاضر (إضافي)'
                  else 'حاضر'
                end
              when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'متأخر'
              else 'حاضر'
            end
          when ad.status = 'absent' then 'غائب'
          else 'لم يسجل بعد'
        end,
        'activityTitle', req.activity_title,
        'workMinutes', coalesce(ad.work_minutes, 0),
        'overtimeMinutes', coalesce(ad.overtime_minutes, case when coalesce(ad.work_minutes, 0) > 480 then coalesce(ad.work_minutes, 0) - 480 else 0 end),
        'lateMinutes', case
          when ad.status = 'present' or coalesce(ad.work_minutes, 0) >= 480 then 0
          else coalesce(ad.late_minutes, 0)
        end,
        'firstCheckIn', coalesce(ad.first_check_in, ae.event_at),
        'lastCheckOut', ad.last_check_out
      ) as row_data
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join public.teams t on t.id = e.team_id
      left join public.branches b on b.id = e.branch_id
      left join public.job_titles jt on jt.id = e.job_title_id
      left join lateral (
        select 
          r.request_type,
          coalesce(nullif(r.payload->>'location',''), nullif(r.payload->>'destination',''), nullif(r.title,'')) as activity_title
        from public.requests r
        where r.employee_id = e.id
          and r.status in ('approved', 'pending')
          and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
          and v_today between 
              coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date, r.created_at::date)
          and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date, r.created_at::date)
        order by case when r.status = 'approved' then 1 else 2 end,
                 case r.request_type 
                   when 'convoy' then 1
                   when 'fundraising' then 2
                   when 'mission' then 3
                   when 'leave' then 4
                   else 5
                 end,
                 r.created_at desc
        limit 1
      ) req on true
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
      left join lateral (
        select min(event_at) as event_at
        from public.attendance_events
        where employee_id = e.id and event_type = 'CHECK_IN'
          and (event_at at time zone 'Africa/Cairo')::date = v_today
          and status in ('accepted', 'adjusted')
      ) ae on true
      where e.is_deleted = false
        and not public.is_employee_executive(e.id)
        and (
          not public.is_employee_isolated(e.id)
          or public.can_view_isolated_employee(e.id)
        )
        and (p_status is null or e.status = p_status)
        and (
          v_search is null
          or lower(e.full_name_ar) like '%' || v_search || '%'
          or lower(coalesce(e.full_name_en, '')) like '%' || v_search || '%'
          or lower(e.employee_code) like '%' || v_search || '%'
          or e.phone_e164 like '%' || v_search || '%'
          or lower(coalesce(d.name, '')) like '%' || v_search || '%'
          or exists (
            select 1 from public.employee_departments ed_srch
            join public.departments d_srch on d_srch.id = ed_srch.department_id
            where ed_srch.employee_id = e.id and lower(d_srch.name) like '%' || v_search || '%'
          )
        )
        and (
          v_is_org_admin
          or public.can_access_employee(e.id, 'people.employee.read')
        )
      order by e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 200), 500))
    ) q
  ), '[]'::jsonb);
end;
$function$;

GRANT EXECUTE ON FUNCTION public.get_employees_enriched(text, text, integer) TO authenticated;

-- 2) get_mobile_employee_directory
CREATE OR REPLACE FUNCTION public.get_mobile_employee_directory(
  p_search text DEFAULT NULL::text,
  p_limit integer DEFAULT 40
)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',               e.id,
      'name',             e.full_name_ar,
      'employeeCode',     e.employee_code,
      'photoUrl',         e.photo_url,
      'jobTitle',         jt.name,
      'department',       d.name,
      'statusToday',      case
        when req.request_type = 'convoy' then 'convoy'
        when req.request_type = 'fundraising' then 'fundraising'
        when req.request_type = 'mission' then 'mission'
        when req.request_type = 'leave' then 'on_leave'
        when ad.status = 'on_leave' then 'on_leave'
        when ad.status in ('weekend','holiday') then ad.status
        when coalesce(ad.first_check_in, ae.event_at) is not null then
          case
            when ad.status = 'present'
              or coalesce(ad.work_minutes, 0) >= 480
              or (
                ad.first_check_in is not null and ad.last_check_out is not null
                and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
              )
              or (
                ad.last_check_out is null
                and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
              )
            then 'present'
            when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'late'
            else 'present'
          end
        when ad.status = 'absent' then 'absent'
        else 'not_recorded'
      end,
      'statusTodayLabel', case
        when req.request_type = 'convoy' then 'في قافلة'
        when req.request_type = 'fundraising' then 'في فاندي'
        when req.request_type = 'mission' then 'في مأمورية'
        when req.request_type = 'leave' then 'في إجازة'
        when ad.status = 'on_leave' then 'في إجازة'
        when ad.status = 'weekend' then 'إجازة أسبوعية'
        when ad.status = 'holiday' then 'عطلة رسمية'
        when coalesce(ad.first_check_in, ae.event_at) is not null then
          case
            when ad.status = 'present'
              or coalesce(ad.work_minutes, 0) >= 480
              or (
                ad.first_check_in is not null and ad.last_check_out is not null
                and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
              )
              or (
                ad.last_check_out is null
                and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
              )
            then
              case
                when coalesce(ad.work_minutes, 0) > 480 or coalesce(ad.overtime_minutes, 0) > 0 then 'حاضر (إضافي)'
                else 'حاضر'
              end
            when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'متأخر'
            else 'حاضر'
          end
        when ad.status = 'absent' then 'غائب'
        else 'لم يسجل'
      end,
      'activityTitle',    req.activity_title
    ) order by e.full_name_ar)
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d  on d.id  = e.department_id
    left join lateral (
      select 
        r.request_type,
        coalesce(nullif(r.payload->>'location',''), nullif(r.payload->>'destination',''), nullif(r.title,'')) as activity_title
      from public.requests r
      where r.employee_id = e.id
        and r.status in ('approved', 'pending')
        and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
        and v_today between 
            coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date, r.created_at::date)
        and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date, r.created_at::date)
      order by case when r.status = 'approved' then 1 else 2 end,
               case r.request_type 
                 when 'convoy' then 1
                 when 'fundraising' then 2
                 when 'mission' then 3
                 when 'leave' then 4
                 else 5
               end,
               r.created_at desc
      limit 1
    ) req on true
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
    left join lateral (
      select min(event_at) as event_at
      from public.attendance_events
      where employee_id = e.id and event_type = 'CHECK_IN'
        and (event_at at time zone 'Africa/Cairo')::date = v_today
        and status in ('accepted', 'adjusted')
    ) ae on true
    where e.is_active = true
      and e.is_deleted = false
      and not public.is_employee_executive(e.id)
      and (
        not public.is_employee_isolated(e.id)
        or public.can_view_isolated_employee(e.id)
      )
      and (
        v_search is null
        or lower(e.full_name_ar) like '%' || lower(v_search) || '%'
        or lower(coalesce(e.full_name_en, '')) like '%' || lower(v_search) || '%'
        or lower(e.employee_code) like '%' || lower(v_search) || '%'
        or lower(coalesce(d.name, '')) like '%' || lower(v_search) || '%'
        or lower(coalesce(jt.name, '')) like '%' || lower(v_search) || '%'
      )
    limit greatest(1, least(coalesce(p_limit, 40), 100))
  ), '[]'::jsonb);
end;
$function$;

GRANT EXECUTE ON FUNCTION public.get_mobile_employee_directory(text, integer) TO authenticated;

-- 3) get_my_mobile_team
CREATE OR REPLACE FUNCTION public.get_my_mobile_team(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_result jsonb;
begin
  if v_manager_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'people.employee.read',
      'requests.request.approve',
      'performance.kpi.manager_assess',
      'attendance.record.read'
    ])
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_manager_id
        and mr.relation_type = 'primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    )
  ) then
    raise exception 'manager workspace is not allowed' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'team', tm.name,
    'attendanceStatus', case
      when req.request_type = 'convoy' then 'convoy'
      when req.request_type = 'fundraising' then 'fundraising'
      when req.request_type = 'mission' then 'mission'
      when req.request_type = 'leave' then 'on_leave'
      when ad.status = 'on_leave' then 'on_leave'
      when ad.status in ('weekend','holiday') then ad.status
      when coalesce(ad.first_check_in, ae.event_at) is not null then
        case
          when ad.status = 'present'
            or coalesce(ad.work_minutes, 0) >= 480
            or (
              ad.first_check_in is not null and ad.last_check_out is not null
              and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
            )
            or (
              ad.last_check_out is null
              and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
            )
          then 'present'
          when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'late'
          else 'present'
        end
      when ad.status = 'absent' then 'absent'
      else 'not_recorded'
    end,
    'statusLabel', case
      when req.request_type = 'convoy' then 'في قافلة'
      when req.request_type = 'fundraising' then 'في فاندي'
      when req.request_type = 'mission' then 'في مأمورية'
      when req.request_type = 'leave' then 'في إجازة'
      when ad.status = 'on_leave' then 'في إجازة'
      when ad.status = 'weekend' then 'إجازة أسبوعية'
      when ad.status = 'holiday' then 'عطلة رسمية'
      when coalesce(ad.first_check_in, ae.event_at) is not null then
        case
          when ad.status = 'present'
            or coalesce(ad.work_minutes, 0) >= 480
            or (
              ad.first_check_in is not null and ad.last_check_out is not null
              and extract(epoch from (ad.last_check_out - ad.first_check_in)) >= 28800
            )
            or (
              ad.last_check_out is null
              and extract(epoch from ((now() at time zone 'Africa/Cairo') - coalesce(ad.first_check_in, ae.event_at))) >= 28800
            )
          then
            case
              when coalesce(ad.work_minutes, 0) > 480 or coalesce(ad.overtime_minutes, 0) > 0 then 'حاضر (إضافي)'
              else 'حاضر'
            end
          when ad.status = 'late' or coalesce(ad.late_minutes, 0) > 0 then 'متأخر'
          else 'حاضر'
        end
      when ad.status = 'absent' then 'غائب'
      else 'لم يسجل بعد'
    end,
    'activityTitle', req.activity_title,
    'lateMinutes', case
      when ad.status = 'present' or coalesce(ad.work_minutes, 0) >= 480 then 0
      else coalesce(ad.late_minutes, 0)
    end,
    'workMinutes', coalesce(ad.work_minutes, 0),
    'overtimeMinutes', coalesce(ad.overtime_minutes, case when coalesce(ad.work_minutes, 0) > 480 then coalesce(ad.work_minutes, 0) - 480 else 0 end),
    'firstCheckIn', coalesce(ad.first_check_in, ae.event_at),
    'lastCheckOut', ad.last_check_out,
    'pendingRequests', (
      select count(*) from public.requests r
      where r.employee_id = e.id and r.status = 'pending'
    ),
    'kpiStage', (
      select ke.current_stage
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    )
  ) order by e.full_name_ar), '[]'::jsonb)
  into v_result
  from (
    select child.*
    from public.manager_relations mr
    join public.employees child on child.id = mr.employee_id
    where mr.manager_employee_id = v_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= v_today
      and (mr.effective_to is null or mr.effective_to >= v_today)
      and child.is_active = true
      and child.is_deleted = false
      and (
        not public.is_employee_isolated(child.id)
        or public.can_view_isolated_employee(child.id)
      )
    order by child.full_name_ar
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  ) e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join lateral (
    select 
      r.request_type,
      coalesce(nullif(r.payload->>'location',''), nullif(r.payload->>'destination',''), nullif(r.title,'')) as activity_title
    from public.requests r
    where r.employee_id = e.id
      and r.status in ('approved', 'pending')
      and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
      and v_today between 
          coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date, r.created_at::date)
      and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date, r.created_at::date)
    order by case when r.status = 'approved' then 1 else 2 end,
             case r.request_type 
               when 'convoy' then 1
               when 'fundraising' then 2
               when 'mission' then 3
               when 'leave' then 4
               else 5
             end,
             r.created_at desc
    limit 1
  ) req on true
  left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
  left join lateral (
    select min(event_at) as event_at
    from public.attendance_events
    where employee_id = e.id and event_type = 'CHECK_IN'
      and (event_at at time zone 'Africa/Cairo')::date = v_today
      and status in ('accepted', 'adjusted')
  ) ae on true;

  return v_result;
end;
$function$;

GRANT EXECUTE ON FUNCTION public.get_my_mobile_team(integer) TO authenticated;
