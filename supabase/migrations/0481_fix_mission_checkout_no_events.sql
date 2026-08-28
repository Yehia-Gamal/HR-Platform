-- ============================================================================
-- 0481: إصلاح زر الانصراف بعد إنهاء المأمورية (بدون بصمة حضور في attendance_events)
-- ============================================================================
-- البلاغ: الموظف ينهي المأمورية قبل نهاية الدوام، يظهر زر "تسجيل الانصراف"
-- لكن عند الضغط → خطأ "يجب تسجيل الحضور أولاً قبل الانصراف".
--
-- السبب الجذري:
--   end_my_mission (0450) يكتب فقط في attendance_daily (upsert مع first_check_in)،
--   لكنه لا يُنشئ سجلًا في attendance_events.
--   get_my_attendance_state يستنتج CHECK_OUT من بيانات attendance_daily + mission_executions
--   لكن record_attendance_local_biometric يتحقق من attendance_events فقط → فشل.
--
-- الإصلاح (مجزأان):
--   1) end_my_mission: عند الإنهاء قبل نهاية الدوام، يُنشئ أيضًا حدث CHECK_IN
--      في attendance_events (status='adjusted', source='mission_auto') حتى يمرّ
--      تسلسل record_attendance_local_biometric.
--   2) get_my_attendance_state: حماية للبيانات القديمة — إذا كانت المأمورية
--      منتهية ولم يكن هناك حدث CHECK_IN في attendance_events، يقترح CHECK_IN
--      بدلاً من CHECK_OUT (لأن الموظف يحتاج بصمة حضور أولاً).
-- ============================================================================

begin;

-- ─── 1) إصلاح end_my_mission ───────────────────────────────────────────────
create or replace function public.end_my_mission(
  p_request_id uuid,
  p_report text,
  p_outcome text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me      uuid := public.current_employee_id();
  v_exec    public.mission_executions;
  v_minutes integer;
  v_today   date := (now() at time zone 'Africa/Cairo')::date;
  v_cutoff  time;
  v_end_now time := (now() at time zone 'Africa/Cairo')::time;
  v_auto    boolean;
  v_geofence_id uuid;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select * into v_exec from public.mission_executions where request_id = p_request_id;
  if not found then
    raise exception 'execution not started' using errcode = 'P0002';
  end if;
  if v_exec.employee_id <> v_me then
    raise exception 'mission ownership required' using errcode = '42501';
  end if;
  if v_exec.status <> 'in_progress' then
    raise exception 'execution already finished' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_report, ''))) < 3 then
    raise exception 'report is required (min 3 chars)' using errcode = '22023';
  end if;

  v_minutes := greatest(1, round(extract(epoch from (now() - v_exec.started_at)) / 60)::integer);

  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');
  v_auto := v_end_now >= v_cutoff;

  update public.mission_executions
     set ended_at         = now(),
         actual_minutes   = v_minutes,
         report           = trim(p_report),
         outcome          = nullif(trim(coalesce(p_outcome, '')), ''),
         status           = 'completed',
         updated_at       = now()
   where id = v_exec.id;

  --attendance_daily (نفس0450): تسجيل الحضور والانصراف اليومي
  insert into public.attendance_daily
    (employee_id, work_date, status, first_check_in, last_check_out, work_minutes, updated_at)
  values
    (v_me,
     v_today,
     'present',
     v_exec.started_at,
     case when v_auto then now() end,
     v_minutes,
     now())
  on conflict (employee_id, work_date) do update
    set first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
        last_check_out = coalesce(public.attendance_daily.last_check_out, excluded.last_check_out),
        work_minutes   = greatest(public.attendance_daily.work_minutes, excluded.work_minutes),
        status         = case
                           when public.attendance_daily.status in ('absent','missing_checkout','pending')
                             then 'present'
                           else public.attendance_daily.status
                         end,
        updated_at     = now();

  -- 0481: عند الإنهاء قبل نهاية الدوام (انصراف يدوي)، يُنشئ حدث CHECK_IN
  -- في attendance_events حتى يتوافق التسلسل مع record_attendance_local_biometric.
  -- بدون هذا، يرفض التسجيل بـ 'attendance_check_in_required'.
  if not v_auto then
    select id into v_geofence_id
      from public.geofences where is_active = true
      order by created_at limit 1;

    insert into public.attendance_events (
      employee_id, geofence_id, event_type, event_at, status,
      requires_review, verification_status, server_verified,
      is_mock_location, source, notes
    ) values (
      v_me, v_geofence_id, 'CHECK_IN', v_exec.started_at, 'adjusted',
      true, 'server_verified', true,
      false, 'mission_auto', 'auto_check_in_from_mission_end'
    );
  end if;

  return v_exec.id;
end $$;

revoke execute on function public.end_my_mission(uuid, text, text) from public, anon;
grant  execute on function public.end_my_mission(uuid, text, text) to authenticated;

-- ─── 2) إصلاح get_my_attendance_state — حماية للبيانات القديمة ──────────────
-- عندما تكون المأمورية منتهية ولم يكن هناك حدث CHECK_IN في attendance_events
-- (بيانات قديمة قبل0481)، يقترح CHECK_IN بدلاً من CHECK_OUT حتى لا يظهر
-- زر الانصراف الذي سيفشل.
create or replace function public.get_my_attendance_state(
  p_installation_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_active boolean;
  v_local_devices integer := 0;
  v_local_device_status text;
  v_current_device_active boolean := false;
  v_current_device_status text;
  v_passkeys integer := 0;
  v_last public.attendance_events;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_today_status text;
  v_suggested text := 'CHECK_IN';
  v_hash text;
  v_today_check_in timestamptz;
  v_today_check_out timestamptz;
  --0450: متغيرات يوم المأمورية
  v_cutoff time;
  v_m_id uuid;
  v_m_type text;
  v_m_start_time text;
  v_m_exec text;
  v_m_started timestamptz;
  v_m_ended timestamptz;
  v_m_auto boolean := false;
  v_can_punch boolean;
  v_mission jsonb;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select e.is_active and not coalesce(e.is_deleted, false), exists(
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.slug in ('executive','executive-director')
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
  ) into v_active, v_is_executive
  from public.employees e where e.id = v_me;

  select count(*) into v_local_devices
  from public.managed_devices md
  where md.user_id=auth.uid() and md.employee_id=v_me
    and md.platform in ('android','ios') and md.status='active'
    and exists (
      select 1 from public.employee_devices ed
      where ed.employee_id=v_me and ed.user_id=auth.uid() and ed.status='active'
        and ed.device_identifier_hash=encode(
          digest(convert_to(md.installation_id,'UTF8'),'sha256'),'hex'
        )
    );

  if p_installation_id is not null and length(trim(p_installation_id)) >= 12 then
    v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');

    if exists (
      select 1 from public.managed_devices md
      where md.installation_id = p_installation_id
        and md.user_id = auth.uid()
        and md.employee_id = v_me
        and md.platform in ('android','ios')
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
      where md.installation_id = p_installation_id
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
  else
    perform 1 from public.employee_devices ed
    where ed.employee_id = v_me and ed.user_id = auth.uid() and ed.status = 'pending'
    limit 1;
    if found then
      v_local_device_status := 'pending';
    else
      perform 1 from public.managed_devices md
      where md.user_id = auth.uid() and md.employee_id = v_me
        and md.platform in ('android','ios')
        and md.status = 'pending'
      limit 1;
      if found then
        v_local_device_status := 'pending';
      end if;
    end if;
  end if;

  select count(*) into v_passkeys
  from public.passkey_credentials p
  where p.employee_id=v_me and p.user_id=auth.uid()
    and p.status='active' and p.trusted;

  select * into v_last from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
  order by event_at desc limit 1;
  select status into v_today_status from public.attendance_daily
  where employee_id=v_me and work_date=v_today;
  if v_last.id is not null and v_last.event_type='CHECK_IN' then
    v_suggested := 'CHECK_OUT';
  end if;

  select event_at into v_today_check_in
  from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and event_type='CHECK_IN'
  order by event_at asc limit 1;

  select event_at into v_today_check_out
  from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and event_type='CHECK_OUT'
  order by event_at desc limit 1;

  --0450: يوم المأمورية
  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');

  select r.id, r.request_type, nullif(r.payload->>'startTime',''),
         x.exec_status, x.started_at, x.ended_at
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
     and r.status = 'approved'
     and r.request_type in ('mission','convoy','fundraising')
     and v_today between coalesce(nullif(r.payload->>'startDate','')::date, v_today)
                     and coalesce(nullif(r.payload->>'endDate','')::date, v_today)
   order by x.started_at desc nulls last, r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    --بدائل التوقيتات من المأمورية عندما لا توجد بصمات فعلية
    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;
    if v_today_check_out is null then
      select d.last_check_out into v_today_check_out
        from public.attendance_daily d
       where d.employee_id=v_me and d.work_date=v_today;
    end if;

    -- قواعد الزر الرئيسي — فقط عندما لا تكون هناك بصمة فعلية اليوم
    if v_last.id is null then
      if v_m_exec is null then
        v_suggested := 'MISSION_START';
      elsif v_m_exec = 'in_progress' then
        v_suggested := 'MISSION_IN_PROGRESS';
      elsif v_m_exec = 'completed' then
        -- 0481: إذا كانت المأمورية منتهية ولم يكن هناك حدث CHECK_IN في
        -- attendance_events (بيانات قديمة قبل0481)، نقترح CHECK_IN بدلاً
        -- من CHECK_OUT حتى لا يظهر زر الانصراف الذي سيفشل التسلسليًا.
        if v_m_auto then
          v_suggested := 'DAY_COMPLETED';
        elsif v_today_check_in is not null then
          -- موجود حدث CHECK_IN فعلي → يمكن الانصراف
          v_suggested := 'CHECK_OUT';
        else
          -- لا يوجد حدث CHECK_IN → يحتاج بصمة حضور أولاً
          v_suggested := 'CHECK_IN';
        end if;
      end if;
    elsif v_m_exec = 'completed' and v_m_auto and v_today_check_out is not null then
      v_suggested := 'DAY_COMPLETED';
    end if;

    v_mission := jsonb_build_object(
      'requestId', v_m_id,
      'type', v_m_type,
      'execStatus', coalesce(v_m_exec, 'approved'),
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
  if v_suggested in ('MISSION_START','MISSION_IN_PROGRESS') then
    v_can_punch := false;
  end if;

  return jsonb_build_object(
    'employeeId',v_me,
    'attendanceRequired',v_active and not v_is_executive,
    'selfPunchEnabled',v_active and not v_is_executive,
    'activeLocalDevices',v_local_devices,
    'hasActiveLocalDevice',v_local_devices>0,
    'localDeviceStatus',v_local_device_status,
    'currentDeviceStatus',v_current_device_status,
    'currentDeviceActive',v_current_device_active,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys>0,
    'canPunch',v_can_punch,
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    'todayCheckInAt',v_today_check_in,
    'todayCheckOutAt',v_today_check_out,
    'missionToday',v_mission,
    'lastUpdatedAt',now()
  );
end;
$$;

revoke all on function public.get_my_attendance_state(text) from public, anon;
grant execute on function public.get_my_attendance_state(text) to authenticated;

comment on function public.get_my_attendance_state is
  '0481: دورة يوم المأمورية — مع حماية لبيانات قديمة (CHECK_IN مفقود في attendance_events).';

comment on function public.end_my_mission is
  '0481: إنهاء المأمورية مع إنشاء حدث CHECK_IN تلقائي في attendance_events عند الإنهاء قبل نهاية الدوام.';

commit;
