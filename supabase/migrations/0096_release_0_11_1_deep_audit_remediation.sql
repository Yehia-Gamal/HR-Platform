-- 0096: Close the remaining release 0.11.1 P0/P1 audit gaps.
-- - employee_devices is the canonical attendance-device state
-- - urgent location links/channels are normalized server-side
-- - push delivery lifecycle can record token_missing/delivered/opened
-- - a video-required request cannot be completed through a location-only waiver

begin;

-- Canonical device lifecycle and duplicate prevention.
alter table public.employee_devices
  drop constraint if exists employee_devices_status_check;
alter table public.employee_devices
  add constraint employee_devices_status_check
  check (status in ('pending','active','blocked','revoked','replaced'));

with ranked as (
  select id,
         row_number() over (
           partition by employee_id, credential_id
           order by (status = 'active') desc, registered_at desc, created_at desc
         ) as position
  from public.employee_devices
  where credential_id is not null
    and status in ('pending','active','blocked')
)
update public.employee_devices d
set status = 'replaced',
    revoked_at = coalesce(d.revoked_at, now()),
    metadata = d.metadata || jsonb_build_object('replacedByMigration', '0096')
from ranked r
where d.id = r.id and r.position > 1;

create unique index if not exists ux_employee_devices_live_credential
  on public.employee_devices(employee_id, credential_id)
  where credential_id is not null and status in ('pending','active','blocked');

create or replace function public.get_my_passkeys()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'credentialId', p.credential_id,
    'deviceId', d.id,
    'deviceLabel', coalesce(d.device_name, p.device_label, 'هاتف الموظف'),
    'status', case
      when p.status = 'revoked' then 'revoked'
      else coalesce(d.status, 'pending')
    end,
    'trusted', p.status = 'active' and p.trusted and d.status = 'active',
    'deviceType', p.credential_device_type,
    'backedUp', p.credential_backed_up,
    'lastUsedAt', greatest(p.last_used, d.last_used_at),
    'createdAt', p.created_at
  ) order by p.created_at desc), '[]'::jsonb)
  from public.passkey_credentials p
  left join lateral (
    select ed.*
    from public.employee_devices ed
    where ed.employee_id = p.employee_id
      and ed.user_id = p.user_id
      and ed.credential_id = p.credential_id
    order by
      case ed.status
        when 'active' then 1 when 'pending' then 2 when 'blocked' then 3
        when 'replaced' then 4 else 5
      end,
      ed.registered_at desc
    limit 1
  ) d on true
  where p.user_id = auth.uid()
    and p.employee_id = public.current_employee_id();
$$;

revoke all on function public.get_my_passkeys() from public, anon, authenticated;
grant execute on function public.get_my_passkeys() to authenticated;

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
  v_devices integer := 0;
  v_last public.attendance_events;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_today_status text;
  v_suggested text := 'CHECK_IN';
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select e.is_active and not coalesce(e.is_deleted, false), exists(
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.slug in ('executive','executive-director')
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
  ) into v_active, v_is_executive
  from public.employees e
  where e.id = v_me;

  select count(*) into v_devices
  from public.passkey_credentials p
  join public.employee_devices d
    on d.employee_id = p.employee_id
   and d.user_id = p.user_id
   and d.credential_id = p.credential_id
   and d.status = 'active'
  where p.employee_id = v_me
    and p.user_id = auth.uid()
    and p.status = 'active'
    and p.trusted;

  select * into v_last
  from public.attendance_events
  where employee_id = v_me
    and (event_at at time zone 'Africa/Cairo')::date = v_today
  order by event_at desc
  limit 1;

  select status into v_today_status
  from public.attendance_daily
  where employee_id = v_me and work_date = v_today;

  if v_last.id is not null and v_last.event_type = 'CHECK_IN' then
    v_suggested := 'CHECK_OUT';
  end if;

  return jsonb_build_object(
    'employeeId', v_me,
    'attendanceRequired', v_active and not v_is_executive,
    'selfPunchEnabled', v_active and not v_is_executive,
    'activePasskeys', v_devices,
    'hasActivePasskey', v_devices > 0,
    'canPunch', v_active and not v_is_executive and v_devices > 0,
    'suggestedAction', v_suggested,
    'lastEventType', v_last.event_type,
    'lastEventAt', v_last.event_at,
    'lastEventStatus', v_last.status,
    'todayStatus', v_today_status,
    'lastUpdatedAt', now()
  );
end;
$$;

revoke all on function public.get_my_attendance_state() from public, anon, authenticated;
grant execute on function public.get_my_attendance_state() to authenticated;

create or replace function public.set_employee_attendance_device_status(
  p_device_id uuid,
  p_status text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device public.employee_devices;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('access.account.manage_devices')
  ) then
    raise exception 'device management permission required' using errcode = '42501';
  end if;
  if p_status not in ('pending','active','blocked','revoked','replaced') then
    raise exception 'invalid device status' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'device status reason is required' using errcode = '22023';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;
  if not found then
    raise exception 'device not found' using errcode = 'P0002';
  end if;

  update public.employee_devices
  set status = p_status,
      revoked_at = case
        when p_status in ('revoked','replaced') then coalesce(revoked_at, now())
        else null
      end,
      metadata = metadata || jsonb_build_object(
        'lastStatusReason', trim(p_reason),
        'lastStatusActor', auth.uid(),
        'lastStatusAt', now()
      )
  where id = p_device_id
  returning * into v_device;

  if p_status = 'active' then
    update public.passkey_credentials
    set status = 'active', trusted = true, updated_at = now()
    where employee_id = v_device.employee_id
      and user_id = v_device.user_id
      and credential_id = v_device.credential_id;
  elsif p_status in ('revoked','replaced') then
    update public.passkey_credentials
    set status = 'revoked', trusted = false, updated_at = now()
    where employee_id = v_device.employee_id
      and user_id = v_device.user_id
      and credential_id = v_device.credential_id;
  end if;

  perform public.log_audit_event(
    'attendance.device_status_changed', 'security', 'warning',
    'employee_devices', v_device.id,
    'تغيير حالة جهاز الحضور', trim(p_reason),
    jsonb_build_object(
      'employeeId', v_device.employee_id,
      'status', p_status,
      'credentialId', v_device.credential_id
    )
  );

  return jsonb_build_object(
    'id', v_device.id,
    'employeeId', v_device.employee_id,
    'status', v_device.status
  );
end;
$$;

revoke all on function public.set_employee_attendance_device_status(uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.set_employee_attendance_device_status(uuid,text,text)
  to authenticated;

-- Idempotency ledger for the local-biometric attendance path. The biometric
-- material remains on-device; the server still enforces session, canonical
-- device status, GPS policy and a stable operation UUID.
create table if not exists public.local_attendance_operations (
  operation_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  event_type text not null check (event_type in ('CHECK_IN','CHECK_OUT')),
  credential_id text not null,
  status text not null default 'processing'
    check (status in ('processing','completed','rejected')),
  result jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table public.local_attendance_operations enable row level security;
revoke all on table public.local_attendance_operations from public, anon, authenticated;

create or replace function public.punch_attendance_local_v2(
  p_operation_id uuid,
  p_event_type text,
  p_credential_id text,
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
  v_operation public.local_attendance_operations;
  v_result jsonb;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'authenticated employee is required' using errcode = '42501';
  end if;
  if p_operation_id is null then
    raise exception 'attendance_operation_id_required' using errcode = '22023';
  end if;

  insert into public.local_attendance_operations(
    operation_id, user_id, employee_id, event_type, credential_id
  ) values (
    p_operation_id, auth.uid(), v_employee_id, p_event_type, p_credential_id
  ) on conflict (operation_id) do nothing;

  select * into v_operation
  from public.local_attendance_operations
  where operation_id = p_operation_id
  for update;

  if v_operation.user_id <> auth.uid()
     or v_operation.employee_id <> v_employee_id
     or v_operation.event_type <> p_event_type
     or v_operation.credential_id <> p_credential_id then
    raise exception 'attendance_idempotency_conflict' using errcode = '22023';
  end if;
  if v_operation.status in ('completed','rejected') then
    return coalesce(v_operation.result, '{}'::jsonb)
      || jsonb_build_object('replayed', true);
  end if;

  v_result := public.punch_attendance_local(
    p_event_type,
    p_credential_id,
    p_latitude,
    p_longitude,
    p_accuracy_meters,
    p_is_mock,
    null
  );

  update public.local_attendance_operations
  set status = case when coalesce((v_result->>'ok')::boolean, false)
                    then 'completed' else 'rejected' end,
      result = v_result,
      completed_at = now()
  where operation_id = p_operation_id;

  return v_result || jsonb_build_object('replayed', false);
end;
$$;

revoke all on function public.punch_attendance_local_v2(
  uuid,text,text,double precision,double precision,double precision,boolean
) from public, anon, authenticated;
grant execute on function public.punch_attendance_local_v2(
  uuid,text,text,double precision,double precision,double precision,boolean
) to authenticated;

-- Normalize all new urgent location notifications to the immutable v4 channel
-- and make the verified HTTPS App Link the primary route.
create or replace function public.normalize_live_location_notification()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_request_id text;
  v_deep_link text;
begin
  if new.entity_type is distinct from 'live_location_request' then
    return new;
  end if;
  v_request_id := coalesce(new.metadata->>'requestId', new.entity_id::text);
  if nullif(v_request_id, '') is null then
    return new;
  end if;
  v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_request_id;
  new.action_url := v_deep_link;
  new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
    'fullScreen', true,
    'kind', 'live_location_request',
    'requestId', v_request_id,
    'entityId', v_request_id,
    'channel', 'urgent_location_v4',
    'sound', 'urgent_notification',
    'deepLink', v_deep_link
  );
  return new;
end;
$$;

drop trigger if exists trg_normalize_live_location_notification on public.notifications;
create trigger trg_normalize_live_location_notification
before insert or update of action_url, metadata on public.notifications
for each row execute function public.normalize_live_location_notification();

update public.notifications
set metadata = metadata,
    action_url = action_url
where entity_type = 'live_location_request';

alter table public.notification_delivery_log
  drop constraint if exists notification_delivery_log_status_check;
alter table public.notification_delivery_log
  add constraint notification_delivery_log_status_check
  check (status in (
    'queued','token_missing','sent','delivered','opened','failed','bounced'
  ));

create or replace function public.mark_my_notification_delivery(
  p_notification_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_log public.notification_delivery_log;
  v_subscription_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;
  if p_status not in ('delivered','opened') then
    raise exception 'invalid delivery status' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.notifications n
    where n.id = p_notification_id and n.recipient_user_id = auth.uid()
  ) then
    raise exception 'notification not owned by current user' using errcode = '42501';
  end if;

  select * into v_log
  from public.notification_delivery_log l
  where l.notification_id = p_notification_id
    and l.recipient_user_id = auth.uid()
    and l.channel = 'push'
  order by l.created_at desc
  limit 1
  for update;

  if v_log.id is null then
    select id into v_subscription_id
    from public.push_subscriptions
    where user_id = auth.uid() and is_active
    order by last_seen_at desc nulls last, created_at desc
    limit 1;

    insert into public.notification_delivery_log(
      notification_id, subscription_id, recipient_user_id,
      channel, status, attempts, sent_at, delivered_at
    ) values (
      p_notification_id, v_subscription_id, auth.uid(),
      'push', p_status, 1, now(), now()
    );
  elsif v_log.status <> 'opened' or p_status = 'opened' then
    update public.notification_delivery_log
    set status = p_status,
        delivered_at = coalesce(delivered_at, now()),
        updated_at = now()
    where id = v_log.id;
  end if;
end;
$$;

revoke all on function public.mark_my_notification_delivery(uuid,text)
  from public, anon, authenticated;
grant execute on function public.mark_my_notification_delivery(uuid,text)
  to authenticated;

-- Video-required requests cannot use the old location-only waiver.
create or replace function public.complete_my_live_location_request(p_request_id uuid)
returns public.live_location_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.live_location_requests;
  v_mode text;
begin
  select * into v_row
  from public.live_location_requests
  where id = p_request_id and employee_id = v_me
  for update;
  if not found then
    raise exception 'active request not found' using errcode = 'P0002';
  end if;
  if v_row.status not in ('accepted','active') or v_row.expires_at <= now() then
    raise exception 'location session is not active' using errcode = '22023';
  end if;

  v_mode := coalesce(v_row.metadata->>'mode', 'snapshot');
  if v_mode in ('snapshot','location_video') and not exists (
    select 1 from public.employee_locations
    where live_request_id = p_request_id and employee_id = v_me
  ) then
    raise exception 'location point is required' using errcode = '22023';
  end if;
  if v_mode in ('video_5s','location_video') and not exists (
    select 1 from public.live_location_videos_meta
    where live_request_id = p_request_id
      and employee_id = v_me
      and status = 'ready'
      and duration_seconds between 4 and 7
      and size_bytes > 0
  ) then
    raise exception 'video_required' using errcode = '22023';
  end if;

  update public.live_location_requests
  set status = 'completed',
      expires_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'videoWaived', false,
        'completionMode', 'verified',
        'completedAt', now()
      )
  where id = p_request_id
  returning * into v_row;

  perform public.log_audit_event(
    'live_location_completed', 'security', 'info',
    'live_location_requests', p_request_id,
    'إكمال طلب الموقع بعد التحقق من المتطلبات', null,
    jsonb_build_object('mode', v_mode, 'completionMode', 'verified')
  );
  return v_row;
end;
$$;

revoke all on function public.complete_my_live_location_request(uuid)
  from public, anon, authenticated;
grant execute on function public.complete_my_live_location_request(uuid)
  to authenticated;

notify pgrst, 'reload schema';
commit;
