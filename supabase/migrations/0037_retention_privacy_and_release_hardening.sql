-- Ahla Shabab Management OS V8
-- Privacy retention, legal holds, and release hardening.

alter table public.live_location_videos_meta
  add column if not exists retention_delete_after timestamptz,
  add column if not exists legal_hold_until timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists deletion_reason text;

create or replace function public.set_live_video_retention()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.retention_delete_after is null then
    new.retention_delete_after := coalesce(new.captured_at, new.created_at, now()) + interval '24 hours';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_live_video_retention on public.live_location_videos_meta;
create trigger trg_live_video_retention
before insert or update of captured_at, retention_delete_after
on public.live_location_videos_meta
for each row execute function public.set_live_video_retention();

update public.live_location_videos_meta
set retention_delete_after = coalesce(captured_at, created_at, now()) + interval '24 hours'
where retention_delete_after is null;

create index if not exists ix_live_video_retention_due
  on public.live_location_videos_meta(retention_delete_after)
  where deleted_at is null and status <> 'deleted';

create table if not exists public.live_location_video_access_logs (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references public.live_location_videos_meta(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_employee_id uuid references public.employees(id) on delete set null,
  action text not null check (action in ('view','signed_url','download','delete','legal_hold','release_hold')),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index if not exists ix_live_video_access_video_time
  on public.live_location_video_access_logs(video_id, occurred_at desc);

alter table public.live_location_video_access_logs enable row level security;

drop policy if exists live_video_access_logs_read on public.live_location_video_access_logs;
create policy live_video_access_logs_read
on public.live_location_video_access_logs
for select to authenticated
using (
  public.current_is_full_access()
  or public.has_permission('live_location.read_access_log')
  or public.has_permission('live_location.manage_retention')
);

revoke insert, update, delete on public.live_location_video_access_logs from authenticated;

create or replace function public.list_retention_video_candidates(p_limit integer default 100)
returns table(video_id uuid, storage_bucket text, storage_path text)
language sql
security definer
set search_path = public, auth
as $$
  select v.id, coalesce(v.storage_bucket, 'live-location-videos'), v.storage_path
  from public.live_location_videos_meta v
  where v.deleted_at is null
    and v.status <> 'deleted'
    and v.storage_path is not null
    and v.retention_delete_after <= now()
    and (v.legal_hold_until is null or v.legal_hold_until <= now())
  order by v.retention_delete_after
  limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

create or replace function public.mark_retention_video_deleted(
  p_video_id uuid,
  p_reason text default 'retention_expired'
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  update public.live_location_videos_meta
  set status = 'deleted',
      deleted_at = now(),
      deletion_reason = coalesce(nullif(trim(p_reason), ''), 'retention_expired'),
      updated_at = now()
  where id = p_video_id
    and deleted_at is null;

  if found then
    insert into public.live_location_video_access_logs(
      video_id, actor_user_id, actor_employee_id, action, reason, metadata
    ) values (
      p_video_id, auth.uid(), public.current_employee_id(), 'delete',
      coalesce(nullif(trim(p_reason), ''), 'retention_expired'),
      jsonb_build_object('source', 'retention_worker')
    );
  end if;
end;
$$;

create or replace function public.cleanup_expired_ephemeral_records(p_batch integer default 1000)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_challenges integer := 0;
  v_resets integer := 0;
  v_notification_jobs integer := 0;
  v_report_runs integer := 0;
  v_limit integer := greatest(1, least(coalesce(p_batch, 1000), 5000));
begin
  with doomed as (
    select id from public.webauthn_challenges
    where expires_at < now() - interval '1 day'
       or (used_at is not null and used_at < now() - interval '1 day')
    order by expires_at
    limit v_limit
  )
  delete from public.webauthn_challenges w using doomed d where w.id = d.id;
  get diagnostics v_challenges = row_count;

  with doomed as (
    select id from public.password_reset_requests
    where expires_at < now() - interval '7 days'
    order by expires_at
    limit v_limit
  )
  delete from public.password_reset_requests p using doomed d where p.id = d.id;
  get diagnostics v_resets = row_count;

  with doomed as (
    select id from public.notification_jobs
    where status in ('sent','cancelled') and created_at < now() - interval '30 days'
    order by created_at
    limit v_limit
  )
  delete from public.notification_jobs n using doomed d where n.id = d.id;
  get diagnostics v_notification_jobs = row_count;

  with doomed as (
    select id from public.report_runs
    where status in ('completed','cancelled') and created_at < now() - interval '180 days'
    order by created_at
    limit v_limit
  )
  delete from public.report_runs r using doomed d where r.id = d.id;
  get diagnostics v_report_runs = row_count;

  return jsonb_build_object(
    'webauthnChallenges', v_challenges,
    'passwordResetRequests', v_resets,
    'notificationJobs', v_notification_jobs,
    'reportRuns', v_report_runs,
    'completedAt', now()
  );
end;
$$;

revoke execute on function public.list_retention_video_candidates(integer) from public, authenticated, anon;
revoke execute on function public.mark_retention_video_deleted(uuid, text) from public, authenticated, anon;
revoke execute on function public.cleanup_expired_ephemeral_records(integer) from public, authenticated, anon;
grant execute on function public.list_retention_video_candidates(integer) to service_role;
grant execute on function public.mark_retention_video_deleted(uuid, text) to service_role;
grant execute on function public.cleanup_expired_ephemeral_records(integer) to service_role;
