-- 0104: V10 identity, workspace and local-biometric attendance hardening.
-- Forward-only: no applied migration is edited and no business data is removed.

create or replace function public.get_my_access_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_display_name text;
  v_employee_code text;
  v_roles text[] := '{}'::text[];
  v_permissions text[] := '{}'::text[];
  v_workspaces text[] := '{}'::text[];
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_executive boolean := false;
  v_is_manager boolean := false;
  v_is_operations boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  select p.employee_id, coalesce(e.full_name_ar, 'مستخدم النظام'), e.employee_code
    into v_employee_id, v_display_name, v_employee_code
  from public.profiles p
  left join public.employees e on e.id = p.employee_id
  where p.id = v_user_id
    and p.status in ('active', 'pending');

  if not found then
    raise exception 'active profile not found' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct r.slug order by r.slug), '{}'::text[])
    into v_roles
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_user_id
    and ur.effective_from <= now()
    and (ur.effective_to is null or ur.effective_to > now());

  v_is_full := public.current_is_full_access();
  if v_is_full then
    v_permissions := array['*']::text[];
  else
    select coalesce(array_agg(distinct p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = v_user_id
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to is null or rp.effective_to > now());
  end if;

  v_is_executive := v_roles && array['executive-director', 'executive']::text[];
  v_is_operations := v_roles && array[
    'operations-officer', 'operations-manager',
    'operations-manager-1', 'operations-manager-2'
  ]::text[];
  v_is_manager := v_is_operations or v_roles && array[
    'direct-manager', 'department-manager', 'branch-manager'
  ]::text[];
  v_is_hr := v_roles && array['hr-manager', 'hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_roles && array[
    'admin', 'super-admin', 'super_admin', 'system-admin',
    'technical-lead', 'executive-secretary'
  ]::text[];
  v_is_committee := v_roles && array[
    'committee-member', 'committee-chair', 'committee-secretary'
  ]::text[];

  -- V10: HR and executive-secretary are web-only; the executive has no
  -- employee attendance workspace. Operations inherits employee + manager.
  if v_employee_id is not null
     and not v_is_executive
     and not v_is_hr
     and not v_is_main_admin then
    v_workspaces := array_append(v_workspaces, 'employee');
  end if;
  if v_is_manager and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'manager');
  end if;
  if v_is_operations and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'field_operations');
  end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces, 'executive'); end if;
  if v_is_hr and not v_is_main_admin then v_workspaces := array_append(v_workspaces, 'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces, 'main_admin'); end if;
  if v_is_committee and not v_is_hr and not v_is_main_admin then
    v_workspaces := array_append(v_workspaces, 'committee');
  end if;

  if v_is_executive then
    v_default_workspace := 'executive';
  elsif v_is_main_admin then
    v_default_workspace := 'main_admin';
  elsif v_is_hr then
    v_default_workspace := 'hr';
  elsif v_is_operations then
    v_default_workspace := 'field_operations';
  elsif v_is_manager then
    v_default_workspace := 'manager';
  elsif v_employee_id is not null then
    v_default_workspace := 'employee';
  else
    raise exception 'no workspace assigned' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'userId', v_user_id,
    'employeeId', v_employee_id,
    'displayName', v_display_name,
    'employeeCode', v_employee_code,
    'roles', to_jsonb(v_roles),
    'permissions', to_jsonb(v_permissions),
    'workspaces', to_jsonb(v_workspaces),
    'defaultWorkspace', v_default_workspace,
    'attendancePolicy', jsonb_build_object(
      'attendanceRequired', not v_is_executive and not v_is_hr
        and not v_is_main_admin and v_employee_id is not null,
      'selfPunchEnabled', not v_is_executive and not v_is_hr
        and not v_is_main_admin and v_employee_id is not null,
      'liveLocationResponseEnabled', not v_is_executive and not v_is_hr
        and not v_is_main_admin and v_employee_id is not null
    )
  );
end;
$$;

revoke all on function public.get_my_access_context() from public, anon;
grant execute on function public.get_my_access_context() to authenticated;

-- Registration remains the one canonical managed-device entry point. A
-- matching employee_devices row is maintained for local-biometric attendance.
create or replace function public.register_my_device(
  p_installation_id text,
  p_platform text,
  p_device_name text,
  p_device_model text,
  p_os_version text,
  p_app_version text,
  p_app_build integer,
  p_environment text default 'production',
  p_push_enabled boolean default false,
  p_biometric_available boolean default false,
  p_metadata jsonb default '{}'::jsonb
)
returns public.managed_devices
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.managed_devices;
  v_existing_user uuid;
  v_employee_id uuid := public.current_employee_id();
  v_identifier_hash text;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_installation_id,''))) < 12 then
    raise exception 'invalid installation id' using errcode='22023';
  end if;
  if p_platform not in ('android','ios','web') then
    raise exception 'invalid platform' using errcode='22023';
  end if;
  if p_environment not in ('development','staging','production') then
    raise exception 'invalid environment' using errcode='22023';
  end if;
  v_identifier_hash := encode(
    digest(convert_to(p_installation_id, 'UTF8'), 'sha256'), 'hex'
  );

  select user_id into v_existing_user
  from public.managed_devices
  where installation_id=p_installation_id;
  if v_existing_user is not null and v_existing_user <> auth.uid() then
    raise exception 'installation belongs to another account' using errcode='42501';
  end if;

  insert into public.managed_devices(
    installation_id,user_id,employee_id,platform,device_name,device_model,os_version,
    app_version,app_build,environment,push_enabled,biometric_available,last_seen_at,metadata
  ) values (
    p_installation_id,auth.uid(),v_employee_id,p_platform,nullif(trim(p_device_name),''),
    nullif(trim(p_device_model),''),nullif(trim(p_os_version),''),
    coalesce(nullif(trim(p_app_version),''),'0.0.0'),greatest(coalesce(p_app_build,0),0),
    p_environment,coalesce(p_push_enabled,false),coalesce(p_biometric_available,false),
    now(),coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (installation_id) do update set
    user_id=excluded.user_id,employee_id=excluded.employee_id,platform=excluded.platform,
    device_name=excluded.device_name,device_model=excluded.device_model,
    os_version=excluded.os_version,app_version=excluded.app_version,
    app_build=excluded.app_build,environment=excluded.environment,
    push_enabled=excluded.push_enabled,biometric_available=excluded.biometric_available,
    last_seen_at=now(),metadata=excluded.metadata,
    status=case when public.managed_devices.status='retired'
      then 'active' else public.managed_devices.status end
  returning * into v_row;

  if v_employee_id is not null and p_platform in ('android','ios') then
    insert into public.employee_devices(
      employee_id,user_id,device_identifier_hash,credential_id,device_name,
      platform,status,last_used_at,metadata
    ) values (
      v_employee_id,auth.uid(),v_identifier_hash,null,
      coalesce(nullif(trim(p_device_name),''),nullif(trim(p_device_model),'')),
      p_platform,'active',now(),jsonb_build_object(
        'kind','local_biometric','managedDeviceId',v_row.id,
        'biometricAvailable',coalesce(p_biometric_available,false)
      )
    )
    on conflict (employee_id,device_identifier_hash) do update set
      user_id=excluded.user_id,device_name=excluded.device_name,
      platform=excluded.platform,last_used_at=now(),
      status=case
        when public.employee_devices.status in ('blocked','revoked','replaced')
          then public.employee_devices.status
        else 'active'
      end,
      metadata=public.employee_devices.metadata || excluded.metadata;
  end if;

  perform public.log_security_event(
    'device.registered','low','allowed',v_identifier_hash,
    jsonb_build_object('platform',p_platform,'appVersion',p_app_version,
      'appBuild',p_app_build,'biometricAvailable',p_biometric_available)
  );
  return v_row;
end;
$$;

revoke all on function public.register_my_device(
  text,text,text,text,text,text,integer,text,boolean,boolean,jsonb
) from public, anon;
grant execute on function public.register_my_device(
  text,text,text,text,text,text,integer,text,boolean,boolean,jsonb
) to authenticated;

create or replace function public.get_my_attendance_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_active boolean;
  v_local_devices integer := 0;
  v_passkeys integer := 0;
  v_last public.attendance_events;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_today_status text;
  v_suggested text := 'CHECK_IN';
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
    and md.biometric_available
    and exists (
      select 1 from public.employee_devices ed
      where ed.employee_id=v_me and ed.user_id=auth.uid() and ed.status='active'
        and ed.device_identifier_hash=encode(
          digest(convert_to(md.installation_id,'UTF8'),'sha256'),'hex'
        )
    );

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

  return jsonb_build_object(
    'employeeId',v_me,
    'attendanceRequired',v_active and not v_is_executive,
    'selfPunchEnabled',v_active and not v_is_executive,
    'activeLocalDevices',v_local_devices,
    'hasActiveLocalDevice',v_local_devices>0,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys>0,
    'canPunch',v_active and not v_is_executive and v_local_devices>0,
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    'lastUpdatedAt',now()
  );
end;
$$;

revoke all on function public.get_my_attendance_state() from public, anon;
grant execute on function public.get_my_attendance_state() to authenticated;

-- Internal attendance writer for an already verified local-biometric device.
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
set search_path = public, pg_temp
as $$
declare
  v_event_id uuid;
  v_assignment public.shift_assignments%rowtype;
  v_geofence public.geofences%rowtype;
  v_shift public.shifts%rowtype;
  v_roster_shift_id uuid;
  v_roster_geofence_id uuid;
  v_now timestamptz := now();
  v_work_date date := (v_now at time zone 'Africa/Cairo')::date;
  v_distance numeric(12,2);
  v_late integer := 0;
  v_first_check_in timestamptz;
  v_last_check_out timestamptz;
  v_last_event_type text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'attendance_trusted_server_required' using errcode='42501';
  end if;
  if p_event_type not in ('CHECK_IN','CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode='22023';
  end if;
  if p_employee_id is null then
    raise exception 'attendance_identity_not_verified' using errcode='28000';
  end if;
  if p_is_mock then
    raise exception 'attendance_mock_location_rejected' using errcode='22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'attendance_location_required' using errcode='22023';
  end if;
  if p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180
     or p_accuracy_meters < 0 or p_accuracy_meters > 10000 then
    raise exception 'invalid_attendance_location' using errcode='22023';
  end if;
  if exists (
    select 1 from public.attendance_events ae
    where ae.employee_id=p_employee_id and ae.event_type=p_event_type
      and ae.event_at>v_now-interval '60 seconds'
  ) then
    raise exception 'duplicate_attendance_event' using errcode='23505';
  end if;
  if exists (
    select 1 from public.attendance_daily
    where employee_id=p_employee_id and work_date=v_work_date and is_finalized
  ) then
    raise exception 'attendance_period_finalized' using errcode='55000';
  end if;

  select ae.event_type into v_last_event_type
  from public.attendance_events ae
  where ae.employee_id=p_employee_id
    and (ae.event_at at time zone 'Africa/Cairo')::date=v_work_date
    and ae.status in ('accepted','adjusted')
  order by ae.event_at desc limit 1;
  if p_event_type='CHECK_OUT' and v_last_event_type is distinct from 'CHECK_IN' then
    raise exception 'attendance_check_in_required' using errcode='22023';
  end if;
  if p_event_type='CHECK_IN' and v_last_event_type='CHECK_IN' then
    raise exception 'attendance_check_out_required' using errcode='22023';
  end if;

  select rd.shift_id,rd.geofence_id into v_roster_shift_id,v_roster_geofence_id
  from public.roster_days rd
  join public.work_rosters wr on wr.id=rd.roster_id and wr.status='published'
  where rd.employee_id=p_employee_id and rd.work_date=v_work_date
    and rd.day_status='scheduled'
  order by wr.published_at desc nulls last limit 1;

  select * into v_assignment from public.shift_assignments sa
  where sa.employee_id=p_employee_id and sa.is_active
    and sa.effective_from<=v_work_date
    and (sa.effective_to is null or sa.effective_to>=v_work_date)
  order by sa.effective_from desc limit 1;

  if v_roster_geofence_id is not null then
    select * into v_geofence from public.geofences
    where id=v_roster_geofence_id and is_active;
  elsif v_assignment.geofence_id is not null then
    select * into v_geofence from public.geofences
    where id=v_assignment.geofence_id and is_active;
  end if;
  if v_geofence.id is null then
    raise exception 'attendance_geofence_not_configured' using errcode='55000';
  end if;

  v_distance := public.geo_distance_meters(
    p_latitude,p_longitude,v_geofence.latitude,v_geofence.longitude
  )::numeric(12,2);
  if v_distance>v_geofence.radius_meters then
    raise exception 'attendance_outside_complex' using errcode='22023';
  end if;
  if v_geofence.max_accuracy is not null
     and p_accuracy_meters>v_geofence.max_accuracy then
    raise exception 'attendance_location_accuracy_too_low' using errcode='22023';
  end if;

  if coalesce(v_roster_shift_id,v_assignment.shift_id) is not null then
    select * into v_shift from public.shifts
    where id=coalesce(v_roster_shift_id,v_assignment.shift_id);
  end if;
  if p_event_type='CHECK_IN' and v_shift.id is not null then
    v_late := public.calculate_late_minutes(
      v_now,v_shift.start_time,v_shift.grace_in_minutes,v_work_date
    );
  end if;

  insert into public.attendance_events(
    employee_id,shift_assignment_id,geofence_id,event_type,event_at,
    latitude,longitude,accuracy_meters,distance_meters,status,
    late_minutes,requires_review,verification_status,
    passkey_credential_id,biometric_method,selfie_path,server_verified,
    is_mock_location,notes,source,created_by
  ) values (
    p_employee_id,v_assignment.id,v_geofence.id,p_event_type,v_now,
    p_latitude,p_longitude,p_accuracy_meters,v_distance,'accepted',
    v_late,false,'biometric_verified',null,'fingerprint',null,true,false,
    'inside_complex_local_biometric','mobile',null
  ) returning id into v_event_id;

  select min(event_at) filter(where event_type='CHECK_IN'),
         max(event_at) filter(where event_type='CHECK_OUT')
    into v_first_check_in,v_last_check_out
  from public.attendance_events
  where employee_id=p_employee_id
    and (event_at at time zone 'Africa/Cairo')::date=v_work_date
    and status in ('accepted','adjusted');

  insert into public.attendance_daily(
    employee_id,work_date,shift_id,first_check_in,last_check_out,
    work_minutes,late_minutes,status,is_finalized,created_by
  ) values (
    p_employee_id,v_work_date,coalesce(v_roster_shift_id,v_assignment.shift_id),
    v_first_check_in,v_last_check_out,
    case when v_first_check_in is not null and v_last_check_out is not null
      then greatest(0,floor(extract(epoch from (v_last_check_out-v_first_check_in))/60)::integer)
      else 0 end,
    v_late,
    case when v_first_check_in is null then 'partial'
      when v_late>0 then 'late' else 'present' end,
    false,null
  )
  on conflict on constraint attendance_daily_uq do update set
    shift_id=coalesce(excluded.shift_id,attendance_daily.shift_id),
    first_check_in=coalesce(excluded.first_check_in,attendance_daily.first_check_in),
    last_check_out=coalesce(excluded.last_check_out,attendance_daily.last_check_out),
    work_minutes=excluded.work_minutes,
    late_minutes=greatest(attendance_daily.late_minutes,excluded.late_minutes),
    status=case
      when attendance_daily.status in ('on_leave','holiday','weekend')
        then attendance_daily.status
      when excluded.first_check_in is null then 'partial'
      when greatest(attendance_daily.late_minutes,excluded.late_minutes)>0 then 'late'
      else 'present' end,
    updated_at=now()
  where attendance_daily.is_finalized=false;

  perform public.log_audit_event(
    'attendance.'||lower(p_event_type),'security','info','attendance_events',
    v_event_id,'بصمة محلية موثقة داخل نطاق المجمع',null,
    jsonb_build_object('method','local_biometric','insideComplex',true,
      'distanceMeters',v_distance,'geofenceId',v_geofence.id)
  );
  return v_event_id;
end;
$$;

revoke all on function public.record_attendance_local_biometric(
  uuid,text,double precision,double precision,double precision,boolean
) from public, anon, authenticated;

create or replace function public.punch_attendance_local_biometric_v1(
  p_operation_id uuid,
  p_event_type text,
  p_installation_id text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_is_mock boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_hash text;
  v_managed public.managed_devices;
  v_employee_device public.employee_devices;
  v_operation public.local_attendance_operations;
  v_event_id uuid;
  v_event public.attendance_events;
  v_result jsonb;
  v_error text;
  v_known_errors constant text[] := array[
    'attendance_outside_complex','attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low','attendance_geofence_not_configured',
    'attendance_location_required','duplicate_attendance_event',
    'attendance_period_finalized','attendance_check_in_required',
    'attendance_check_out_required'
  ];
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'authenticated employee is required' using errcode='42501';
  end if;
  if p_operation_id is null then
    raise exception 'attendance_operation_id_required' using errcode='22023';
  end if;
  if p_event_type not in ('CHECK_IN','CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode='22023';
  end if;
  if length(trim(coalesce(p_installation_id,'')))<12 then
    raise exception 'invalid_installation_id' using errcode='22023';
  end if;
  if exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=auth.uid() and r.slug in ('executive','executive-director')
      and ur.effective_from<=now()
      and (ur.effective_to is null or ur.effective_to>now())
  ) then
    raise exception 'executive_attendance_not_required' using errcode='42501';
  end if;

  v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');
  select * into v_managed from public.managed_devices
  where installation_id=p_installation_id and user_id=auth.uid()
    and employee_id=v_employee_id and platform in ('android','ios')
    and status='active' and biometric_available
  for update;
  if not found then
    raise exception 'local_biometric_device_not_active' using errcode='28000';
  end if;
  select * into v_employee_device from public.employee_devices
  where employee_id=v_employee_id and user_id=auth.uid()
    and device_identifier_hash=v_hash and status='active'
  for update;
  if not found then
    raise exception 'local_biometric_device_not_active' using errcode='28000';
  end if;

  insert into public.local_attendance_operations(
    operation_id,user_id,employee_id,event_type,credential_id
  ) values (p_operation_id,auth.uid(),v_employee_id,p_event_type,v_hash)
  on conflict (operation_id) do nothing;
  select * into v_operation from public.local_attendance_operations
  where operation_id=p_operation_id for update;
  if v_operation.user_id<>auth.uid()
     or v_operation.employee_id<>v_employee_id
     or v_operation.event_type<>p_event_type
     or v_operation.credential_id<>v_hash then
    raise exception 'attendance_idempotency_conflict' using errcode='22023';
  end if;
  if v_operation.status in ('completed','rejected') then
    return coalesce(v_operation.result,'{}'::jsonb)
      || jsonb_build_object('replayed',true);
  end if;

  begin
    v_event_id := public.record_attendance_local_biometric(
      v_employee_id,p_event_type,p_latitude,p_longitude,
      p_accuracy_meters,p_is_mock
    );
  exception when others then
    get stacked diagnostics v_error=message_text;
    if v_error=any(v_known_errors) then
      v_result := jsonb_build_object('ok',false,'error',v_error,'replayed',false);
      update public.local_attendance_operations
      set status='rejected',result=v_result,completed_at=now()
      where operation_id=p_operation_id;
      return v_result;
    end if;
    raise;
  end;

  update public.employee_devices set last_used_at=now()
  where id=v_employee_device.id;
  update public.managed_devices set last_seen_at=now()
  where id=v_managed.id;
  select * into v_event from public.attendance_events where id=v_event_id;
  v_result := jsonb_build_object(
    'ok',true,'verified',true,'verificationMethod','local_biometric',
    'eventId',v_event_id,'eventType',p_event_type,
    'status',coalesce(v_event.status,'accepted'),
    'insideComplex',v_event.status='accepted',
    'distanceMeters',v_event.distance_meters,'geofenceId',v_event.geofence_id,
    'recordedAt',v_event.event_at,'replayed',false
  );
  update public.local_attendance_operations
  set status='completed',result=v_result,completed_at=now()
  where operation_id=p_operation_id;
  return v_result;
end;
$$;

revoke all on function public.punch_attendance_local_biometric_v1(
  uuid,text,text,double precision,double precision,double precision,boolean
) from public, anon, authenticated;
grant execute on function public.punch_attendance_local_biometric_v1(
  uuid,text,text,double precision,double precision,double precision,boolean
) to authenticated;

-- Explicit executive role detection and executive exclusion from attendance.
create or replace function public.get_executive_attendance_today()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := current_date;
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_has_attendance_access boolean;
begin
  select exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=auth.uid() and r.slug in ('executive','executive-director')
      and ur.effective_from<=now()
      and (ur.effective_to is null or ur.effective_to>now())
  ) into v_is_executive;
  select public.current_is_full_access() or public.has_any_permission(array[
    'attendance.record.read','attendance.history.manage','attendance.roster.manage',
    'people.employee.read'
  ]) into v_has_attendance_access;
  if not (v_is_executive or v_has_attendance_access) then
    raise exception 'executive or attendance access required' using errcode='42501';
  end if;

  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',e.id,'name',e.full_name_ar,'employeeCode',e.employee_code,
    'jobTitle',jt.name,'department',d.name,
    'attendanceStatus',coalesce(ad.status,'absent'),
    'firstCheckIn',ad.first_check_in,'lastCheckOut',ad.last_check_out,
    'lateMinutes',coalesce(ad.late_minutes,0),'isOnMission',(mission.id is not null),
    'lastLatitude',last_loc.latitude,'lastLongitude',last_loc.longitude,
    'lastRecordedAt',last_loc.recorded_at
  ) order by case
    when mission.id is not null then 1 when coalesce(ad.status,'absent')='present' then 2
    when coalesce(ad.status,'absent')='late' then 3
    when coalesce(ad.status,'absent')='partial' then 4
    when coalesce(ad.status,'absent')='on_leave' then 5
    when coalesce(ad.status,'absent')='holiday' then 6
    when coalesce(ad.status,'absent')='weekend' then 7
    when coalesce(ad.status,'absent')='absent' then 8 else 9 end,e.full_name_ar)
  from public.employees e
  left join public.job_titles jt on jt.id=e.job_title_id
  left join public.departments d on d.id=e.department_id
  left join public.attendance_daily ad on ad.employee_id=e.id and ad.work_date=v_today
  left join lateral (
    select wa.id from public.work_assignment_participants wap
    join public.work_assignments wa on wa.id=wap.assignment_id
    where wap.employee_id=e.id and wa.status in ('APPROVED','IN_PROGRESS')
      and wa.counts_as_work_day and wa.start_at::date<=v_today
      and wa.end_at::date>=v_today limit 1
  ) mission on true
  left join lateral (
    select l.latitude,l.longitude,l.recorded_at from public.employee_locations l
    where l.employee_id=e.id order by l.recorded_at desc limit 1
  ) last_loc on true
  where e.status='active' and not e.is_deleted
    and not exists (
      select 1 from public.user_roles eur join public.roles er on er.id=eur.role_id
      where eur.user_id=e.user_id and er.slug in ('executive','executive-director')
        and eur.effective_from<=now()
        and (eur.effective_to is null or eur.effective_to>now())
    )
    and (public.current_is_full_access()
      or public.can_access_employee(e.id,'attendance.record.read')
      or public.can_access_employee(e.id,'people.employee.read'))
  ),'[]'::jsonb);
end;
$$;

revoke all on function public.get_executive_attendance_today() from public, anon;
grant execute on function public.get_executive_attendance_today() to authenticated;

notify pgrst, 'reload schema';
