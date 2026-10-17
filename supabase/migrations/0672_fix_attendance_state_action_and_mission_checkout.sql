-- ==============================================================================
-- Migration 0672: تصحيح الإجراء المقترح للبصمة وتفادي خطأ attendance_check_out_required
-- ==============================================================================
-- المشكلة:
-- 1. الموظف عندما يسجل حضوراً بمأمورية أو حضور عادي، كانت دالة get_my_attendance_state
--    تضبط suggestedAction إلى 'MISSION_IN_PROGRESS' بدلاً من 'CHECK_OUT'.
-- 2. في تطبيق الموبايل، أي قيمة غير 'CHECK_OUT' تسقط افتراضياً إلى 'CHECK_IN'
--    فيظهر للموظف زر "تسجيل الحضور" بالرغم من أنه حاضر بالفعل!
-- 3. عند الضغط على الزر، يرسل التطبيق CHECK_IN فيرفضه الخادم بالخطأ:
--    attendance_check_out_required ("يجب تسجيل الانصراف أولاً قبل حضور جديد").
--
-- الحل الجذري:
-- 1. تحديث get_my_attendance_state: طالما أن الموظف مسجل حضور اليوم ولم يسجل انصرافاً بعد
--    (سواء بحضور عادي أو مأمورية جارية أو تعديل إداري)، فالإجراء المقترح للبصمة هو حتماً 'CHECK_OUT'.
-- 2. في record_attendance_local_biometric:
--    - التحقق من آخر حدث مع الرجوع لسجل attendance_daily اليومي كـ fallback.
--    - السماح بالانصراف الميداني (field check-out) عند وجود مأمورية جارية أو معتمدة لليوم
--      حتى لو كان خارج نطاق مقر الجمعية الجغرافي.
--    - إغلاق سجل المأمورية الجارية تلقائياً عند تسجيل بصمة الانصراف.
-- ==============================================================================

begin;

-- ─── 1) تحديث get_my_attendance_state ─────────────────────────────────────────
create or replace function public.get_my_attendance_state(
  p_installation_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
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
  v_me := public.current_employee_id();

  if v_me is null then
    return jsonb_build_object(
      'attendanceRequired', false,
      'selfPunchEnabled', false,
      'canPunch', false,
      'reason', 'no_employee_linked'
    );
  end if;

  -- سياسة الإعفاء الموحّدة
  if public.is_employee_attendance_exempt(v_me) then
    return jsonb_build_object(
      'attendanceRequired', false,
      'selfPunchEnabled', false,
      'canPunch', false,
      'reason', 'executive_exempt'
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

  -- آخر حدث حضور/انصراف مسجل اليوم
  select * into v_last from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and status in ('accepted', 'adjusted')
  order by event_at desc limit 1;

  -- حالة اليوم اليومية المسجلة
  select status into v_today_status from public.attendance_daily
  where employee_id = v_me and work_date = v_today;

  select count(*) into v_check_in_count
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
    and event_type = 'CHECK_IN'
    and status in ('accepted', 'adjusted');

  -- جلب توقيت أول حضور وآخر انصراف اليوم
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

  -- fallback لسجل attendance_daily في حال التعديلات الإدارية أو غياب الأحداث
  if v_today_check_in is null then
    select d.first_check_in into v_today_check_in
      from public.attendance_daily d
     where d.employee_id = v_me and d.work_date = v_today;
  end if;

  if v_today_check_out is null then
    select d.last_check_out into v_today_check_out
      from public.attendance_daily d
     where d.employee_id = v_me and d.work_date = v_today;
  end if;

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
     and v_today between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                     and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
   order by case when r.status = 'approved' then 1 else 2 end,
            x.started_at desc nulls last, r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;
    if v_today_check_out is null and v_m_ended is not null then
      v_today_check_out := v_m_ended;
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

  -- ── حسم الإجراء المقترح (suggestedAction) بدقة تامة تمنع أي تضارب ──
  -- 1) إذا كان اليوم مكتملاً بانصراف موثق (والوردية عادية أو اكتملت فتراتها):
  if v_today_check_out is not null and (not v_is_split or v_check_in_count >= 2) then
    v_suggested := 'DAY_COMPLETED';
  -- 2) إذا كانت وردية مجزأة وتم انصراف الفترة الأولى وبانتظار حضور الفترة الثانية:
  elsif v_today_check_out is not null and v_is_split and v_check_in_count < 2 then
    v_suggested := 'CHECK_IN';
  -- 3) إذا كان الموظف مسجل حضور بالفعل اليوم ولم ينصرف بعد (سواء حضور عادي، مأمورية جارية، أو تعديل إداري):
  -- فالإجراء الوحيد الممكن والمسموح به للبصمة هو تسجيل الانصراف!
  elsif v_today_check_in is not null or (v_last.id is not null and v_last.event_type = 'CHECK_IN') then
    v_suggested := 'CHECK_OUT';
  -- 4) إذا لم يبصم حضوراً بعد ولديه مأمورية معتمدة لليوم لم تبدأ بعد:
  elsif v_m_id is not null and v_m_exec in ('approved', 'pending') and v_last.id is null and v_today_check_in is null then
    v_suggested := 'MISSION_START';
  -- 5) خلاف ذلك: بانتظار تسجيل الحضور
  else
    v_suggested := 'CHECK_IN';
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
        and v_today between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                        and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
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

revoke all on function public.get_my_attendance_state(text) from public, anon;
grant execute on function public.get_my_attendance_state(text) to authenticated;
comment on function public.get_my_attendance_state(text) is
  '0672: الحالة اللحظية للحضور مع تصحيح suggestedAction ليكون CHECK_OUT حتماً عند وجود حضور قائم.';


-- ─── 2) تحديث record_attendance_local_biometric ──────────────────────────────
create or replace function public.record_attendance_local_biometric(
  p_employee_id uuid,
  p_event_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_is_mock boolean default false
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_event_id uuid;
  v_assignment public.shift_assignments%rowtype;
  v_geofence public.geofences%rowtype;
  v_shift public.shifts%rowtype;
  v_roster_shift_id uuid;
  v_roster_geofence_id uuid;
  v_now timestamptz := now();
  v_tz text;
  v_local_time time;
  v_work_date date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
  v_crosses_midnight boolean := false;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_prev_at timestamptz;
  v_prev_lat double precision;
  v_prev_lon double precision;
  v_gap_seconds numeric;
  v_travel double precision;
  v_impossible_speed numeric;
  v_requires_review boolean := false;
  v_notes text := 'inside_complex_local_biometric';
  v_max_accuracy numeric;
begin
  select s.timezone, s.impossible_travel_speed_mps, s.accuracy_max_default_meters
    into v_tz, v_impossible_speed, v_max_accuracy
  from public.attendance_settings s
  limit 1;
  v_tz := coalesce(v_tz, 'Africa/Cairo');
  v_impossible_speed := coalesce(v_impossible_speed, 42);
  v_max_accuracy := coalesce(v_max_accuracy, 100);

  v_local_time := (v_now at time zone v_tz)::time;
  v_work_date := (v_now at time zone v_tz)::date;

  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if p_employee_id is null then
    raise exception 'attendance_identity_not_verified' using errcode = '28000';
  end if;
  if p_is_mock then
    raise exception 'attendance_mock_location_rejected' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'attendance_location_required' using errcode = '22023';
  end if;
  if p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180
     or p_accuracy_meters < 0 or p_accuracy_meters > 10000 then
    raise exception 'invalid_attendance_location' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id = p_employee_id
      and ae.event_type = p_event_type
      and ae.event_at > v_now - interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode = '23505';
  end if;

  select rd.shift_id, rd.geofence_id
    into v_roster_shift_id, v_roster_geofence_id
  from public.roster_days rd
  join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
  where rd.employee_id = p_employee_id
    and rd.work_date = v_work_date
    and rd.day_status = 'scheduled'
  order by wr.published_at desc nulls last
  limit 1;

  select * into v_assignment
  from public.shift_assignments sa
  where sa.employee_id = p_employee_id
    and sa.is_active = true
    and sa.effective_from <= v_work_date
    and (sa.effective_to is null or sa.effective_to >= v_work_date)
  order by sa.effective_from desc
  limit 1;

  if coalesce(v_roster_shift_id, v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id = coalesce(v_roster_shift_id, v_assignment.shift_id);
  end if;

  if v_crosses_midnight and v_shift.id is not null then
    v_period_start := (v_work_date + v_shift.start_time) at time zone v_tz;
    v_period_end   := ((v_work_date + 1) + v_shift.end_time) at time zone v_tz;
  else
    v_period_start := v_work_date::timestamp at time zone v_tz;
    v_period_end   := (v_work_date + 1)::timestamp at time zone v_tz;
  end if;

  if exists (
    select 1 from public.attendance_daily
    where employee_id = p_employee_id
      and work_date = v_work_date
      and is_finalized = true
  ) then
    raise exception 'attendance_period_finalized' using errcode = '55000';
  end if;

  select ae.event_at, ae.latitude, ae.longitude
    into v_prev_at, v_prev_lat, v_prev_lon
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.latitude is not null and ae.longitude is not null
    and ae.event_at > v_now - interval '6 hours'
  order by ae.event_at desc
  limit 1;

  if v_prev_at is not null then
    v_gap_seconds := greatest(extract(epoch from (v_now - v_prev_at)), 1);
    v_travel := public.geo_distance_meters(
      p_latitude, p_longitude, v_prev_lat, v_prev_lon
    );
    if v_travel is not null and (v_travel / v_gap_seconds) > v_impossible_speed then
      v_requires_review := true;
      v_notes := v_notes || ',impossible_travel';
    end if;
  end if;

  -- استعلام آخر حدث حضور مع الـ fallback لسجل attendance_daily
  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id = p_employee_id
    and ae.event_at >= v_period_start
    and ae.event_at < v_period_end
    and ae.status in ('accepted', 'adjusted')
  order by ae.event_at desc
  limit 1;

  if v_last_event_type is null then
    select case
      when ad.last_check_out is not null then 'CHECK_OUT'
      when ad.first_check_in is not null then 'CHECK_IN'
      else null
    end into v_last_event_type
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id
      and ad.work_date = v_work_date;
  end if;

  if p_event_type = 'CHECK_OUT' and v_last_event_type is distinct from 'CHECK_IN' then
    raise exception 'attendance_check_in_required' using errcode = '22023';
  end if;
  if p_event_type = 'CHECK_IN' and v_last_event_type = 'CHECK_IN' then
    raise exception 'attendance_check_out_required' using errcode = '22023';
  end if;

  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_roster_geofence_id and is_active = true;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id = v_assignment.geofence_id and is_active = true;
  end if;

  if v_geofence.id is null then
    select * into v_geofence from public.geofences
    where is_active = true
    order by created_at
    limit 1;
  end if;

  if v_geofence.id is null then
    raise exception 'attendance_geofence_not_configured' using errcode = '55000';
  end if;

  v_distance := public.geo_distance_meters(
    p_latitude, p_longitude, v_geofence.latitude, v_geofence.longitude
  )::numeric(12,2);

  -- التحقق من النطاق الجغرافي مع استثناء الانصراف الميداني للمأموريات
  if v_distance > v_geofence.radius_meters then
    if p_event_type = 'CHECK_OUT' and (
      exists (
        select 1 from public.mission_executions me
         where me.employee_id = p_employee_id
           and me.status in ('in_progress', 'completed')
           and (me.started_at at time zone 'Africa/Cairo')::date = v_work_date
      ) or exists (
        select 1 from public.requests r
         where r.employee_id = p_employee_id
           and r.status in ('approved', 'pending')
           and r.request_type in ('mission', 'convoy', 'fundraising')
           and v_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), r.created_at::date)
                               and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), r.created_at::date)
      )
    ) then
      v_notes := 'mission_field_checkout';
    else
      raise exception 'attendance_outside_complex' using errcode = '22023';
    end if;
  end if;

  if coalesce(v_geofence.max_accuracy, v_max_accuracy) is not null
     and p_accuracy_meters > coalesce(v_geofence.max_accuracy, v_max_accuracy) then
    raise exception 'attendance_location_accuracy_too_low' using errcode = '22023';
  end if;

  -- حساب التأخير عند تسجيل أول حضور
  if p_event_type = 'CHECK_IN' and not exists (
    select 1 from public.attendance_events ae_prev
    where ae_prev.employee_id = p_employee_id
      and ae_prev.event_type = 'CHECK_IN'
      and ae_prev.status in ('accepted', 'adjusted')
      and ae_prev.event_at >= v_period_start
      and ae_prev.event_at < v_period_end
  ) then
    begin
      v_late := public.attendance_policy_late_minutes(p_employee_id, v_work_date, v_now, v_shift.id);
    exception when others then
      v_late := 0;
    end;
  end if;

  -- إدراج حدث الحضور/الانصراف
  insert into public.attendance_events (
    employee_id, shift_assignment_id, geofence_id, event_type, event_at,
    latitude, longitude, accuracy_meters, distance_meters, status,
    late_minutes, requires_review, verification_status,
    passkey_credential_id, biometric_method, selfie_path, server_verified,
    is_mock_location, notes, source, created_by
  ) values (
    p_employee_id, v_assignment.id, v_geofence.id, p_event_type, v_now,
    p_latitude, p_longitude, p_accuracy_meters, v_distance,
    case when v_requires_review then 'flagged' else 'accepted' end,
    v_late, v_requires_review, 'biometric_verified',
    null, 'fingerprint', null, true, false,
    v_notes, 'mobile', null
  ) returning id into v_event_id;

  -- تجميع بيانات الحضور اليومي في attendance_daily
  select min(event_at) filter (where event_type = 'CHECK_IN'),
         max(event_at) filter (where event_type = 'CHECK_OUT')
    into v_first_check_in, v_last_check_out
  from public.attendance_events
  where employee_id = p_employee_id
    and event_at >= v_period_start
    and event_at < v_period_end
    and status in ('accepted', 'adjusted');

  insert into public.attendance_daily (
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    work_minutes, late_minutes, status, is_finalized, created_by
  ) values (
    p_employee_id, v_work_date, coalesce(v_roster_shift_id, v_assignment.shift_id, public.match_flexible_shift(v_first_check_in)),
    v_first_check_in, v_last_check_out,
    case when v_first_check_in is not null and v_last_check_out is not null
      then greatest(0, floor(extract(epoch from (v_last_check_out - v_first_check_in)) / 60)::integer)
      else 0 end,
    v_late,
    case
      when v_first_check_in is null then 'partial'
      when v_late > 0 then 'late'
      else 'present'
    end,
    false, null
  )
  on conflict on constraint attendance_daily_uq do update set
    shift_id = coalesce(excluded.shift_id, attendance_daily.shift_id),
    first_check_in = coalesce(excluded.first_check_in, attendance_daily.first_check_in),
    last_check_out = coalesce(excluded.last_check_out, attendance_daily.last_check_out),
    work_minutes = excluded.work_minutes,
    late_minutes = greatest(attendance_daily.late_minutes, excluded.late_minutes),
    status = case
      when attendance_daily.status in ('on_leave', 'holiday', 'weekend')
        then attendance_daily.status
      when excluded.first_check_in is null then 'partial'
      when greatest(attendance_daily.late_minutes, excluded.late_minutes) > 0 then 'late'
      else 'present'
    end,
    updated_at = now();

  -- عند تسجيل الانصراف: إغلاق أي مأمورية جارية لليوم تلقائياً
  if p_event_type = 'CHECK_OUT' then
    update public.mission_executions
       set status = 'completed',
           ended_at = coalesce(ended_at, v_now),
           actual_minutes = greatest(1, round(extract(epoch from (v_now - started_at)) / 60)::integer),
           report = coalesce(report, 'تم تسجيل الانصراف وتوثيق إنهاء المأمورية بنجاح'),
           updated_at = v_now
     where employee_id = p_employee_id
       and status = 'in_progress'
       and (started_at at time zone 'Africa/Cairo')::date = v_work_date;
  end if;

  return v_event_id;
end;
$function$;

revoke all on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) from public, anon;
grant execute on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) to service_role;
comment on function public.record_attendance_local_biometric is
  '0672: تسجيل الحضور البيومتري مع fallback لسجل attendance_daily ودعم الانصراف الميداني للمأموريات.';

commit;
