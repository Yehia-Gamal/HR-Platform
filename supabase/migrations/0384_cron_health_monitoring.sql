-- migration: 0384
-- description: cron health monitoring for process_request_sla + escalation audit

begin;

-- ── cron health log ──────────────────────────────────────────────────────────
create table if not exists public.cron_health_log (
  id           bigserial primary key,
  job_name     text        not null,
  ran_at       timestamptz not null default now(),
  rows_affected integer     not null default 0,
  status       text        not null default 'ok' check (status in ('ok','error')),
  detail       text
);

create index if not exists idx_cron_health_log_job_ran
  on public.cron_health_log(job_name, ran_at desc);

-- only service_role and full-access can read
alter table public.cron_health_log enable row level security;
create policy "full_access_read_cron_health"
  on public.cron_health_log for select
  using (current_is_full_access());

-- ── update process_request_sla to log health ─────────────────────────────────
create or replace function public.process_request_sla(
  p_limit integer default 100
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count    integer := 0;
  v_req      record;
begin
  if auth.role() <> 'service_role' and not current_is_full_access() then
    raise exception 'PERMISSION_DENIED';
  end if;

  for v_req in
    select id
    from public.requests
    where status = 'pending'
      and workflow_status not in ('completed', 'terminated')
      and decision_due_at < now()
    limit p_limit
  loop
    update public.requests
    set workflow_status = 'escalated',
        updated_at      = now()
    where id = v_req.id;

    insert into public.request_actions(request_id, action, actor_type, note)
    values (v_req.id, 'escalated', 'system', 'تصعيد تلقائي — انتهت مهلة الاعتماد');

    v_count := v_count + 1;
  end loop;

  -- log health
  insert into public.cron_health_log(job_name, rows_affected, status)
  values ('process_request_sla', v_count, 'ok');

  return v_count;

exception when others then
  insert into public.cron_health_log(job_name, rows_affected, status, detail)
  values ('process_request_sla', 0, 'error', sqlerrm);
  raise;
end;
$$;

-- ── admin RPC to check cron health ──────────────────────────────────────────
create or replace function public.get_cron_health()
returns table(
  job_name     text,
  last_run     timestamptz,
  minutes_ago  numeric,
  last_status  text,
  is_healthy   boolean
)
language sql
security definer
set search_path = public
as $$
  select
    job_name,
    max(ran_at)                                     as last_run,
    round(extract(epoch from now() - max(ran_at)) / 60, 1) as minutes_ago,
    (array_agg(status order by ran_at desc))[1]     as last_status,
    max(ran_at) > now() - interval '30 minutes'     as is_healthy
  from public.cron_health_log
  group by job_name;
$$;

revoke all on function public.get_cron_health() from anon;
grant execute on function public.get_cron_health() to authenticated;

commit;
