-- Migration 0027: Controlled decision lifecycle, versions, voting and execution tracking

alter table public.administrative_decisions drop constraint if exists administrative_decisions_status_check;
alter table public.administrative_decisions add constraint administrative_decisions_status_check
  check (status in ('draft','in_review','approved','scheduled','published','archived','revoked'));

alter table public.administrative_decisions
  add column if not exists version_no integer not null default 1,
  add column if not exists review_due_at timestamptz,
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by uuid references public.employees(id) on delete set null,
  add column if not exists scheduled_for timestamptz,
  add column if not exists implementation_owner_id uuid references public.employees(id) on delete set null,
  add column if not exists implementation_due_at timestamptz,
  add column if not exists expected_outcome text,
  add column if not exists success_metric text,
  add column if not exists baseline_value numeric,
  add column if not exists target_value numeric,
  add column if not exists actual_value numeric,
  add column if not exists impact_review_at timestamptz;

create table if not exists public.decision_versions (
  id uuid primary key default gen_random_uuid(),
  decision_id uuid not null references public.administrative_decisions(id) on delete cascade,
  version_no integer not null,
  title text not null,
  body text,
  category text not null,
  effective_date date,
  expiry_date date,
  change_reason text,
  content_hash text not null,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique(decision_id,version_no)
);

create table if not exists public.decision_actions (
  id uuid primary key default gen_random_uuid(),
  decision_id uuid not null references public.administrative_decisions(id) on delete cascade,
  action_type text not null check(action_type in ('create','submit_review','approve','return','schedule','publish','archive','revoke','impact_review')),
  from_status text,
  to_status text,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  actor_employee_id uuid references public.employees(id) on delete set null,
  actor_user_id uuid references auth.users(id)
);

create table if not exists public.decision_execution_items (
  id uuid primary key default gen_random_uuid(),
  decision_id uuid not null references public.administrative_decisions(id) on delete cascade,
  title text not null,
  owner_employee_id uuid references public.employees(id) on delete set null,
  due_at timestamptz,
  status text not null default 'not_started' check(status in ('not_started','in_progress','blocked','completed','cancelled')),
  progress_percent integer not null default 0 check(progress_percent between 0 and 100),
  blocker text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);

create table if not exists public.decision_polls (
  id uuid primary key default gen_random_uuid(),
  decision_id uuid references public.administrative_decisions(id) on delete cascade,
  question text not null,
  poll_type text not null default 'yes_no' check(poll_type in ('yes_no','single_choice','multiple_choice','rating')),
  is_anonymous boolean not null default false,
  opens_at timestamptz not null default now(),
  closes_at timestamptz not null,
  quorum_percent numeric(5,2),
  approval_threshold_percent numeric(5,2),
  status text not null default 'draft' check(status in ('draft','open','closed','certified','cancelled')),
  results_visible_before_close boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create table if not exists public.decision_poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.decision_polls(id) on delete cascade,
  label text not null,
  sort_order integer not null default 0,
  unique(poll_id,label)
);

create table if not exists public.decision_poll_eligibility (
  poll_id uuid not null references public.decision_polls(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(poll_id,employee_id)
);

create table if not exists public.decision_poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.decision_polls(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  option_ids uuid[] not null default '{}',
  rating numeric(5,2),
  cast_at timestamptz not null default now(),
  updated_at timestamptz,
  unique(poll_id,employee_id)
);

alter table public.decision_versions enable row level security;
alter table public.decision_actions enable row level security;
alter table public.decision_execution_items enable row level security;
alter table public.decision_polls enable row level security;
alter table public.decision_poll_options enable row level security;
alter table public.decision_poll_eligibility enable row level security;
alter table public.decision_poll_votes enable row level security;

create policy decision_versions_read on public.decision_versions for select to authenticated using (
  public.current_is_full_access() or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
  or exists(select 1 from public.decision_recipients r where r.decision_id=decision_versions.decision_id and r.employee_id=public.current_employee_id())
);
create policy decision_actions_read on public.decision_actions for select to authenticated using (public.current_is_full_access() or public.has_any_permission(array['comms.decision.read','comms.decision.manage']));
create policy decision_execution_read on public.decision_execution_items for select to authenticated using (
  public.current_is_full_access() or public.has_any_permission(array['comms.decision.read','comms.decision.manage']) or owner_employee_id=public.current_employee_id()
  or exists(select 1 from public.decision_recipients r where r.decision_id=decision_execution_items.decision_id and r.employee_id=public.current_employee_id())
);
create policy decision_polls_read on public.decision_polls for select to authenticated using (
  public.current_is_full_access() or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
  or exists(select 1 from public.decision_poll_eligibility e where e.poll_id=decision_polls.id and e.employee_id=public.current_employee_id())
);
create policy decision_poll_options_read on public.decision_poll_options for select to authenticated using (
  exists(select 1 from public.decision_polls p where p.id=decision_poll_options.poll_id)
);
create policy decision_poll_eligibility_self on public.decision_poll_eligibility for select to authenticated using (
  public.current_is_full_access() or public.has_permission('comms.decision.manage') or employee_id=public.current_employee_id()
);
create policy decision_poll_votes_self on public.decision_poll_votes for select to authenticated using (
  public.current_is_full_access() or public.has_permission('comms.decision.manage') or employee_id=public.current_employee_id()
);

-- Remove direct writes; lifecycle must use RPCs.
drop policy if exists admin_decisions_write on public.administrative_decisions;
revoke insert,update,delete on public.administrative_decisions from authenticated;
revoke insert,update,delete on public.decision_versions from authenticated;
revoke insert,update,delete on public.decision_actions from authenticated;
revoke insert,update,delete on public.decision_execution_items from authenticated;
revoke insert,update,delete on public.decision_polls from authenticated;
revoke insert,update,delete on public.decision_poll_options from authenticated;
revoke insert,update,delete on public.decision_poll_eligibility from authenticated;
revoke insert,update,delete on public.decision_poll_votes from authenticated;

create or replace function public.decision_content_hash(p_title text,p_body text,p_version integer)
returns text language sql immutable as $$ select encode(digest(coalesce(p_title,'')||E'\n'||coalesce(p_body,'')||E'\n'||p_version::text,'sha256'),'hex') $$;

create or replace function public.create_decision_draft(
  p_title text,p_body text,p_category text default 'general',p_effective_date date default null,
  p_requires_read_receipt boolean default true,p_expected_outcome text default null,p_success_metric text default null
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_emp uuid:=public.current_employee_id();
begin
  if not(public.current_is_full_access() or public.has_permission('comms.decision.manage')) then raise exception 'FORBIDDEN'; end if;
  if length(trim(p_title))<3 or length(trim(coalesce(p_body,'')))<10 then raise exception 'INVALID_CONTENT'; end if;
  insert into public.administrative_decisions(title,body,category,status,target_type,issued_by,effective_date,requires_read_receipt,expected_outcome,success_metric,created_by)
  values(trim(p_title),trim(p_body),p_category,'draft','selected',v_emp,p_effective_date,p_requires_read_receipt,p_expected_outcome,p_success_metric,auth.uid()) returning id into v_id;
  insert into public.decision_versions(decision_id,version_no,title,body,category,effective_date,content_hash,created_by)
  values(v_id,1,trim(p_title),trim(p_body),p_category,p_effective_date,public.decision_content_hash(trim(p_title),trim(p_body),1),auth.uid());
  insert into public.decision_actions(decision_id,action_type,to_status,actor_employee_id,actor_user_id) values(v_id,'create','draft',v_emp,auth.uid());
  return v_id;
end $$;

create or replace function public.transition_decision(
  p_decision_id uuid,p_action text,p_reason text default null,p_scheduled_for timestamptz default null
) returns public.administrative_decisions language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.administrative_decisions; v_from text; v_to text; v_emp uuid:=public.current_employee_id();
begin
  select * into strict v_row from public.administrative_decisions where id=p_decision_id for update;
  v_from:=v_row.status;
  if p_action='submit_review' and v_from='draft' then v_to:='in_review';
  elsif p_action='approve' and v_from='in_review' then
    if not(public.current_is_full_access() or public.has_permission('comms.decision.approve')) then raise exception 'FORBIDDEN'; end if;
    v_to:='approved';
  elsif p_action='return' and v_from='in_review' then v_to:='draft';
  elsif p_action='schedule' and v_from='approved' and p_scheduled_for>now() then v_to:='scheduled';
  elsif p_action='publish' and v_from in ('approved','scheduled') then v_to:='published';
  elsif p_action='archive' and v_from='published' then v_to:='archived';
  elsif p_action='revoke' and v_from in ('approved','scheduled','published') then v_to:='revoked';
  else raise exception 'INVALID_DECISION_TRANSITION'; end if;
  if p_action in ('return','revoke') and length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED'; end if;
  if p_action not in ('approve') and not(public.current_is_full_access() or public.has_permission('comms.decision.manage')) then raise exception 'FORBIDDEN'; end if;
  update public.administrative_decisions set status=v_to,
    approved_at=case when v_to='approved' then now() else approved_at end,
    approved_by=case when v_to='approved' then v_emp else approved_by end,
    scheduled_for=case when v_to='scheduled' then p_scheduled_for else scheduled_for end,
    published_at=case when v_to='published' then now() else published_at end,
    updated_at=now()
  where id=p_decision_id returning * into v_row;
  insert into public.decision_actions(decision_id,action_type,from_status,to_status,reason,actor_employee_id,actor_user_id)
  values(p_decision_id,p_action,v_from,v_to,nullif(trim(coalesce(p_reason,'')),''),v_emp,auth.uid());
  perform public.log_audit_event('decision.'||p_action,'governance',case when p_action='revoke' then 'warning' else 'info' end,'administrative_decisions',p_decision_id,'انتقال قرار من '||v_from||' إلى '||v_to,p_reason,jsonb_build_object('from',v_from,'to',v_to));
  return v_row;
end $$;

create or replace function public.cast_decision_vote(p_poll_id uuid,p_option_ids uuid[] default '{}',p_rating numeric default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_poll public.decision_polls; v_emp uuid:=public.current_employee_id(); v_id uuid;
begin
  select * into strict v_poll from public.decision_polls where id=p_poll_id for update;
  if v_poll.status<>'open' or now()<v_poll.opens_at or now()>v_poll.closes_at then raise exception 'POLL_NOT_OPEN'; end if;
  if not exists(select 1 from public.decision_poll_eligibility where poll_id=p_poll_id and employee_id=v_emp) then raise exception 'NOT_ELIGIBLE'; end if;
  if v_poll.poll_type='yes_no' and cardinality(p_option_ids)<>1 then raise exception 'ONE_OPTION_REQUIRED'; end if;
  if v_poll.poll_type='single_choice' and cardinality(p_option_ids)<>1 then raise exception 'ONE_OPTION_REQUIRED'; end if;
  if v_poll.poll_type='rating' and (p_rating is null or p_rating<1 or p_rating>5) then raise exception 'INVALID_RATING'; end if;
  insert into public.decision_poll_votes(poll_id,employee_id,option_ids,rating,cast_at,updated_at)
  values(p_poll_id,v_emp,coalesce(p_option_ids,'{}'),p_rating,now(),now())
  on conflict(poll_id,employee_id) do update set option_ids=excluded.option_ids,rating=excluded.rating,updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.acknowledge_decision(p_decision_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id();
begin
  if not exists(select 1 from public.decision_recipients where decision_id=p_decision_id and employee_id=v_emp) then raise exception 'NOT_A_RECIPIENT'; end if;
  insert into public.decision_reads(decision_id,employee_id,read_at,acknowledged,acknowledged_at,created_by)
  values(p_decision_id,v_emp,now(),true,now(),auth.uid())
  on conflict(decision_id,employee_id) do update set acknowledged=true,acknowledged_at=now(),updated_at=now();
end $$;

revoke execute on function public.create_decision_draft(text,text,text,date,boolean,text,text) from public;
grant execute on function public.create_decision_draft(text,text,text,date,boolean,text,text) to authenticated;
revoke execute on function public.transition_decision(uuid,text,text,timestamptz) from public;
grant execute on function public.transition_decision(uuid,text,text,timestamptz) to authenticated;
revoke execute on function public.cast_decision_vote(uuid,uuid[],numeric) from public;
grant execute on function public.cast_decision_vote(uuid,uuid[],numeric) to authenticated;
revoke execute on function public.acknowledge_decision(uuid) from public;
grant execute on function public.acknowledge_decision(uuid) to authenticated;
