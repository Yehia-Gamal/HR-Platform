-- Restore the production FCM pipeline for urgent live-location requests.
--
-- 0108 stopped populating the legacy Web Push NOT NULL columns on
-- push_subscriptions. Every Android token registration therefore failed and
-- queue_notification_jobs silently omitted the push job. Keep the mixed
-- Web/FCM table compatible, recover pending urgent jobs after registration,
-- and always make live-location push failures observable.

create or replace function public.upsert_my_push_token(
  p_fcm_token text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_token text := trim(p_fcm_token);
  v_now timestamptz := now();
  v_recovered integer := 0;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if length(v_token) < 16 then
    raise exception 'token_too_short' using errcode = '22023';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'invalid_platform' using errcode = '22023';
  end if;

  -- One physical FCM token must never remain active for two signed-in users.
  update public.push_subscriptions
  set is_active = false,
      updated_at = v_now
  where fcm_token = v_token
    and user_id <> v_user_id
    and is_active;

  insert into public.push_subscriptions(
    user_id,
    endpoint,
    p256dh_key,
    auth_key,
    fcm_token,
    platform,
    is_active,
    last_used_at,
    created_by
  ) values (
    v_user_id,
    'fcm://' || v_token,
    '-',
    '-',
    v_token,
    p_platform,
    true,
    v_now,
    v_user_id
  )
  on conflict (user_id, fcm_token) where fcm_token is not null
  do update set
    endpoint = excluded.endpoint,
    p256dh_key = excluded.p256dh_key,
    auth_key = excluded.auth_key,
    platform = excluded.platform,
    is_active = true,
    last_used_at = v_now,
    updated_at = v_now;

  -- A request may have been created before the first successful token upsert.
  -- Insert its missing push job, or retry a previously terminal token_missing
  -- job, while never redelivering a job already marked sent.
  insert into public.notification_jobs(
    notification_id,
    recipient_user_id,
    channel,
    status,
    available_at,
    attempts,
    idempotency_key
  )
  select
    n.id,
    n.recipient_user_id,
    'push',
    'queued',
    v_now,
    0,
    n.id::text || ':push'
  from public.notifications n
  join public.live_location_requests r
    on r.id = n.entity_id
  where n.recipient_user_id = v_user_id
    and n.entity_type = 'live_location_request'
    and r.status in ('pending', 'accepted', 'active')
    and (r.expires_at is null or r.expires_at > v_now)
  on conflict (idempotency_key)
  do update set
    status = 'queued',
    available_at = v_now,
    attempts = 0,
    last_error = null,
    locked_at = null,
    locked_by = null
  where public.notification_jobs.status in ('failed', 'cancelled');

  get diagnostics v_recovered = row_count;
  if v_recovered > 0 then
    perform public.nudge_notification_dispatcher();
  end if;
end;
$$;

revoke all on function public.upsert_my_push_token(text, text)
  from public, anon, authenticated;
grant execute on function public.upsert_my_push_token(text, text)
  to authenticated;

create or replace function public.queue_notification_jobs()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  insert into public.notification_jobs(
    notification_id, recipient_user_id, channel, idempotency_key
  ) values (
    new.id, new.recipient_user_id, 'in_app', new.id::text || ':in_app'
  )
  on conflict (idempotency_key) do nothing;

  -- Urgent location requests must have a visible push delivery state even if
  -- the application has not registered its token yet. Token registration will
  -- recover a token_missing job through upsert_my_push_token above.
  if new.entity_type = 'live_location_request'
     or exists(
       select 1
       from public.push_subscriptions s
       where s.user_id = new.recipient_user_id
         and s.is_active
         and s.fcm_token is not null
     ) then
    insert into public.notification_jobs(
      notification_id, recipient_user_id, channel, idempotency_key
    ) values (
      new.id, new.recipient_user_id, 'push', new.id::text || ':push'
    )
    on conflict (idempotency_key) do nothing;
  end if;

  return new;
end;
$$;

revoke all on function public.queue_notification_jobs()
  from public, anon, authenticated;

drop trigger if exists trg_notifications_queue_jobs on public.notifications;
create trigger trg_notifications_queue_jobs
after insert on public.notifications
for each row execute function public.queue_notification_jobs();

notify pgrst, 'reload schema';

