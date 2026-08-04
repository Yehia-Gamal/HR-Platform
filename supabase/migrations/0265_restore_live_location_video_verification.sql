-- 0265: Restore live-location video verification.
-- Re-enables the requested production contract:
-- request -> high priority push -> employee sends accurate location + 5s front-camera video.

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'live-location-videos',
  'live-location-videos',
  false,
  15728640,
  array['video/mp4', 'video/quicktime']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists live_location_videos_owner_write on storage.objects;
create policy live_location_videos_owner_write on storage.objects
for insert to authenticated with check (
  bucket_id = 'live-location-videos'
  and (storage.foldername(name))[1] = coalesce(public.current_employee_id()::text, '')
);

create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode text default 'location_video',
  p_reason text default ''
)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_duration integer;
  v_video_seconds integer := 0;
  v_needs_point boolean := true;
  v_needs_video boolean := false;
  v_target_user uuid;
  v_mode text := coalesce(nullif(trim(p_mode), ''), 'location_video');
begin
  if v_me is null then
    raise exception 'requester has no employee profile' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.current_has_active_role(array['executive', 'executive-director'])
    or public.has_permission('live_location.request')
  ) then
    raise exception 'live_location.request permission required' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'live_location.request')
  ) then
    raise exception 'target outside permitted scope' using errcode = '42501';
  end if;

  if p_employee_id = v_me then
    raise exception 'cannot request own location' using errcode = '22023';
  end if;

  if v_mode not in ('snapshot', 'video_5s', 'location_video') then
    raise exception 'invalid request mode' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.employees
    where id = p_employee_id
      and status = 'active'
      and is_active
      and not is_deleted
      and user_id is not null
  ) then
    raise exception 'employee is not active or has no linked user account' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.live_location_requests
    where requested_by = v_me
      and employee_id = p_employee_id
      and requested_at > now() - interval '30 seconds'
  ) then
    raise exception 'cooldown_active: please wait 30 seconds between requests' using errcode = '22023';
  end if;

  update public.live_location_requests
  set status = 'cancelled',
      expires_at = least(coalesce(expires_at, now()), now()),
      updated_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('autoCancelledByNewRequest', true)
  where employee_id = p_employee_id
    and status in ('pending', 'accepted', 'active')
    and (expires_at is null or expires_at > now());

  v_duration := case v_mode
    when 'snapshot' then 1
    when 'video_5s' then 2
    when 'location_video' then 2
    else null
  end;

  if v_mode = 'video_5s' then
    v_video_seconds := 5;
    v_needs_point := false;
    v_needs_video := true;
  elsif v_mode = 'location_video' then
    v_video_seconds := 5;
    v_needs_point := true;
    v_needs_video := true;
  end if;

  insert into public.live_location_requests(
    employee_id,
    requested_by,
    reason,
    status,
    purpose,
    requested_at,
    expires_at,
    duration_minutes,
    metadata,
    created_by
  )
  values(
    p_employee_id,
    v_me,
    coalesce(nullif(trim(p_reason), ''), null),
    'pending',
    'verification',
    now(),
    now() + interval '5 minutes',
    v_duration,
    jsonb_build_object(
      'mode', v_mode,
      'videoSeconds', v_video_seconds,
      'needsPoint', v_needs_point,
      'needsVideo', v_needs_video,
      'isTracking', false,
      'policyVersion', 'V26-video-restore'
    ),
    auth.uid()
  )
  returning * into v_req;

  update public.live_location_requests
  set metadata = metadata || jsonb_build_object('requestId', v_req.id)
  where id = v_req.id
  returning * into v_req;

  select user_id into v_target_user
  from public.employees
  where id = p_employee_id;

  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id,
      recipient_employee_id,
      title,
      body,
      category,
      priority,
      action_url,
      entity_type,
      entity_id,
      metadata,
      created_by
    )
    values(
      v_target_user,
      p_employee_id,
      'طلب تحقق عاجل من الموقع',
      'الإدارة تطلب إرسال موقعك الحالي مع فيديو تحقق أمامي مدته 5 ثوان.',
      'system',
      'urgent',
      'ahlashabab://action/live_location_request/' || v_req.id::text,
      'live_location_request',
      v_req.id,
      jsonb_build_object(
        'fullScreen', true,
        'kind', 'live_location_request',
        'requestId', v_req.id,
        'entityId', v_req.id,
        'deepLink', 'ahlashabab://action/live_location_request/' || v_req.id::text,
        'channel', 'urgent_location_v6',
        'requiresVideo', v_needs_video,
        'videoSeconds', v_video_seconds
      ),
      auth.uid()
    );
  end if;

  perform public.log_audit_event(
    'live_location.requested',
    'security',
    'warning',
    'live_location_requests',
    v_req.id,
    'Live location verification requested',
    null,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'mode', v_mode,
      'needsPoint', v_needs_point,
      'needsVideo', v_needs_video,
      'requestId', v_req.id
    )
  );

  perform public.nudge_notification_dispatcher();
  return v_req;
end $$;

revoke execute on function public.request_live_location(uuid, text, text) from public, anon;
grant execute on function public.request_live_location(uuid, text, text) to authenticated;

create or replace function public.submit_live_location_point(
  p_request_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy double precision,
  p_altitude double precision default null,
  p_speed double precision default null,
  p_heading double precision default null,
  p_is_mock boolean default false,
  p_address_ar text default null
)
returns public.employee_locations
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_row public.employee_locations;
  v_mode text;
  v_needs_video boolean;
  v_has_video boolean := false;
begin
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;
  if p_accuracy is null or p_accuracy < 0 or p_accuracy > 10000 then
    raise exception 'invalid accuracy' using errcode = '22023';
  end if;

  select * into v_req
  from public.live_location_requests
  where id = p_request_id
  for update;

  if not found or v_req.employee_id is distinct from v_me then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if v_req.status <> 'active' or v_req.expires_at <= now() then
    raise exception 'location session is not active' using errcode = '22023';
  end if;

  insert into public.employee_locations(
    employee_id,
    live_request_id,
    latitude,
    longitude,
    accuracy,
    altitude,
    speed,
    heading,
    source,
    is_mock,
    address_ar,
    geocode_source,
    recorded_at,
    created_by
  )
  values(
    v_me,
    p_request_id,
    p_latitude,
    p_longitude,
    p_accuracy,
    p_altitude,
    p_speed,
    p_heading,
    'mobile',
    coalesce(p_is_mock, false),
    nullif(trim(coalesce(p_address_ar, '')), ''),
    case when nullif(trim(coalesce(p_address_ar, '')), '') is not null then 'nominatim' else null end,
    now(),
    auth.uid()
  )
  returning * into v_row;

  v_mode := coalesce(v_req.metadata->>'mode', 'snapshot');
  v_needs_video := coalesce((v_req.metadata->>'needsVideo')::boolean, v_mode in ('video_5s', 'location_video'));

  if v_needs_video then
    select exists(
      select 1
      from public.live_location_videos_meta
      where live_request_id = p_request_id
        and status <> 'deleted'
    ) into v_has_video;
  end if;

  if not v_needs_video or v_has_video then
    update public.live_location_requests
    set status = 'completed',
        expires_at = now(),
        updated_at = now()
    where id = p_request_id;
  end if;

  return v_row;
end $$;

revoke execute on function public.submit_live_location_point(uuid, double precision, double precision, double precision, double precision, double precision, double precision, boolean, text) from public, anon;
grant execute on function public.submit_live_location_point(uuid, double precision, double precision, double precision, double precision, double precision, double precision, boolean, text) to authenticated;

create or replace function public.register_live_location_video(
  p_request_id uuid,
  p_storage_path text,
  p_duration_seconds integer,
  p_size_bytes bigint,
  p_mime_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy double precision
)
returns public.live_location_videos_meta
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_row public.live_location_videos_meta;
  v_mode text;
  v_needs_point boolean;
  v_has_point boolean := false;
begin
  select * into v_req
  from public.live_location_requests
  where id = p_request_id
  for update;

  if not found or v_req.employee_id is distinct from v_me then
    raise exception 'request not found' using errcode = 'P0002';
  end if;

  v_mode := coalesce(v_req.metadata->>'mode', 'snapshot');
  if v_req.status <> 'active' or v_req.expires_at <= now() or v_mode not in ('video_5s', 'location_video') then
    raise exception 'video request is not active' using errcode = '22023';
  end if;
  if p_duration_seconds not between 4 and 7 then
    raise exception 'video must be approximately five seconds' using errcode = '22023';
  end if;
  if p_size_bytes <= 0 or p_size_bytes > 15728640 then
    raise exception 'invalid video size' using errcode = '22023';
  end if;
  if p_storage_path not like v_me::text || '/' || p_request_id::text || '/%' then
    raise exception 'invalid storage path' using errcode = '42501';
  end if;

  insert into public.live_location_videos_meta(
    live_request_id,
    employee_id,
    storage_path,
    storage_bucket,
    duration_seconds,
    size_bytes,
    mime_type,
    captured_lat,
    captured_lng,
    captured_accuracy,
    captured_at,
    status,
    created_by
  )
  values(
    p_request_id,
    v_me,
    p_storage_path,
    'live-location-videos',
    p_duration_seconds,
    p_size_bytes,
    coalesce(nullif(trim(p_mime_type), ''), 'video/mp4'),
    p_latitude,
    p_longitude,
    p_accuracy,
    now(),
    'ready',
    auth.uid()
  )
  returning * into v_row;

  v_needs_point := coalesce((v_req.metadata->>'needsPoint')::boolean, v_mode = 'location_video');
  if v_needs_point then
    select exists(
      select 1 from public.employee_locations where live_request_id = p_request_id
    ) into v_has_point;
  end if;

  if not v_needs_point or v_has_point then
    update public.live_location_requests
    set status = 'completed',
        expires_at = now(),
        updated_at = now()
    where id = p_request_id;
  end if;

  perform public.log_audit_event(
    'live_location.video_registered',
    'security',
    'warning',
    'live_location_videos_meta',
    v_row.id,
    'Live location verification video registered',
    null,
    jsonb_build_object(
      'requestId', p_request_id,
      'durationSeconds', p_duration_seconds,
      'mode', v_mode
    )
  );

  return v_row;
end $$;

revoke execute on function public.register_live_location_video(uuid, text, integer, bigint, text, double precision, double precision, double precision) from public, anon;
grant execute on function public.register_live_location_video(uuid, text, integer, bigint, text, double precision, double precision, double precision) to authenticated;

drop function if exists public.can_view_live_location_video(uuid);
create or replace function public.can_view_live_location_video(p_request_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_req public.live_location_requests;
  v_video public.live_location_videos_meta;
begin
  select * into v_req
  from public.live_location_requests
  where id = p_request_id;

  if not found then
    return null;
  end if;

  if not (
    v_req.employee_id = public.current_employee_id()
    or v_req.requested_by = public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_req.employee_id, 'live_location.view_response')
  ) then
    return null;
  end if;

  select * into v_video
  from public.live_location_videos_meta
  where live_request_id = p_request_id
    and status <> 'deleted'
  order by created_at desc
  limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'videoId', v_video.id,
    'bucket', coalesce(v_video.storage_bucket, 'live-location-videos'),
    'storagePath', v_video.storage_path
  );
end $$;

revoke execute on function public.can_view_live_location_video(uuid) from public, anon;
grant execute on function public.can_view_live_location_video(uuid) to authenticated;

insert into public.system_settings (key, value, value_type, group_name, label_ar, description, is_editable)
values(
  'live_location_video_enabled',
  'true'::jsonb,
  'boolean',
  'live_location',
  'تفعيل فيديو طلب الموقع',
  'Restored by 0265: live-location requests require a 5-second front-camera verification video.',
  false
)
on conflict (key) do update set
  value = 'true'::jsonb,
  is_editable = false,
  updated_at = now();
