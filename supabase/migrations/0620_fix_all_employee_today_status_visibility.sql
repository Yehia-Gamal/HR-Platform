-- 0620: Fix employee today status visibility across mobile attendance, executive summary, and employee registry.
-- إصلاح ظهور حالة الموظف اليومية في شاشة الحضور وملخص القيادة وسجل الموظفين

-- 1. تحديث get_my_attendance_state بحيث يحسب v_today_status تلقائياً ولا يتركه null
create or replace function public.get_my_attendance_state(
  p_installation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me                    uuid;
  v_today                 date := (now() at time zone 'Africa/Cairo')::date;
  v_is_split              boolean := false;
  v_hash                  text;
  v_last                  record;
  v_check_in_count        integer := 0;
  v_today_check_in        timestamptz;
  v_today_check_out       timestamptz;
  v_shift_end             timestamptz;
  v_local_device_status   text := 'not_registered';
  v_today_status          text;
  v_suggested             text;
  v_passkeys              integer;
  v_local_devices         integer;
  v_current_device_active boolean := false;
  v_current_device_status text;
  v_mission               jsonb := null;
  v_m_id                  uuid;
  v_m_type                text;
  v_m_start_time          text;
  v_m_exec                text;
  v_m_started             timestamptz;
  v_m_ended               timestamptz;
  v_cutoff                time;
  v_m_auto                boolean;
begin
  select employee_id into v_me
  from public.user_profiles
  where id = auth.uid();

  if v_me is null then
    return jsonb_build_object(
      'attendanceRequired', false,
      'selfPunchEnabled', false,
      'canPunch', false,
      'reason', 'NO_EMPLOYEE_LINKED'
    );
  end if;

  v_is_split := coalesce(public.is_employee_split_shift(v_me), false);

  select count(*) into v_local_devices
  from public.employee_devices ed
  where ed.employee_id = v_me
    and ed.user_id = auth.uid()
    and ed.status = 'active';

  if coalesce(v_local_devices, 0) = 0 then
    select count(*) into v_local_devices
    from public.managed_devices md
    where md.user_id = auth.uid()
      and md.employee_id = v_me
      and md.platform in ('android', 'ios')
      and md.status = 'active';
  end if;

  if p_installation_id is not null and trim(p_installation_id) <> '' then
    v_hash := encode(digest(trim(p_installation_id), 'sha256'), 'hex');

    if exists (
      select 1 from public.employee_devices ed
      where ed.employee_id = v_me
        and ed.user_id = auth.uid()
        and ed.device_identifier_hash = v_hash
        and ed.status = 'active'
    ) or exists (
      select 1 from public.managed_devices md
      where md.installation_id = trim(p_installation_id)
        and md.user_id = auth.uid()
        and md.employee_id = v_me
        and md.platform in ('android', 'ios')
        and md.status = 'active'
    ) then
      select ed.status into v_current_device_status
      from public.employee_devices ed
      where ed.employee_id = v_me
        and ed.user_id = auth.uid()
        and ed.device_identifier_hash = v_hash
      order by ed.created_at desc
      limit 1;

      if v_current_device_status = 'active' then
        v_current_device_active := true;
      end if;
    else
      select md.status into v_current_device_status
      from public.managed_devices md
      where md.installation_id = trim(p_installation_id)
        and md.user_id = auth.uid()
        and md.employee_id = v_me
      limit 1;

      if v_current_device_status is null then
        v_current_device_status := 'not_registered';
      end if;
    end if;
  end if;

  if v_local_devices > 0 then
    v_local_device_status := 'active';
  elsif v_current_device_status is not null then
    v_local_device_status := v_current_device_status;
  else
    perform 1 from public.employee_devices ed
    where ed.employee_id = v_me and ed.user_id = auth.uid() and ed.status = 'pending'
    limit 1;
    if found then
      v_local_device_status := 'pending';
    else
      perform 1 from public.managed_devices md
      where md.user_id = auth.uid() and md.employee_id = v_me
        and md.platform in ('android', 'ios')
        and md.status = 'pending'
      limit 1;
      if found then
        v_local_device_status := 'pending';
      end if;
    end if;
  end if;

  select count(*) into v_passkeys
  from public.passkey_credentials p
  where p.employee_id = v_me and p.user_id = auth.uid()
    and p.status = 'active' and p.trusted;

  select * into v_last from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  select status into v_today_status from public.attendance_daily
  where employee_id = v_me and work_date = v_today;

  select count(*) into v_check_in_count
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_IN'
    and status in ('accepted', 'adjusted');

  if v_last.id is not null and v_last.event_type = 'CHECK_IN' then
    v_suggested := 'CHECK_OUT';
  elsif v_last.id is not null and v_last.event_type = 'CHECK_OUT' then
    if v_is_split and v_check_in_count < 2 then
      v_suggested := 'CHECK_IN';
    else
      v_suggested := 'DAY_COMPLETED';
    end if;
  else
    v_suggested := 'CHECK_IN';
  end if;

  select event_at into v_today_check_in
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_IN'
    and status in ('accepted', 'adjusted')
  order by event_at asc limit 1;

  select event_at into v_today_check_out
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_OUT'
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  -- فحص المأموريات والأنشطة اليوم
  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');

  select r.id, r.request_type, nullif(r.payload->>'startTime',''),
         coalesce(x.exec_status, case when r.status = 'approved' then 'approved' else 'pending' end),
         x.started_at, x.ended_at
    into v_m_id, v_m_type, v_m_start_time, v_m_exec, v_m_started, v_m_ended
    from public.requests r
    left join lateral (
      select m.status as exec_status, m.started_at, m.ended_at
        from public.mission_executions m
       where m.request_id = r.id
       order by m.created_at desc
       limit 1
    ) x on true
   where r.employee_id = v_me
     and r.status in ('approved', 'pending')
     and r.request_type in ('mission','convoy','fundraising')
     and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date, r.created_at::date)
                     and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date, r.created_at::date)
   order by case when r.status = 'approved' then 1 else 2 end,
            x.started_at desc nulls last, r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;
    if v_today_check_out is null then
      select d.last_check_out into v_today_check_out
        from public.attendance_daily d
       where d.employee_id = v_me and d.work_date = v_today;
    end if;

    if v_m_exec = 'in_progress' then
      v_suggested := 'MISSION_IN_PROGRESS';
    elsif v_m_exec in ('approved', 'pending') and v_last.id is null then
      v_suggested := 'MISSION_START';
    elsif v_m_exec = 'completed' then
      if v_today_check_out is not null then
        v_suggested := 'DAY_COMPLETED';
      elsif v_today_check_in is not null then
        v_suggested := 'CHECK_OUT';
      else
        v_suggested := 'CHECK_IN';
      end if;
    end if;

    v_mission := jsonb_build_object(
      'requestId', v_m_id,
      'type', v_m_type,
      'startTime', v_m_start_time,
      'execStatus', v_m_exec,
      'startedAt', v_m_started,
      'endedAt', v_m_ended,
      'autoCheckout', coalesce(v_m_auto, false)
    );
  end if;

  -- إذا لم تسجل attendance_daily بعد (خلال اليوم)، نحسب الحالة الحية للموظف
  if v_today_status is null or v_today_status = '' then
    if v_m_id is not null and v_m_exec in ('approved', 'in_progress', 'completed') then
      v_today_status := case v_m_type
        when 'convoy' then 'convoy'
        when 'fundraising' then 'fundraising'
        when 'mission' then 'mission'
        else 'mission'
      end;
    elsif exists (
      select 1 from public.requests r
      where r.employee_id = v_me
        and r.status = 'approved'
        and r.request_type = 'leave'
        and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date, r.created_at::date)
                        and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date, r.created_at::date)
    ) then
      v_today_status := 'on_leave';
    elsif v_today_check_in is not null or v_last.id is not null then
      if coalesce(v_last.status, '') = 'late' or coalesce(v_last.late_minutes, 0) > 0 then
        v_today_status := 'late';
      else
        v_today_status := 'present';
      end if;
    elsif extract(dow from v_today) = 5 then
      v_today_status := 'weekend';
    elsif exists (select 1 from public.public_holidays where holiday_date = v_today) then
      v_today_status := 'holiday';
    elsif (now() at time zone 'Africa/Cairo')::time > '12:00:00'::time then
      v_today_status := 'absent';
    else
      v_today_status := 'not_recorded';
    end if;
  end if;

  select (v_today::text || ' ' || coalesce(s.shift_end_time, time '17:00')::text)::timestamptz
  into v_shift_end
  from public.attendance_settings s where s.singleton_key;

  return jsonb_build_object(
    'attendanceRequired', true,
    'selfPunchEnabled', true,
    'canPunch', true,
    'todayStatus', v_today_status,
    'lastEventType', v_last.event_type,
    'lastEventAt', v_last.event_at,
    'lastEventStatus', v_last.status,
    'suggestedAction', v_suggested,
    'hasPasskeys', v_passkeys > 0,
    'passkeysCount', v_passkeys,
    'hasActiveLocalDevice', coalesce(v_local_devices, 0) > 0,
    'activeLocalDevicesCount', coalesce(v_local_devices, 0),
    'currentDeviceActive', v_current_device_active,
    'currentDeviceStatus', v_current_device_status,
    'localDeviceStatus', v_local_device_status,
    'todayCheckInAt', v_today_check_in,
    'todayCheckOutAt', v_today_check_out,
    'shiftEndTime', v_shift_end,
    'isSplitShift', v_is_split,
    'checkInCount', v_check_in_count,
    'missionToday', v_mission
  );
end;
$$;


-- 2. تحديث get_mobile_executive_employee_summary لتضمين todayStatus
create or replace function public.get_mobile_executive_employee_summary(
  p_employee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed boolean;
  v_result jsonb;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'وصول ملخص الموظفين مرفوض' using errcode = '42501';
  end if;

  if not (public.current_is_full_access() or public.can_access_employee(p_employee_id,'people.employee.read')) then
    raise exception 'FORBIDDEN: لا تملك صلاحية رؤية ملف هذا الموظف' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'status', e.status,
    'jobTitle', jt.name,
    'position', p.name,
    'department', d.name,
    'team', tm.name,
    'branch', b.name,
    'workSite', ws.name,
    'managerName', manager.full_name_ar,
    'hireDate', e.hire_date,
    'pendingRequests', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending'),
    'openTasks', (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')),
    'expiringDocuments', (select count(*) from public.documents doc where doc.owner_employee_id = e.id and doc.status <> 'archived' and doc.expiry_date <= current_date + 60),
    'latestKpi', (
      select jsonb_build_object('score', ke.final_score, 'rating', ke.final_rating, 'stage', ke.current_stage, 'periodMonth', kc.period_month)
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    ),
    'todayStatus', (
      with req as (
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
                 case r.request_type when 'convoy' then 1 when 'fundraising' then 2 when 'mission' then 3 when 'leave' then 4 else 5 end,
                 r.created_at desc
        limit 1
      ),
      att as (
        select status, first_check_in, last_check_out, late_minutes, work_minutes
        from public.attendance_daily
        where employee_id = e.id and work_date = v_today
        limit 1
      ),
      ae as (
        select min(event_at) as event_at
        from public.attendance_events
        where employee_id = e.id and event_type = 'CHECK_IN'
          and (event_at at time zone 'Africa/Cairo')::date = v_today
          and status in ('accepted', 'adjusted')
      )
      select jsonb_build_object(
        'status', case
          when (select request_type from req) = 'convoy' then 'convoy'
          when (select request_type from req) = 'fundraising' then 'fundraising'
          when (select request_type from req) = 'mission' then 'mission'
          when (select request_type from req) = 'leave' then 'on_leave'
          when (select status from att) = 'on_leave' then 'on_leave'
          when (select status from att) in ('weekend','holiday') then (select status from att)
          when coalesce((select first_check_in from att), (select event_at from ae)) is not null then
            case when coalesce((select late_minutes from att), 0) > 0 or (select status from att) = 'late' then 'late' else 'present' end
          when (select status from att) = 'absent' then 'absent'
          when extract(dow from v_today) = 5 then 'weekend'
          when exists (select 1 from public.public_holidays where holiday_date = v_today) then 'holiday'
          when (now() at time zone 'Africa/Cairo')::time > '12:00:00'::time then 'absent'
          else 'not_recorded'
        end,
        'statusLabel', case
          when (select request_type from req) = 'convoy' then coalesce((select activity_title from req), 'في قافلة')
          when (select request_type from req) = 'fundraising' then coalesce((select activity_title from req), 'في فاندي')
          when (select request_type from req) = 'mission' then coalesce((select activity_title from req), 'في مأمورية')
          when (select request_type from req) = 'leave' then 'في إجازة'
          when (select status from att) = 'on_leave' then 'في إجازة'
          when (select status from att) = 'weekend' then 'إجازة أسبوعية'
          when (select status from att) = 'holiday' then 'عطلة رسمية'
          when coalesce((select first_check_in from att), (select event_at from ae)) is not null then
            case when coalesce((select late_minutes from att), 0) > 0 or (select status from att) = 'late' then 'متأخر' else 'حاضر' end
          when (select status from att) = 'absent' then 'غائب'
          when extract(dow from v_today) = 5 then 'إجازة أسبوعية'
          when exists (select 1 from public.public_holidays where holiday_date = v_today) then 'عطلة رسمية'
          when (now() at time zone 'Africa/Cairo')::time > '12:00:00'::time then 'غائب'
          else 'لم يسجل'
        end,
        'activityTitle', (select activity_title from req),
        'checkInAt', coalesce((select first_check_in from att), (select event_at from ae)),
        'checkOutAt', (select last_check_out from att),
        'lateMinutes', coalesce((select late_minutes from att), 0),
        'workMinutes', coalesce((select work_minutes from att), 0)
      )
    ),
    'recentAttendance', coalesce((
      select jsonb_agg(jsonb_build_object(
        'workDate', a.work_date,
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'workMinutes', a.work_minutes,
        'firstCheckIn', a.first_check_in,
        'lastCheckOut', a.last_check_out
      ) order by a.work_date desc)
      from (
        select * from public.attendance_daily
        where employee_id = e.id
        order by work_date desc
        limit 14
      ) a
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  ) into v_result
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions p on p.id = e.position_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join public.branches b on b.id = e.branch_id
  left join public.work_sites ws on ws.id = e.work_site_id
  left join lateral (
    select me.full_name_ar
    from public.manager_relations mr
    join public.employees me on me.id = mr.manager_employee_id
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= v_today
      and (mr.effective_to is null or mr.effective_to >= v_today)
    order by mr.effective_from desc
    limit 1
  ) manager on true
  where e.id = p_employee_id;

  return v_result;
end;
$$;


-- 3. تحديث get_mobile_employees لتضمين statusToday و statusTodayLabel
create or replace function public.get_mobile_employees(
  p_search text default null,
  p_department_id uuid default null,
  p_status text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', e.id,
      'fullNameAr', e.full_name_ar,
      'fullNameEn', e.full_name_en,
      'employeeCode', e.employee_code,
      'photoUrl', e.photo_url,
      'jobTitle', jt.name,
      'department', d.name,
      'team', tm.name,
      'branch', b.name,
      'status', e.status,
      'isActive', e.is_active,
      'statusToday', today_st.computed_status,
      'statusTodayLabel', today_st.computed_label,
      'activityTitle', today_st.activity_title
    ) order by e.full_name_ar)
    from (
      select * from public.employees
      where is_deleted = false
        and (p_department_id is null or department_id = p_department_id)
        and (p_status is null or status = p_status)
        and (
          p_search is null
          or trim(p_search) = ''
          or full_name_ar ilike '%' || trim(p_search) || '%'
          or full_name_en ilike '%' || trim(p_search) || '%'
          or employee_code ilike '%' || trim(p_search) || '%'
        )
      limit coalesce(nullif(p_limit, 0), 100)
      offset coalesce(p_offset, 0)
    ) e
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.departments d on d.id = e.department_id
    left join public.teams tm on tm.id = e.team_id
    left join public.branches b on b.id = e.branch_id
    cross join lateral (
      with req as (
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
                 case r.request_type when 'convoy' then 1 when 'fundraising' then 2 when 'mission' then 3 when 'leave' then 4 else 5 end,
                 r.created_at desc
        limit 1
      ),
      att as (
        select status, first_check_in, last_check_out, late_minutes, work_minutes
        from public.attendance_daily
        where employee_id = e.id and work_date = v_today
        limit 1
      ),
      ae as (
        select min(event_at) as event_at
        from public.attendance_events
        where employee_id = e.id and event_type = 'CHECK_IN'
          and (event_at at time zone 'Africa/Cairo')::date = v_today
          and status in ('accepted', 'adjusted')
      )
      select
        case
          when (select request_type from req) = 'convoy' then 'convoy'
          when (select request_type from req) = 'fundraising' then 'fundraising'
          when (select request_type from req) = 'mission' then 'mission'
          when (select request_type from req) = 'leave' then 'on_leave'
          when (select status from att) = 'on_leave' then 'on_leave'
          when (select status from att) in ('weekend','holiday') then (select status from att)
          when coalesce((select first_check_in from att), (select event_at from ae)) is not null then
            case when coalesce((select late_minutes from att), 0) > 0 or (select status from att) = 'late' then 'late' else 'present' end
          when (select status from att) = 'absent' then 'absent'
          when extract(dow from v_today) = 5 then 'weekend'
          when exists (select 1 from public.public_holidays where holiday_date = v_today) then 'holiday'
          when (now() at time zone 'Africa/Cairo')::time > '12:00:00'::time then 'absent'
          else 'not_recorded'
        end as computed_status,
        case
          when (select request_type from req) = 'convoy' then coalesce((select activity_title from req), 'في قافلة')
          when (select request_type from req) = 'fundraising' then coalesce((select activity_title from req), 'في فاندي')
          when (select request_type from req) = 'mission' then coalesce((select activity_title from req), 'في مأمورية')
          when (select request_type from req) = 'leave' then 'في إجازة'
          when (select status from att) = 'on_leave' then 'في إجازة'
          when (select status from att) = 'weekend' then 'إجازة أسبوعية'
          when (select status from att) = 'holiday' then 'عطلة رسمية'
          when coalesce((select first_check_in from att), (select event_at from ae)) is not null then
            case when coalesce((select late_minutes from att), 0) > 0 or (select status from att) = 'late' then 'متأخر' else 'حاضر' end
          when (select status from att) = 'absent' then 'غائب'
          when extract(dow from v_today) = 5 then 'إجازة أسبوعية'
          when exists (select 1 from public.public_holidays where holiday_date = v_today) then 'عطلة رسمية'
          when (now() at time zone 'Africa/Cairo')::time > '12:00:00'::time then 'غائب'
          else 'لم يسجل'
        end as computed_label,
        (select activity_title from req) as activity_title
    ) today_st
    where public.can_see_directory_entry(public.current_employee_id(), e.id)
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.get_my_attendance_state(text) to authenticated;
grant execute on function public.get_mobile_executive_employee_summary(uuid) to authenticated;
grant execute on function public.get_mobile_employees(text, uuid, text, integer, integer) to authenticated;
