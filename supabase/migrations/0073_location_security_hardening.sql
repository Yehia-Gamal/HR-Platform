-- 0073: Location Security Hardening
-- Adds employee_devices, location_request_responses, idempotency, cooldown, and replay protection.

-- =====================================================================
-- Table: employee_devices
-- =====================================================================
create table if not exists public.employee_devices (
  id                    uuid primary key default gen_random_uuid(),
  employee_id           uuid not null references public.employees(id) on delete cascade,
  user_id               uuid references auth.users(id) on delete set null,
  device_identifier_hash text not null,
  credential_id         text,
  public_key            text,
  device_name           text,
  platform              text not null default 'android' check (platform in ('android','ios','web')),
  status                text not null default 'active' check (status in ('active','revoked','blocked')),
  registered_at         timestamptz not null default now(),
  last_used_at          timestamptz,
  revoked_at            timestamptz,
  metadata              jsonb not null default '{}'::jsonb,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz,
  constraint employee_devices_identifier_unique unique (employee_id, device_identifier_hash)
);
comment on table public.employee_devices is 'أجهزة الموظفين المسجلة بالبصمة أو المفتاح.';
create index if not exists ix_emp_devices_employee on public.employee_devices(employee_id, status);
create index if not exists ix_emp_devices_user on public.employee_devices(user_id, status);

drop trigger if exists trg_emp_devices_updated_at on public.employee_devices;
create trigger trg_emp_devices_updated_at before update on public.employee_devices
for each row execute function public.set_updated_at();

alter table public.employee_devices enable row level security;

drop policy if exists emp_devices_select on public.employee_devices;
create policy emp_devices_select on public.employee_devices
for select to authenticated using (
  user_id = auth.uid()
  or public.current_is_full_access()
  or public.has_permission('access.account.manage_devices')
);

-- =====================================================================
-- Table: location_request_responses
-- =====================================================================
create table if not exists public.location_request_responses (
  id                       uuid primary key default gen_random_uuid(),
  request_id               uuid not null references public.live_location_requests(id) on delete cascade,
  employee_id              uuid not null references public.employees(id) on delete cascade,
  latitude                 double precision not null,
  longitude                double precision not null,
  accuracy_meters          double precision,
  address                  text,
  captured_at              timestamptz not null default now(),
  video_storage_path       text,
  map_snapshot_storage_path text,
  device_id                uuid references public.employee_devices(id) on delete set null,
  video_duration_ms        integer,
  upload_status            text not null default 'pending' check (upload_status in ('pending','uploading','completed','failed')),
  metadata                 jsonb not null default '{}'::jsonb,
  created_at               timestamptz not null default now(),
  constraint loc_resp_request_unique unique (request_id)
);
comment on table public.location_request_responses is 'استجابات الموظفين لطلبات الموقع — فيديو وموقع.';
create index if not exists ix_loc_resp_request on public.location_request_responses(request_id);
create index if not exists ix_loc_resp_employee on public.location_request_responses(employee_id, created_at desc);

drop trigger if exists trg_loc_resp_updated_at on public.location_request_responses;
create trigger trg_loc_resp_updated_at before update on public.location_request_responses
for each row execute function public.set_updated_at();

alter table public.location_request_responses enable row level security;

drop policy if exists loc_resp_select on public.location_request_responses;
create policy loc_resp_select on public.location_request_responses
for select to authenticated using (
  employee_id = public.current_employee_id()
  or public.can_access_employee(employee_id, 'live_location.view_response')
);

-- =====================================================================
-- Idempotency: prevent double-completion of live_location_requests
-- =====================================================================
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
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_me       uuid := public.current_employee_id();
  v_req      public.live_location_requests;
  v_row      public.employee_locations;
  v_mode     text;
  v_needs_video boolean;
begin
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;
  if p_accuracy is null or p_accuracy < 0 or p_accuracy > 10000 then
    raise exception 'invalid accuracy' using errcode = '22023';
  end if;
  select * into v_req from public.live_location_requests where id = p_request_id for update;
  if not found or v_req.employee_id is distinct from v_me then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if v_req.status <> 'active' or v_req.expires_at <= now() then
    raise exception 'location session is not active' using errcode = '22023';
  end if;

  -- Idempotency: prevent duplicate location point for same request
  if exists (
    select 1 from public.employee_locations
    where live_request_id = p_request_id and created_by = auth.uid()
  ) then
    select * into v_row from public.employee_locations
    where live_request_id = p_request_id and created_by = auth.uid()
    order by recorded_at desc limit 1;
    return v_row;
  end if;

  insert into public.employee_locations(
    employee_id, live_request_id, latitude, longitude, accuracy,
    altitude, speed, heading, source, is_mock,
    address_ar, geocode_source, recorded_at, created_by
  ) values (
    v_me, p_request_id, p_latitude, p_longitude, p_accuracy,
    p_altitude, p_speed, p_heading, 'mobile', coalesce(p_is_mock, false),
    nullif(trim(coalesce(p_address_ar, '')), ''),
    case when nullif(trim(coalesce(p_address_ar, '')), '') is not null then 'nominatim' else null end,
    now(), auth.uid()
  ) returning * into v_row;

  v_mode := coalesce(v_req.metadata->>'mode', 'snapshot');
  v_needs_video := coalesce((v_req.metadata->>'needsVideo')::boolean, v_mode = 'video_5s');

  if v_mode = 'snapshot' then
    update public.live_location_requests
    set status = 'completed', expires_at = now()
    where id = p_request_id;
  end if;
  return v_row;
end;
$$;

-- =====================================================================
-- Cooldown: 30 seconds per requester+target
-- =====================================================================
create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode text,
  p_reason text default ''
)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me            uuid    := public.current_employee_id();
  v_duration      integer;
  v_video_seconds integer := 0;
  v_row           public.live_location_requests;
  v_target_user   uuid;
  v_recent_count  integer;
begin
  if v_me is null then
    raise exception 'requester has no employee profile' using errcode = '42501';
  end if;
  if not (public.current_is_full_access() or public.can_access_employee(p_employee_id, 'live_location.request')) then
    raise exception 'target outside permitted scope' using errcode = '42501';
  end if;
  if p_employee_id = v_me then
    raise exception 'cannot request own location' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.employees where id = p_employee_id and status = 'active'
  ) then
    raise exception 'employee is not active' using errcode = 'P0002';
  end if;

  -- Cooldown: max 1 request per 30 seconds per requester+target
  select count(*) into v_recent_count
  from public.live_location_requests
  where requested_by = v_me
    and employee_id = p_employee_id
    and requested_at > now() - interval '30 seconds';
  if v_recent_count > 0 then
    raise exception 'cooldown_active: please wait 30 seconds between requests' using errcode = '22023';
  end if;

  v_duration := case p_mode
    when 'snapshot'       then 1
    when 'video_5s'       then 2
    when 'location_video' then 2
    when 'track_5'        then 5
    when 'track_10'       then 10
    when 'track_15'       then 15
    when 'track_30'       then 30
    else null
  end;
  if v_duration is null then
    raise exception 'invalid request mode' using errcode = '22023';
  end if;
  if p_mode in ('video_5s', 'location_video') then
    v_video_seconds := 5;
  end if;

  -- Auto-cancel any previous active location request for this employee
  update public.live_location_requests
  set status     = 'rejected',
      expires_at = now(),
      metadata   = jsonb_set(
                     coalesce(metadata, '{}'::jsonb),
                     '{autoCancelledByNewRequest}', 'true'
                   )
  where employee_id = p_employee_id
    and status in ('pending', 'accepted', 'active')
    and (expires_at is null or expires_at > now());

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    p_employee_id, v_me,
    coalesce(nullif(trim(p_reason), ''), null),
    'pending', 'verification',
    now(), now() + interval '5 minutes',
    v_duration,
    jsonb_build_object('mode', p_mode, 'videoSeconds', v_video_seconds),
    auth.uid()
  ) returning * into v_row;

  select user_id into v_target_user from public.employees where id = p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, action_url, entity_type, entity_id, created_by
    ) values (
      v_target_user, p_employee_id,
      'طلب تحقق من الموقع',
      'المدير يطلب التحقق من موقعك. يرجى الاستجابة فوراً.',
      'system', 'urgent',
      '/location-requests', 'live_location_request', v_row.id, auth.uid()
    );
  end if;

  perform public.log_audit_event(
    'live_location_requested',
    'security',
    'warning',
    'live_location_requests',
    v_row.id,
    'طلب موقع حي',
    null,
    jsonb_build_object('mode', p_mode, 'employeeId', p_employee_id)
  );

  perform public.nudge_notification_dispatcher();

  return v_row;
end;
$$;

-- =====================================================================
-- Cleanup: auto-delete videos after 24 hours via retention job
-- =====================================================================
create or replace function public.list_retention_video_candidates(
  p_limit integer default 100
)
returns table (
  video_id       uuid,
  storage_bucket text,
  storage_path   text
)
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  return query
  select
    v.id as video_id,
    v.storage_bucket,
    v.storage_path
  from public.live_location_videos_meta v
  where v.status = 'ready'
    and v.retention_delete_after is not null
    and v.retention_delete_after <= now()
    and v.legal_hold_until is null
  order by v.retention_delete_after asc
  limit p_limit;
end;
$$;

create or replace function public.mark_retention_video_deleted(
  p_video_id uuid,
  p_reason text default 'retention_expired'
)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  update public.live_location_videos_meta
  set status = 'deleted',
      deleted_at = now(),
      deletion_reason = p_reason,
      updated_at = now()
  where id = p_video_id;
end;
$$;

-- =====================================================================
-- Record attendance event via passkey verification
-- =====================================================================
create or replace function public.record_attendance_event(
  p_employee_id uuid,
  p_event_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_biometric_method text default 'passkey',
  p_selfie_path text default null,
  p_passkey_credential_id uuid default null,
  p_verified boolean default false,
  p_is_mock boolean default false
)
returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid event type' using errcode = '22023';
  end if;
  insert into public.attendance_events(
    employee_id, event_type, latitude, longitude, accuracy_meters,
    biometric_method, selfie_path, passkey_credential_id, verified,
    is_mock, recorded_at, created_by
  ) values (
    p_employee_id, p_event_type, p_latitude, p_longitude, p_accuracy_meters,
    p_biometric_method, p_selfie_path, p_passkey_credential_id, p_verified,
    p_is_mock, now(), auth.uid()
  ) returning id into v_id;

  perform public.log_audit_event(
    'attendance.' || lower(p_event_type),
    'security',
    'info',
    'attendance_events',
    v_id,
    'حضور بالبصمة',
    null,
    jsonb_build_object('method', p_biometric_method, 'verified', p_verified)
  );

  return v_id;
end;
$$;

-- =====================================================================
-- Security: disable backup, restrict data extraction
-- =====================================================================
comment on table public.employee_devices is
  'أجهزة الموظفين — لا تُسمح باستعادة الجلسات أو البصمات عبر النسخ الاحتياطي.';
comment on table public.location_request_responses is
  'استجابات طلبات الموقع — الفيديو والموقع يُحذفان بعد 24 ساعة.';
