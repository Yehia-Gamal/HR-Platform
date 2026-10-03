-- 0601_attendance_state_pending_missions.sql
-- إظهار طلبات المأموريات قيد المراجعة في get_my_attendance_state حتى يعلم الموظف أن طلبه تم رفعه وبانتظار الاعتماد

create or replace function public.get_my_attendance_state(p_installation_id text default null::text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_active boolean := false;
  v_is_executive boolean := false;
  v_local_devices integer := 0;
  v_passkeys integer := 0;
  v_local_device_status text := 'not_registered';
  v_current_device_status text := null;
  v_current_device_active boolean := false;
  v_last public.attendance_events;
  v_today_status text := null;
  v_today_check_in timestamptz := null;
  v_today_check_out timestamptz := null;
  v_suggested text := 'CHECK_IN';
  v_can_punch boolean := false;
  v_m_id uuid;
  v_m_type text;
  v_m_start_time text;
  v_m_exec text;
  v_m_started timestamptz;
  v_m_ended timestamptz;
  v_m_auto boolean := false;
  v_cutoff time;
  v_mission jsonb := null;
  v_hash text;
  v_is_split boolean := false;
  v_check_in_count integer := 0;
begin
  if v_me is null then
    return jsonb_build_object(
      'attendanceRequired',false,
      'selfPunchEnabled',false,
      'canPunch',false,
      'suggestedAction','CHECK_IN',
      'lastUpdatedAt',now(),
      'reason','no_employee_linked'
    );
  end if;

  select (e.status = 'active' and e.is_active and not coalesce(e.is_deleted,false))
  into v_active
  from public.employees e where e.id = v_me;
  v_active := coalesce(v_active, false);

  v_is_executive := public.is_executive_employee(v_me);
  v_is_split := public.is_employee_split_shift(v_me);

  -- 1) فحص الأجهزة المحلية المسجلة والموثوقة للموظف
  select count(*) into v_local_devices
  from public.managed_devices md
  where md.user_id = auth.uid() and md.employee_id = v_me
    and md.platform in ('android', 'ios') and md.status = 'active'
    and exists (
      select 1 from public.employee_devices ed
      where ed.employee_id = v_me and ed.user_id = auth.uid() and ed.status = 'active'
        and ed.device_identifier_hash = encode(
          digest(convert_to(md.installation_id, 'UTF8'), 'sha256'), 'hex'
        )
    );

  -- 2) فحص الجهاز الحالي المرسل عبر p_installation_id
  if p_installation_id is not null and length(trim(p_installation_id)) >= 12 then
    v_hash := encode(digest(convert_to(trim(p_installation_id), 'UTF8'), 'sha256'), 'hex');

    if exists (
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

  -- مفاتيح المرور (Passkeys)
  select count(*) into v_passkeys
  from public.passkey_credentials p
  where p.employee_id = v_me and p.user_id = auth.uid()
    and p.status = 'active' and p.trusted;

  -- آخر حدث حضور اليوم
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

  -- المأموريات (المعتمدة أو قيد المراجعة)
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
     and v_today between coalesce(nullif(r.payload->>'startDate','')::date, v_today)
                     and coalesce(nullif(r.payload->>'endDate','')::date, v_today)
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

    if v_last.id is null and v_m_exec <> 'pending' then
      if v_m_exec is null or v_m_exec = 'approved' then
        v_suggested := 'MISSION_START';
      elsif v_m_exec = 'in_progress' then
        v_suggested := 'MISSION_IN_PROGRESS';
      elsif v_m_exec = 'completed' then
        if v_m_auto then
          v_suggested := 'DAY_COMPLETED';
        elsif v_today_check_in is not null then
          v_suggested := 'CHECK_OUT';
        else
          v_suggested := 'CHECK_IN';
        end if;
      end if;
    elsif v_m_exec = 'completed' and v_m_auto and v_today_check_out is not null then
      v_suggested := 'DAY_COMPLETED';
    end if;

    v_mission := jsonb_build_object(
      'requestId', v_m_id,
      'type', v_m_type,
      'execStatus', coalesce(v_m_exec, 'pending'),
      'startTime', v_m_start_time,
      'startedAt', v_m_started,
      'endedAt', v_m_ended,
      'autoCheckout', v_m_auto
    );
  end if;

  v_can_punch := v_active and not v_is_executive and (
    case when p_installation_id is not null and length(trim(p_installation_id)) >= 12
         then v_current_device_active
         else v_local_devices > 0
    end
  );
  if v_suggested in ('MISSION_START','MISSION_IN_PROGRESS','DAY_COMPLETED') then
    v_can_punch := false;
  end if;

  return jsonb_build_object(
    'employeeId',v_me,
    'attendanceRequired',v_active and not v_is_executive,
    'selfPunchEnabled',v_active and not v_is_executive,
    'activeLocalDevices',v_local_devices,
    'hasActiveLocalDevice',v_local_devices > 0,
    'localDeviceStatus',v_local_device_status,
    'currentDeviceStatus',v_current_device_status,
    'currentDeviceActive',v_current_device_active,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys > 0,
    'canPunch',v_can_punch,
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    'todayCheckInAt',v_today_check_in,
    'todayCheckOutAt',v_today_check_out,
    'missionToday',v_mission,
    'isSplitShift',v_is_split,
    'checkInCount',v_check_in_count,
    'lastUpdatedAt',now()
  );
end;
$$;

revoke all on function public.get_my_attendance_state(text) from public, anon;
grant execute on function public.get_my_attendance_state(text) to authenticated;
comment on function public.get_my_attendance_state is 'الحالة اللحظية للحضور مع دعم المأموريات المعتمدة وقيد المراجعة.';
