-- 0088: Keep location_request_responses canonical and add private map snapshots.

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'live-location-map-snapshots', 'live-location-map-snapshots', false,
  2097152, array['image/png', 'image/jpeg']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists live_location_map_owner_write on storage.objects;
create policy live_location_map_owner_write on storage.objects
for insert to authenticated with check (
  bucket_id = 'live-location-map-snapshots'
  and (storage.foldername(name))[1] = coalesce(public.current_employee_id()::text, '')
);

create or replace function public.sync_location_request_response_from_point()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.live_request_id is null then return new; end if;
  insert into public.location_request_responses(
    request_id, employee_id, latitude, longitude, accuracy_meters,
    address, captured_at, upload_status, metadata
  ) values (
    new.live_request_id, new.employee_id, new.latitude, new.longitude,
    new.accuracy, new.address_ar, new.recorded_at, 'pending',
    jsonb_build_object(
      'pointId', new.id,
      'source', new.source,
      'isMock', new.is_mock
    )
  )
  on conflict (request_id) do update set
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    accuracy_meters = excluded.accuracy_meters,
    address = excluded.address,
    captured_at = excluded.captured_at,
    metadata = public.location_request_responses.metadata || excluded.metadata;
  return new;
end;
$$;

drop trigger if exists trg_sync_location_request_response on public.employee_locations;
create trigger trg_sync_location_request_response
after insert or update of latitude, longitude, accuracy, address_ar
on public.employee_locations
for each row when (new.live_request_id is not null)
execute function public.sync_location_request_response_from_point();

-- Repair prior request points, newest point wins deterministically.
insert into public.location_request_responses(
  request_id, employee_id, latitude, longitude, accuracy_meters,
  address, captured_at, upload_status, metadata
)
select distinct on (l.live_request_id)
  l.live_request_id, l.employee_id, l.latitude, l.longitude, l.accuracy,
  l.address_ar, l.recorded_at, 'pending',
  jsonb_build_object('pointId', l.id, 'source', l.source, 'isMock', l.is_mock)
from public.employee_locations l
where l.live_request_id is not null
order by l.live_request_id, l.recorded_at desc
on conflict (request_id) do update set
  latitude = excluded.latitude,
  longitude = excluded.longitude,
  accuracy_meters = excluded.accuracy_meters,
  address = excluded.address,
  captured_at = excluded.captured_at,
  metadata = public.location_request_responses.metadata || excluded.metadata;

create or replace function public.sync_location_response_video()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  update public.location_request_responses
  set video_storage_path = new.storage_path,
      video_duration_ms = new.duration_seconds * 1000,
      upload_status = case when new.status = 'ready' then 'completed' else 'uploading' end,
      metadata = metadata || jsonb_build_object('videoId', new.id)
  where request_id = new.live_request_id;
  return new;
end;
$$;

drop trigger if exists trg_sync_location_response_video on public.live_location_videos_meta;
create trigger trg_sync_location_response_video
after insert or update of storage_path, duration_seconds, status
on public.live_location_videos_meta
for each row execute function public.sync_location_response_video();

update public.location_request_responses r
set video_storage_path = v.storage_path,
    video_duration_ms = v.duration_seconds * 1000,
    upload_status = case when v.status = 'ready' then 'completed' else 'uploading' end,
    metadata = r.metadata || jsonb_build_object('videoId', v.id)
from public.live_location_videos_meta v
where v.live_request_id = r.request_id;

create or replace function public.register_live_location_map_snapshot(
  p_request_id uuid,
  p_storage_path text
)
returns public.location_request_responses
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_row public.location_request_responses;
begin
  select * into v_req from public.live_location_requests
  where id = p_request_id for update;
  if not found or v_req.employee_id is distinct from v_me then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  if p_storage_path not like v_me::text || '/' || p_request_id::text || '/%.png' then
    raise exception 'invalid map snapshot path' using errcode = '42501';
  end if;

  update public.location_request_responses
  set map_snapshot_storage_path = p_storage_path,
      metadata = metadata || jsonb_build_object(
        'mapSnapshotBucket', 'live-location-map-snapshots',
        'mapSnapshotRegisteredAt', now()
      )
  where request_id = p_request_id and employee_id = v_me
  returning * into v_row;
  if not found then
    raise exception 'location point required before map snapshot' using errcode = '22023';
  end if;

  perform public.log_audit_event(
    'live_location_map_snapshot_registered', 'security', 'info',
    'location_request_responses', v_row.id, 'تسجيل لقطة خريطة خاصة', null,
    jsonb_build_object('requestId', p_request_id)
  );
  return v_row;
end;
$$;

revoke execute on function public.register_live_location_map_snapshot(uuid, text) from public, anon;
grant execute on function public.register_live_location_map_snapshot(uuid, text) to authenticated;

create table if not exists public.live_location_map_access_logs (
  id uuid primary key default gen_random_uuid(),
  response_id uuid not null references public.location_request_responses(id) on delete cascade,
  request_id uuid not null references public.live_location_requests(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (action in ('signed_url', 'view')),
  created_at timestamptz not null default now()
);
alter table public.live_location_map_access_logs enable row level security;
revoke all on public.live_location_map_access_logs from anon, authenticated;
grant select, insert on public.live_location_map_access_logs to service_role;

create or replace function public.can_view_live_location_map_snapshot(p_request_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_req public.live_location_requests;
  v_response public.location_request_responses;
begin
  select * into v_req from public.live_location_requests where id = p_request_id;
  if not found then return null; end if;
  if not (
    v_req.employee_id = public.current_employee_id()
    or v_req.requested_by = public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_req.employee_id, 'live_location.view_response')
  ) then
    return null;
  end if;
  select * into v_response from public.location_request_responses
  where request_id = p_request_id;
  if not found or v_response.map_snapshot_storage_path is null then return null; end if;
  return jsonb_build_object(
    'responseId', v_response.id,
    'requestId', p_request_id,
    'bucket', 'live-location-map-snapshots',
    'storagePath', v_response.map_snapshot_storage_path
  );
end;
$$;
revoke execute on function public.can_view_live_location_map_snapshot(uuid) from public, anon;
grant execute on function public.can_view_live_location_map_snapshot(uuid) to authenticated;
notify pgrst, 'reload schema';
