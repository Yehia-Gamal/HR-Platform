begin;

-- Migration 0439: إضافة توقيتَي حضور وانصراف اليوم إلى get_my_attendance_state
-- حتى يخفي تطبيق الموبايل زر البصمة بعد اكتمال اليوم (حضور + انصراف)
-- ويعرض التوقيتين بدلاً منه، ويعود الزر تلقائياً بعد منتصف الليل.

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
  v_local_device_status text;  -- 'active' | 'pending' | null
  v_current_device_active boolean := false;  -- 0226: THIS device specifically
  v_current_device_status text;              -- 0226: status of THIS device
  v_passkeys integer := 0;
  v_last public.attendance_events;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_today_status text;
  v_suggested text := 'CHECK_IN';
  v_hash text;
  v_today_check_in timestamptz;   -- 0439: أول حضور اليوم
  v_today_check_out timestamptz;  -- 0439: آخر انصراف اليوم
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

  -- Count ALL active device pairs (backward compat)
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

  -- 0226: When installation_id is provided, check THIS device specifically
  if p_installation_id is not null and length(trim(p_installation_id)) >= 12 then
    v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');

    -- Check managed_device for this installation_id
    if exists (
      select 1 from public.managed_devices md
      where md.installation_id = p_installation_id
        and md.user_id = auth.uid()
        and md.employee_id = v_me
        and md.platform in ('android','ios')
        and md.status = 'active'
    ) then
      -- Managed device is active - check employee_device
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
      -- v_current_device_status keeps whatever status was found (pending/replaced/revoked/blocked/active/null)
    else
      -- Managed device not active - check if it exists at all
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

  -- Determine general device status for the mobile UI (backward compat)
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

  -- 0439: توقيتا حضور وانصراف اليوم (أول حضور وآخر انصراف)
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

  return jsonb_build_object(
    'employeeId',v_me,
    'attendanceRequired',v_active and not v_is_executive,
    'selfPunchEnabled',v_active and not v_is_executive,
    'activeLocalDevices',v_local_devices,
    'hasActiveLocalDevice',v_local_devices>0,
    'localDeviceStatus',v_local_device_status,
    -- 0226: Current device info (only set when p_installation_id provided)
    'currentDeviceStatus',v_current_device_status,
    'currentDeviceActive',v_current_device_active,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys>0,
    -- 0226: canPunch uses current device check when installation_id is provided
    'canPunch',v_active and not v_is_executive and (
      case when p_installation_id is not null and length(trim(p_installation_id)) >= 12
           then v_current_device_active
           else v_local_devices > 0
      end
    ),
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    -- 0439: توقيتا اليوم لإخفاء زر البصمة عند الاكتمال
    'todayCheckInAt',v_today_check_in,
    'todayCheckOutAt',v_today_check_out,
    'lastUpdatedAt',now()
  );
end;
$$;

revoke all on function public.get_my_attendance_state(text) from public, anon;
grant execute on function public.get_my_attendance_state(text) to authenticated;

comment on function public.get_my_attendance_state is
  '0439: إضافة توقيتي حضور وانصراف اليوم — الموبايل يخفي زر البصمة بعد اكتمال اليوم ويعرض التوقيتين، ويعود الزر بعد منتصف الليل.';

commit;
